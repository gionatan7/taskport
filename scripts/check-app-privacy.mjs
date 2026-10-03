import { lstat, readdir, readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const patterns = [
  ['personal home path', /\/(?:Users|home)\/[^\s/"'<>\x00]+(?:\/|(?=$|[\s"'<>\x00]))/],
  ['private temporary path', /\/(?:private\/)?var\/folders\//],
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['access token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-)?[A-Za-z0-9_-]{40,}|AKIA[A-Z0-9]{16})\b/],
  ['credential in URL', /https?:\/\/[^\s/:]+:[^\s/@]+@/],
];

/** Inspect every packaged file, including binary strings; never return matched values. */
export const checkAppPrivacy = async (bundle, forbiddenPrefixes = [sourceRoot, homedir()]) => {
  const root = resolve(bundle);
  const findings = [];
  let files = 0;
  const prefixes = forbiddenPrefixes.filter(prefix => prefix && prefix !== '/')
    .flatMap(prefix => [prefix, encodeURI(prefix)]);
  const inspect = (text, file) => {
    for (const [reason, pattern] of patterns) {
      if (pattern.test(text)) findings.push({ file, reason });
    }
    if (prefixes.some(prefix => text.includes(prefix))) findings.push({ file, reason: 'local build/home path' });
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
    }
  };
  const metadata = await lstat(root);
  if (!metadata.isDirectory() || metadata.isSymbolicLink()) throw new Error('Expected a real bundle directory');
  await walk(root);
  if (!files) findings.push({ file: '.', reason: 'empty bundle' });
  return { files, findings: [...new Map(findings.map(item => [`${item.file}:${item.reason}`, item])).values()] };
};

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3) {
    console.error('Usage: bun scripts/check-app-privacy.mjs APP_BUNDLE');
    process.exitCode = 2;
  } else {
    try {
      const result = await checkAppPrivacy(process.argv[2]);
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
