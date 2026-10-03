import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, relative } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
// Local build products, downloaded dependencies, and VCS metadata are not source.
const excluded = new Set(['.git', '.build', '.swiftpm', 'build', '.DS_Store']);
const patterns = [
  ['personal home path', /\/Users\/[^\s/"'<>]+\/|\/home\/[^\s/"'<>]+\/|~\/Projects\//],
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['access token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-)?[A-Za-z0-9_-]{40,}|AKIA[A-Z0-9]{16})\b/],
  ['credential in URL', /https?:\/\/[^\s/:]+:[^\s/@]+@/],
];
let findings = 0;
let files = 0;

/** Reports locations, never matched secrets or file contents. */
const checkDirectory = async (directory) => {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (excluded.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) { await checkDirectory(path); continue; }
    if (!entry.isFile()) {
      console.error(`${relative(root, path)}: unexpected non-file entry`);
      findings++;
      continue;
    }
    files++;
    if (/^(?:\.env(?:\..+)?|.*\.(?:p12|pfx|key|pem|mobileprovision))$/.test(entry.name) && entry.name !== '.env.example') {
      console.error(`${relative(root, path)}: private configuration or signing file`);
      findings++;
    }
    const contents = await readFile(path, 'utf8');
    for (const [label, pattern] of patterns) {
      if (!pattern.test(contents)) continue;
      console.error(`${relative(root, path)}: ${label}`);
      findings++;
    }
  }
};
await checkDirectory(root);
console.log(`Checked ${files} source files; ${findings} potential privacy issues.`);
console.log('Heuristic check only: review staged changes and history before publication.');
process.exitCode = findings ? 1 : 0;
