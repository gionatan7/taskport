import { test, expect } from 'bun:test';
import { mkdtemp, mkdir, writeFile, rm, symlink } from 'node:fs/promises';
import { join } from 'node:path';
import { checkAppPrivacy } from './check-app-privacy.mjs';

const fixture = async (run) => {
  await mkdir('build', { recursive: true });
  const root = await mkdtemp(join(process.cwd(), 'build', '.privacy-test-'));
  try { await run(root); } finally { await rm(root, { recursive: true, force: true }); }
};

test('allows neutral paths and ordinary app resources', () => fixture(async root => {
  await writeFile(join(root, 'Executable'), Buffer.from('\0/src/taskport/Sources/main.swift\0/usr/lib/libSystem.B.dylib\0'));
  expect(await checkAppPrivacy(root, ['/fictional/checkout'])).toEqual({ files: 1, findings: [] });
}));

test('rejects private paths in binary UTF-8, UTF-16LE and UTF-16BE strings', () => fixture(async root => {
  const path = '/Users' + '/fictional-person/Projects/example';
  for (const [name, bytes] of [
    ['utf8', Buffer.from(`\0${path}\0`)],
    ['utf16le', Buffer.from(path, 'utf16le')],
    ['utf16be', Buffer.from(path, 'utf16le').swap16()],
  ]) await writeFile(join(root, name), bytes);
  const result = await checkAppPrivacy(root, []);
  expect(result.findings.filter(item => item.reason === 'personal home path')).toHaveLength(3);
  expect(JSON.stringify(result)).not.toContain('fictional-person');
}));

test('rejects checkout paths outside the home and encoded paths', () => fixture(async root => {
  const prefix = '/work/private checkout';
  await writeFile(join(root, 'Executable'), `prefix ${prefix}/file.swift\0${encodeURI(prefix)}/another.swift`);
  expect((await checkAppPrivacy(root, [prefix])).findings.some(item => item.reason === 'local build/home path')).toBe(true);
}));

test('rejects private temporary paths, credential files and tokens without printing contents', () => fixture(async root => {
  await writeFile(join(root, '.env'), 'test only');
  await writeFile(join(root, 'Executable'), '/private/var' + '/folders/fictional/cache\0ghp_' + 'x'.repeat(36));
  const result = await checkAppPrivacy(root, []);
  expect(result.findings.map(item => item.reason)).toContain('access token');
  expect(result.findings.map(item => item.reason)).toContain('private temporary path');
  expect(result.findings.map(item => item.reason)).toContain('private configuration or build artifact');
  expect(JSON.stringify(result)).not.toContain('x'.repeat(36));
}));

test('rejects nested debug artifacts and links without following them', () => fixture(async root => {
  await mkdir(join(root, 'Debug.dSYM'));
  await writeFile(join(root, 'Debug.dSYM', 'symbols'), 'fixture');
  await symlink('/not-a-real-target', join(root, 'external'));
  const result = await checkAppPrivacy(root, []);
  expect(result.findings.map(item => item.reason)).toContain('private configuration or build artifact');
  expect(result.findings.map(item => item.reason)).toContain('unexpected non-file entry');
}));

test('rejects empty or inaccessible bundle roots', () => fixture(async root => {
  expect((await checkAppPrivacy(root, [])).findings).toEqual([{ file: '.', reason: 'empty bundle' }]);
  await expect(checkAppPrivacy(join(root, 'missing'), [])).rejects.toThrow();
  await symlink(root, join(root, 'link'));
  await expect(checkAppPrivacy(join(root, 'link'), [])).rejects.toThrow();
}));

test('command-line gate fails closed and reports categories without matched values', () => fixture(async root => {
  const path = '/Users' + '/private-fixture/Projects/example';
  const file = join(root, 'Executable');
  await writeFile(file, path);
  const run = () => Bun.spawn([process.execPath, 'scripts/check-app-privacy.mjs', root], { stdout: 'pipe', stderr: 'pipe' });
  const rejected = run();
  const rejectedOutput = await new Response(rejected.stderr).text();
  expect(await rejected.exited).toBe(1);
  expect(rejectedOutput).toContain('personal home path');
  expect(rejectedOutput).not.toContain('private-fixture');
  await writeFile(file, '/src/taskport/entry.swift');
  const accepted = run();
  expect(await accepted.exited).toBe(0);
}));
