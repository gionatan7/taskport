import { lstat, readdir, readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const patterns = [
  ['personal home path', /\/(?:Users|home)\/[^\s/"'<>\x00]+(?:\/|(?=$|[\s"'<>\x00]))/],
  ['private temporary path', /\/(?:private\/)?var\/folders\//],
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['access token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-)?[A-Za-z0-9_-]{40,}|AKIA[A-Z0-9]{16})\b/],
  ['credential in URL', /https?:\/\/[^\s/:]+:[^\s/@]+@/],
];

/** Inspect every packaged file, including binary strings; never return matched values. */
export const checkAppPrivacy = async (bundle, forbiddenPrefixes = [sourceRoot, homedir()], forbiddenIdentities = []) => {
  const root = resolve(bundle);
  const findings = [];
  let files = 0;
  const prefixes = forbiddenPrefixes.filter(prefix => prefix && prefix !== '/')
    .flatMap(prefix => [prefix, encodeURI(prefix)]);
  const identities = forbiddenIdentities.filter(value => value.length >= 4)
    .map(value => value.normalize('NFC').toLowerCase());
  const inspect = (text, file) => {
    for (const [reason, pattern] of patterns) {
      if (pattern.test(text)) findings.push({ file, reason });
    }
    if (prefixes.some(prefix => text.includes(prefix))) findings.push({ file, reason: 'local build/home path' });
    const normalized = text.normalize('NFC').toLowerCase();
    if (identities.some(value => normalized.includes(value))) findings.push({ file, reason: 'local identity marker' });
  };
  const walk = async (directory) => {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      const file = relative(root, path);
      // Do not follow links out of the bundle or silently skip unscannable entries.
      if (entry.isSymbolicLink() || (!entry.isDirectory() && !entry.isFile())) {
        findings.push({ file, reason: 'unexpected non-file entry' });
        continue;
      }
      inspect(file, file);
      if (/^(?:\.DS_Store|\.env(?:\..+)?|.*\.(?:dSYM|swiftmodule|swiftdeps|o|a|log|p12|pfx|key|pem|mobileprovision))$/i.test(entry.name)) {
        findings.push({ file, reason: 'private configuration or build artifact' });
      }
      if (entry.isDirectory()) { await walk(path); continue; }
      files++;
      const bytes = await readFile(path);
      // Check UTF-8 and NUL-padded strings (including UTF-16 paths) inside binaries.
      const text = bytes.toString('utf8');
      inspect(text, file);
      if (text.includes('\0')) inspect(text.replaceAll('\0', ''), file);
      // UTF-16 decoding also catches non-ASCII names that NUL removal cannot reconstruct.
      inspect(bytes.toString('utf16le'), file);
      const evenBytes = Buffer.from(bytes.subarray(0, bytes.length - bytes.length % 2));
      inspect(evenBytes.swap16().toString('utf16le'), file);
    }
  };
  const metadata = await lstat(root);
  if (!metadata.isDirectory() || metadata.isSymbolicLink()) throw new Error('Expected a real bundle directory');
  await walk(root);
  if (!files) findings.push({ file: '.', reason: 'empty bundle' });
  const unique = [...new Map(findings.map(item => [`${item.file}:${item.reason}`, item])).values()];
  const privateFiles = new Map();
  for (const item of unique) {
    if (patterns.some(([, pattern]) => pattern.test(item.file)) || prefixes.some(prefix => item.file.includes(prefix))
      || identities.some(value => item.file.normalize('NFC').toLowerCase().includes(value))) {
      if (!privateFiles.has(item.file)) privateFiles.set(item.file, `[redacted filename ${privateFiles.size + 1}]`);
      item.file = privateFiles.get(item.file);
    }
  }
  return { files, findings: unique };
};

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const localIdentities = process.argv.length === 4 && process.argv[3] === '--local-identities';
  if (process.argv.length !== 3 && !localIdentities) {
    console.error('Usage: bun scripts/check-app-privacy.mjs APP_BUNDLE [--local-identities]');
    process.exitCode = 2;
  } else {
    try {
      const identities = [];
      if (localIdentities) {
        for (const [command, args] of [
          ['id', ['-un']], ['id', ['-F']],
          ['git', ['-C', sourceRoot, 'config', 'user.name']],
          ['git', ['-C', sourceRoot, 'config', 'user.email']],
          ['scutil', ['--get', 'ComputerName']], ['scutil', ['--get', 'LocalHostName']],
          ['scutil', ['--get', 'HostName']],
          ['hostname', []],
        ]) {
          try {
            const value = execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
            if (value.length >= 4) identities.push(value);
            if (command === 'id' && args[0] === '-F') identities.push(...value.split(/\s+/).filter(part => part.length >= 4));
          } catch {
            // Optional Git and machine names may be unset; the login name is mandatory.
            if (command === 'id' && args[0] === '-un') throw new Error('Could not read local login name');
          }
        }
        try {
          const hardware = execFileSync('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice'],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
          for (const match of hardware.matchAll(/"IOPlatform(?:SerialNumber|UUID)"\s*=\s*"([^"]+)"/g)) identities.push(match[1]);
        } catch {
          console.log('Hardware serial/UUID markers unavailable; this portion of the audit was skipped.');
        }
        console.log(`Checking ${new Set(identities).size} local identity markers; values are never reported.`);
      }
      const result = await checkAppPrivacy(process.argv[2], undefined, identities);
      for (const finding of result.findings) console.error(`${finding.file}: ${finding.reason}`);
      console.log(`Checked ${result.files} packaged files; ${result.findings.length} potential privacy issues.`);
      console.log('Heuristic check only; this is not a full secrets or license-compliance audit.');
      process.exitCode = result.findings.length ? 1 : 0;
    } catch {
      console.error('Bundle privacy check failed: could not inspect every packaged file.');
      process.exitCode = 1;
    }
  }
}
