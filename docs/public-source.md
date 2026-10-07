# Publication checks

Source publication and binary distribution are separate decisions. A source preview must not imply that the development app is a license-complete or production-ready release.

## Source checklist

```sh
bun scripts/check-public-source.mjs
bun test scripts/check-app-privacy.test.mjs
bun test scripts/verify-licenses.test.mjs
bun test scripts/check-toolchain.test.mjs
bash scripts/swift.sh test
bash scripts/build.sh --check
```

Before committing or pushing:

- Review the exact Git publication inputs, including hidden files, and any existing history. Ignore rules do not protect already-tracked files.
- Confirm the intended public author name/email; use a repository-local GitHub `noreply` identity if desired.
- Keep examples fictional. Exclude real project paths/commands, personal identifiers, credentials, configuration, transcripts, and signing material.
- Preserve [LICENSE](../LICENSE), [dependency notices](../THIRD_PARTY_NOTICES.md), the `LICENSES/` texts/checksums, pins, tests, and the portable skill's permission boundaries.
- Do not upload the whole working directory, dependency/compiler caches, old app bundles, or private archives.

The source scanner checks home paths, common credential patterns, credential-bearing URLs, private configuration/signing files, and symlinks. It reports filenames/categories, not matched values. It excludes `.git/`, `.build/`, `.swiftpm/`, `build/`, and `.DS_Store`. It is a heuristic, not a Git-history audit or a guarantee against arbitrary encoded secrets. Bun is required for these audit commands, not for building.

`build.sh --check` packages and verifies without installing or touching live tasks. Normal `build.sh` installs into Applications after you quit Taskport. Neither mode runs privacy scans.

## Runtime privacy and trust

Saved projects, commands, URLs, and literal environment values live in the per-user `Application Support/Taskport` directory. Its directory is owner-only; workspace JSON is atomically replaced with mode 0600. Values are **not encrypted**. `TASKPORT_DATA_DIR` isolates test data.

Private per-session zsh hooks and command scripts live beneath that directory and are removed on completion/session exit. A crash can leave private files behind; relaunch does not perform a general abandoned-session sweep. Taskport does not persist terminal transcripts. User shell history and startup-file side effects remain controlled by the user's shell configuration.

Taskport runs login zsh and user-authorized project commands as the logged-in user. It is not a sandbox for untrusted commands. Ghostty appearance is imported through an allowlist, not by forwarding commands, environment entries, keybindings, or permissions; see [architecture](architecture.md).

Startup resume is enabled by default for previously running pinned services only; disable it in Settings to clear the resume list without stopping current work. Importing a definition does not run it. Temporary tasks, tunnels, one-offs, and unpinned services do not resume.

The CLI uses an owner-only, same-user Unix socket, not a network listener or daemon. Environment values are omitted from list responses, but paths and commands can still be sensitive. Review/redact CLI output, logs, screenshots, and configuration diagnostics before posting public issues. No telemetry or export feature is implemented.

## Binary release checklist

Builds bundle the checked-in licenses/notices and verify their integrity before signing. The local bundle remains ad-hoc signed, not notarized; notice packaging does not settle the remaining binary compliance gaps. Do not distribute development bundles as release artifacts.

Before distributing binaries:

- Finish verifying the compiler/runtime inventory and unresolved embedded-code provenance. Constituent font licenses and verified compiler input notices are now retained; [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) records the evidence and remaining gaps.
- Assemble exact corresponding source and test a working build/relink distribution for GPL/LGPL/MPL obligations, including statically linked libintl. The pinned producer's source build currently stops at missing Apple's Metal Toolchain; normal Taskport builds use a precompiled engine and do not need this component. Do not replace this verification with source URLs alone.
- Test a clean-machine build, supported architectures, and the terminal/input/accessibility acceptance items in [architecture](architecture.md#current-limitations).
- Prepare distribution signing/notarization for normal macOS installation.
- Audit the actual final artifact separately: `bun scripts/check-app-privacy.mjs APP_BUNDLE`.

The app scanner checks filenames and readable strings, including binary and NUL-padded paths, and fails on unreadable entries, symlinks, private/debug artifacts, detected local paths, and common secret patterns without printing their contents. It does not prove compressed/encoded data is safe or that licenses are satisfied. Compiler path remapping and stripping do not sanitize arbitrary literals or prebuilt dependencies; old builds remain unchecked.
