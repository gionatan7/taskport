import { test, expect } from 'bun:test';
import { cp, mkdtemp, mkdir, writeFile, rm, access } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const fixture = async (options, run) => {
  await mkdir('build', { recursive: true });
  const root = await mkdtemp(join(process.cwd(), 'build', '.toolchain-test-'));
  try {
    await mkdir(join(root, 'scripts'));
    await mkdir(join(root, 'bin'));
    for (const file of ['build.sh', 'check-toolchain.sh', 'swift.sh']) {
      await cp(join('scripts', file), join(root, 'scripts', file));
    }
    await writeFile(join(root, 'bin', 'xcrun'), `#!/bin/bash
case "$*" in
  'xcodebuild -version')
    [[ "$TASKPORT_TEST_XCODE" != clt ]] || exit 1
    printf 'Xcode %s\\nBuild version example\\n' "$TASKPORT_TEST_XCODE" ;;
  'swift --version')
    printf 'swift-driver version: example\\nApple Swift version %s (example)\\nTarget: arm64-apple-macosx27.0\\n' "$TASKPORT_TEST_SWIFT" ;;
  '--find actool') [[ "$TASKPORT_TEST_ACTOOL" == yes ]] ;;
  *) printf '%s\\n' "$*" >> "$TASKPORT_TEST_CALLS"; exit 81 ;;
esac
`, { mode: 0o755 });
    // A PATH-selected Swift must never override the compiler selected by Xcode.
    await writeFile(join(root, 'bin', 'swift'), '#!/bin/bash\nexit 82\n', { mode: 0o755 });
    const env = { ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`,
      TASKPORT_TEST_XCODE: options.xcode ?? '27.0', TASKPORT_TEST_SWIFT: options.swift ?? '6.4',
      TASKPORT_TEST_ACTOOL: options.actool ?? 'yes', TASKPORT_TEST_CALLS: join(root, 'calls') };
    const invoke = (script, ...args) => spawnSync('/bin/bash', [join(root, 'scripts', script), ...args], { cwd: root, env, encoding: 'utf8' });
    await run({ root, invoke });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
};

test('accepts Xcode 27 and Swift 6.4 patch/minor releases', async () => {
  for (const versions of [{ xcode: '27', swift: '6.4' }, { xcode: '27.1', swift: '6.4.2' }]) {
    await fixture(versions, async ({ invoke }) => {
      expect(invoke('check-toolchain.sh').status).toBe(0);
    });
  }
});

test('rejects unsupported Swift, Xcode, CLT-only and missing icon compiler before build side effects', async () => {
  for (const options of [{ swift: '6.2.4' }, { swift: '6.3' }, { swift: '6.40' }, { swift: '7.0' },
    { xcode: '26.3' }, { xcode: '28' }, { xcode: '270' }, { xcode: 'clt' }, { actool: 'no' }]) {
    await fixture(options, async ({ root, invoke }) => {
      for (const args of [[], ['--check']]) {
        const result = invoke('build.sh', ...args);
        expect(result.status).toBe(1);
        expect(result.stderr).toContain('requires full Xcode 27.x with Apple Swift 6.4.x');
        expect(result.stderr).toContain('DEVELOPER_DIR=');
      }
      for (const path of ['calls', '.build', 'build']) {
        expect(await access(join(root, path)).then(() => true, () => false)).toBe(false);
      }
    });
  }
});

test('uses Xcode-selected Swift rather than a conflicting PATH compiler', () => fixture({}, async ({ invoke }) => {
  expect(invoke('swift.sh', 'build').status).toBe(81);
}));

test('rejects unexpected arguments', () => fixture({}, async ({ invoke }) => {
  expect(invoke('check-toolchain.sh', 'unexpected').status).toBe(2);
}));
