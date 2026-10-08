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

`build.sh --check` packages and verifies without installing or touching live tasks. `build.sh --package OUTPUT_APP` retains a fresh verified bundle without installing. Normal `build.sh` installs into Applications after you quit Taskport. These build modes do not run privacy scans.

`bash scripts/prepare-release.sh` is the separate candidate preparation/audit command. It runs the packaging-only build, checks the app with `--local-identities`, creates a ZIP with neutral timestamps and without Unix ownership or extra fields, inspects both local and central ZIP headers, and checks the extracted app's content, notices, and signature. It leaves only a ZIP and SHA-256 checksum in `build/release-candidate/` and refuses overwrites. Complete the binary release checklist below before publication.

`python3 scripts/prepare-source-release.py` prepares the matching source/relink archive and checksum. It verifies pinned download hashes, includes dependency source and an engine archive without libintl, and checks neutral ownership/timestamps and local identity/path markers. Temporary downloads, compilers, and caches are project-local and removed. Upstream public source, fixtures, and author attribution remain verbatim. Run the [documented relink verification](dependency-relinking.md) on the extracted archive; neither a source URL nor GitHub's automatic source archive substitutes for these materials.

## Runtime privacy and trust

Saved projects, commands, URLs, and literal environment values live in the per-user `Application Support/Taskport` directory. Its directory is owner-only; workspace JSON is atomically replaced with mode 0600. Values are **not encrypted**. `TASKPORT_DATA_DIR` isolates test data.

Private per-session zsh hooks and command scripts live beneath that directory and are removed on completion/session exit. A crash can leave private files behind; relaunch does not perform a general abandoned-session sweep. Taskport does not persist terminal transcripts. User shell history and startup-file side effects remain controlled by the user's shell configuration.

Taskport runs login zsh and user-authorized project commands as the logged-in user. It is not a sandbox for untrusted commands. Ghostty appearance is imported through an allowlist, not by forwarding commands, environment entries, keybindings, or permissions; see [architecture](architecture.md).

Startup resume is enabled by default for previously running pinned services only; disable it in Settings to clear the resume list without stopping current work. Importing a definition does not run it. Temporary tasks, tunnels, one-offs, and unpinned services do not resume.

The CLI uses an owner-only, same-user Unix socket, not a network listener or daemon. Environment values are omitted from list responses, but paths and commands can still be sensitive. Review/redact CLI output, logs, screenshots, and configuration diagnostics before posting public issues. No telemetry or export feature is implemented.

## Binary release checklist

Builds bundle the checked-in licenses/notices and verify their integrity before signing. The local bundle remains ad-hoc signed, not notarized; notice packaging does not settle the remaining binary compliance gaps. Do not distribute development bundles as release artifacts.

Before distributing binaries:

- Preserve the compiler/runtime inventory, constituent font licenses, and embedded-code attribution in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Its provenance notes distinguish verified input/source history from the original Fuchsia revision that upstream does not identify.
- Publish the exact corresponding-source/relink archive beside the matching app ZIP with the same free access. The modified-libintl function test and Taskport source rebuild/relink have passed without Metal; see [relinking materials](dependency-relinking.md). The archive also includes MPL-covered z2d source and the full pinned dependency source graph. Whole-engine compilation is a separate, unverified route that needs Apple's Metal Toolchain.
- Test a clean-machine build, supported architectures, and the terminal/input/accessibility acceptance items in [architecture](architecture.md#current-limitations).
- For the free preview route, retain ad-hoc signing and clearly document the first-launch Privacy & Security → Open Anyway step. Developer ID signing/notarization remains an optional future distribution route.
- Audit the actual final artifact separately: `bun scripts/check-app-privacy.mjs APP_BUNDLE`.

The app scanner checks filenames and readable strings, including binary, NUL-padded, and UTF-16 text, and fails on unreadable entries, symlinks, private/debug artifacts, detected local paths, and common secret patterns without printing their contents. `--local-identities` additionally checks the login/full name, full-name words of at least four characters, configured Git name/email, available computer/host names, and readable hardware serial/UUID; marker values are not saved or reported. It does not prove compressed/encoded data is safe or that licenses are satisfied. Compiler path remapping and stripping do not sanitize arbitrary literals or prebuilt dependencies; old builds remain unchecked.
