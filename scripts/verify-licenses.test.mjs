import { test, expect } from 'bun:test';
import { cp, mkdtemp, mkdir, readFile, writeFile, rm, symlink } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const fixture = async run => {
  await mkdir('build', { recursive: true });
  const root = await mkdtemp(join(process.cwd(), 'build', '.license-test-'));
  const app = join(root, 'Taskport.app');
  const resources = join(app, 'Contents', 'Resources');
  const preexec = join(resources, 'GhosttyKit_GhosttyTerminal.bundle', 'Contents', 'Resources', 'Ghostty', 'shell-integration', 'bash', 'LICENSE-bash-preexec.md');
  try {
    await mkdir(join(root, 'scripts'));
    await mkdir(resources, { recursive: true });
    await cp('scripts/verify-licenses.sh', join(root, 'scripts', 'verify-licenses.sh'));
    for (const file of ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'LICENSES']) {
      await cp(file, join(root, file), { recursive: true });
      await cp(file, join(resources, file), { recursive: true });
    }
    await mkdir(join(preexec, '..'), { recursive: true });
    await cp('LICENSES/bash-preexec/LICENSE.md', preexec);
    const verify = (...args) => spawnSync('bash', [join(root, 'scripts', 'verify-licenses.sh'), ...(args.length ? args : [app])], { encoding: 'utf8' });
    await run({ root, resources, preexec, verify });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
};

test('accepts all canonical license texts and original shell resource notice', () => fixture(async ({ verify }) => {
  const result = verify();
  expect(result.status).toBe(0);
  expect(result.stdout).toContain('License files verified');
}));

test('fails when required bundled notices, manifests, or licenses are missing', async () => {
  for (const file of ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'LICENSES/SHA256SUMS', 'LICENSES/libintl/COPYING.LIB', 'LICENSES/JetBrainsMono/OFL.txt']) {
    await fixture(async ({ resources, verify }) => {
      await rm(join(resources, file));
      expect(verify().status).toBe(1);
    });
  }
});

test('rejects empty or altered license text in either source or bundle', async () => {
  for (const location of ['source', 'bundle']) {
    for (const text of ['', 'altered license text\n']) {
      await fixture(async ({ root, resources, verify }) => {
        await writeFile(join(location === 'source' ? root : resources, 'LICENSES/libintl/COPYING.LIB'), text);
        expect(verify().status).toBe(1);
      });
    }
  }
  await fixture(async ({ root, resources, verify }) => {
    for (const dir of [root, resources]) await writeFile(join(dir, 'LICENSES/libintl/COPYING.LIB'), 'same alteration in both copies\n');
    expect(verify().stderr).toContain('checksum mismatch');
  });
});

test('rejects missing canonical files and unlisted license files', async () => {
  await fixture(async ({ root, verify }) => {
    await rm(join(root, 'LICENSES/libintl/COPYING.LIB'));
    expect(verify().status).toBe(1);
  });
  await fixture(async ({ root, resources, verify }) => {
    for (const dir of [root, resources]) await writeFile(join(dir, 'LICENSES/extra.txt'), 'unreviewed text\n');
    expect(verify().stderr).toContain('unlisted or missing');
  });
});

test('rejects symlinks without accepting linked source or bundled licenses', async () => {
  for (const location of ['source', 'bundle']) {
    await fixture(async ({ root, resources, verify }) => {
      const file = join(location === 'source' ? root : resources, 'LICENSES/libintl/COPYING.LIB');
      await rm(file);
      await symlink('/not-a-real-target', file);
      expect(verify().stderr).toContain('unexpected non-file');
    });
  }
  await fixture(async ({ resources, verify }) => {
    const file = join(resources, 'LICENSE');
    await rm(file);
    await symlink('/not-a-real-target', file);
    expect(verify().status).toBe(1);
  });
});

test('rejects malformed, duplicate, or truncated manifest entries', async () => {
  for (const text of ['', '0'.repeat(64) + '  FreeType/../LICENSE\n', 'not-a-checksum  FreeType/FTL.TXT\n']) {
    await fixture(async ({ root, verify }) => {
      await writeFile(join(root, 'LICENSES/SHA256SUMS'), text);
      expect(verify().status).toBe(1);
    });
  }
  await fixture(async ({ root, verify }) => {
    const file = join(root, 'LICENSES/SHA256SUMS');
    const text = await readFile(file, 'utf8');
    await writeFile(file, text + text.split('\n')[0] + '\n');
    expect(verify().stderr).toContain('duplicate');
  });
  await fixture(async ({ root, resources, verify }) => {
    const text = (await readFile(join(root, 'LICENSES/SHA256SUMS'), 'utf8')).split('\n').slice(1).join('\n');
    for (const dir of [root, resources]) await writeFile(join(dir, 'LICENSES/SHA256SUMS'), text);
    expect(verify().stderr).toContain('unlisted or missing');
  });
});

test('preserves the bash-preexec notice in the wrapper resource bundle', async () => {
  for (const text of ['', 'altered resource notice\n']) {
    await fixture(async ({ preexec, verify }) => {
      await writeFile(preexec, text);
      expect(verify().status).toBe(1);
    });
  }
  await fixture(async ({ preexec, verify }) => {
    await rm(preexec);
    expect(verify().status).toBe(1);
  });
});

test('requires one explicit bundle argument', () => fixture(async ({ root, verify }) => {
  expect(verify('').status).toBe(2);
  expect(verify('one', 'two').status).toBe(2);
  expect(spawnSync('bash', [join(root, 'scripts', 'verify-licenses.sh')]).status).toBe(2);
}));
