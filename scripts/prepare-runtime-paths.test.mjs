import { test, expect } from 'bun:test';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { execFileSync, spawnSync } from 'node:child_process';
import { join, resolve } from 'node:path';

const script = resolve('scripts/prepare-runtime-paths.sh');
const toolchain = '/opt/Example Xcode.app/Contents/Developer/Toolchains/Example.xctoolchain/usr/lib/swift/macosx';

/** Use real Mach-O commands to cover spaces, preservation, rejection, and signing order. */
const fixture = async (run) => {
  await mkdir('build', { recursive: true });
  const root = await mkdtemp(join(process.cwd(), 'build', 'runtime-path-test.'));
  try {
    const binary = join(root, 'example');
    execFileSync('xcrun', ['clang', '-x', 'c', '-', '-Wl,-headerpad_max_install_names', '-o', binary], { input: 'int main(void) { return 0; }\n' });
    const add = (path) => execFileSync('xcrun', ['install_name_tool', '-add_rpath', path, binary]);
    const invoke = (...options) => spawnSync('/bin/bash', [script, ...options, binary], { encoding: 'utf8' });
    await run({ binary, add, invoke });
  } finally { await rm(root, { recursive: true, force: true }); }
};

test('removes toolchain RPATH before signing while preserving system and bundled paths', () => fixture(async ({ binary, add, invoke }) => {
  for (const path of ['/usr/lib/swift', '@loader_path', '@executable_path/../Frameworks', toolchain]) add(path);
  expect(invoke('--check').status).toBe(1);
  expect(invoke().status).toBe(0);
  expect(invoke('--check').status).toBe(0);
  const commands = execFileSync('xcrun', ['otool', '-l', binary], { encoding: 'utf8' });
  expect(commands).not.toContain(toolchain);
  for (const path of ['/usr/lib/swift', '@loader_path', '@executable_path/../Frameworks']) expect(commands).toContain(path);
  execFileSync('/usr/bin/codesign', ['--force', '--sign', '-', binary], { stdio: 'pipe' });
  expect(spawnSync('/usr/bin/codesign', ['--verify', '--strict', binary]).status).toBe(0);
}));

test('check-only rejects the old toolchain path without changing the executable', () => fixture(async ({ binary, add, invoke }) => {
  add(toolchain);
  const before = await Bun.file(binary).arrayBuffer();
  const result = invoke('--check');
  expect(result.status).toBe(1);
  expect(result.stderr).toContain('developer-toolchain');
  expect(result.stderr).not.toContain(toolchain);
  expect(await Bun.file(binary).arrayBuffer()).toEqual(before);
}));

test('rejects unrelated external paths instead of silently changing them', () => fixture(async ({ binary, add, invoke }) => {
  add('/opt/example/private-libraries');
  const before = await Bun.file(binary).arrayBuffer();
  expect(invoke().status).toBe(1);
  expect(await Bun.file(binary).arrayBuffer()).toEqual(before);
}));

test('rejects missing arguments and non-Mach-O inputs', () => {
  expect(spawnSync('/bin/bash', [script]).status).toBe(2);
  expect(spawnSync('/bin/bash', [script, resolve('README.md')]).status).toBe(1);
});
