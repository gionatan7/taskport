import { test, expect } from 'bun:test';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const checker = resolve('scripts/check-release-archive.py');

/** Exercise real ZIP headers and round trips rather than a mock of the metadata check. */
const fixture = async (run) => {
  await mkdir('build', { recursive: true });
  const root = await mkdtemp(join(process.cwd(), 'build', '.archive-test-'));
  try {
    await mkdir(join(root, 'Taskport.app'));
    await writeFile(join(root, 'Taskport.app', 'resource'), 'neutral resource');
    execFileSync('/usr/bin/find', [join(root, 'Taskport.app'), '-exec', '/usr/bin/touch', '-t', '200001010000', '{}', '+']);
    await run(root);
  } finally { await rm(root, { recursive: true, force: true }); }
};

test('accepts ZIP without owner metadata, attributes or comments', () => fixture(async root => {
  execFileSync('/usr/bin/zip', ['-X', '-q', '-r', 'candidate.zip', 'Taskport.app'], { cwd: root });
  const result = spawnSync('python3', [checker, join(root, 'candidate.zip')], { encoding: 'utf8' });
  expect(result.status).toBe(0);
  expect(result.stdout).toContain('no owner IDs');
}));

test('rejects the Unix ownership and timestamp fields in an ordinary ZIP', () => fixture(async root => {
  execFileSync('/usr/bin/zip', ['-q', '-r', 'candidate.zip', 'Taskport.app'], { cwd: root });
  expect(spawnSync('python3', [checker, join(root, 'candidate.zip')]).status).toBe(1);
}));

test('rejects AppleDouble files even when extra fields are absent', () => fixture(async root => {
  await writeFile(join(root, 'Taskport.app', '._resource'), 'fictional metadata');
  execFileSync('/usr/bin/find', [join(root, 'Taskport.app'), '-exec', '/usr/bin/touch', '-t', '200001010000', '{}', '+']);
  execFileSync('/usr/bin/zip', ['-X', '-q', '-r', 'candidate.zip', 'Taskport.app'], { cwd: root });
  const result = spawnSync('python3', [checker, join(root, 'candidate.zip')], { encoding: 'utf8' });
  expect(result.status).toBe(1);
  expect(result.stderr).not.toContain('fictional metadata');
}));

test('rejects local file timestamps even when extra fields are absent', () => fixture(async root => {
  execFileSync('/usr/bin/touch', ['-t', '202601010000', join(root, 'Taskport.app', 'resource')]);
  execFileSync('/usr/bin/zip', ['-X', '-q', '-r', 'candidate.zip', 'Taskport.app'], { cwd: root });
  expect(spawnSync('python3', [checker, join(root, 'candidate.zip')]).status).toBe(1);
}));

test('rejects comments and malformed archives without echoing their content', () => fixture(async root => {
  execFileSync('/usr/bin/zip', ['-X', '-q', '-r', 'candidate.zip', 'Taskport.app'], { cwd: root });
  execFileSync('python3', ['-c', 'import zipfile; z=zipfile.ZipFile("candidate.zip", "a"); z.comment=b"fictional identity"; z.close()'], { cwd: root });
  const rejected = spawnSync('python3', [checker, join(root, 'candidate.zip')], { encoding: 'utf8' });
  expect(rejected.status).toBe(1);
  expect(rejected.stderr).not.toContain('fictional identity');
  await writeFile(join(root, 'candidate.zip'), 'invalid ZIP');
  expect(spawnSync('python3', [checker, join(root, 'candidate.zip')]).status).toBe(1);
}));
