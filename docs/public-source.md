# Publication checks

Source publication and binary distribution are separate decisions. Audit the exact archives rather than assuming a successful source build is ready to distribute.

## Source checklist

```sh
bun scripts/check-public-source.mjs
bun test scripts
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

`bash scripts/prepare-release.sh` is the separate candidate preparation/audit command. It runs the packaging-only build, checks the app with `--local-identities`, creates a ZIP with neutral timestamps and without Unix ownership or extra fields, inspects both local and central ZIP headers, and checks the extracted app's content, notices, and signature. It also signs/verifies the ZIP and `appcast.xml` using the maintainer's Keychain key. It retains the ZIP, SHA-256 checksum, and signed feed in `build/release-candidate/` and refuses overwrites. No private key is exported. Complete the binary release checklist below before publication.

`python3 scripts/prepare-source-release.py` prepares the matching source/relink archive and checksum. It verifies pinned download hashes, includes dependency source and an engine archive without libintl, and checks neutral ownership/timestamps and local identity/path markers. Temporary downloads, compilers, and caches are project-local and removed. Upstream public source, fixtures, and author attribution remain verbatim. Run the [documented relink verification](dependency-relinking.md) on the extracted archive; neither a source URL nor GitHub's automatic source archive substitutes for these materials.

## Runtime privacy and trust

Saved projects, commands, URLs, and literal environment values live in the per-user `Application Support/Taskport` directory. Its directory is owner-only; workspace JSON is atomically replaced with mode 0600. Values are **not encrypted**. `TASKPORT_DATA_DIR` isolates test data.

Private per-session zsh hooks and command scripts live beneath that directory and are removed on completion/session exit. A crash can leave private files behind; relaunch does not perform a general abandoned-session sweep. Taskport does not persist terminal transcripts. User shell history and startup-file side effects remain controlled by the user's shell configuration.

Taskport runs login zsh and user-authorized project commands as the logged-in user. It is not a sandbox for untrusted commands. Ghostty appearance is imported through an allowlist, not by forwarding commands, environment entries, keybindings, or permissions; see [architecture](architecture.md).

Startup resume is enabled by default for previously running pinned services only; disable it in Settings to clear the resume list without stopping current work. Importing a definition does not run it. Explicit CLI restore or an approved update can additionally restart previously active unpinned/temporary services. One-offs and tunnels need separate consent. Manual commands and unfinished input block these restarts; quick shells and terminal history are not replayed.

The CLI uses an owner-only, same-user Unix socket, not a network listener or daemon. Environment values are omitted from list responses, but paths and commands can still be sensitive. Review/redact CLI output, logs, screenshots, and configuration diagnostics before posting public issues. No telemetry or export feature is implemented.

## Binary release checklist

Builds bundle the checked-in licenses/notices and verify their integrity before signing. The app is ad-hoc signed, not notarized; signed update metadata is a separate verification layer and does not provide Apple's notarization. Distribute only audited release archives with their matching source/relink materials.

Before distributing binaries:

- Preserve the compiler/runtime inventory, constituent font licenses, and embedded-code attribution in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Its provenance notes distinguish verified input/source history from the original Fuchsia revision that upstream does not identify.
- Publish the exact corresponding-source/relink archive beside the matching app ZIP with the same free access. The modified-libintl function test and Taskport source rebuild/relink have passed without Metal; see [relinking materials](dependency-relinking.md). The archive also includes MPL-covered z2d source and the full pinned dependency source graph. Whole-engine compilation is a separate, unverified route that needs Apple's Metal Toolchain.
- Test a clean-machine build, supported architectures, and the terminal/input/accessibility acceptance items in [architecture](architecture.md#current-limitations).
- For the free preview route, retain ad-hoc signing and clearly document the first-launch Privacy & Security → Open Anyway step. Developer ID signing/notarization remains an optional future distribution route.
- Audit the actual final artifact separately: `bun scripts/check-app-privacy.mjs APP_BUNDLE`.

Prepare artifacts locally on the documented Xcode toolchain; the private update key remains in the maintainer's Keychain, not CI. Version, build number, and `CHANGELOG.md` belong to one release commit tagged `vX.Y.Z`. Attach the app ZIP/checksum, source/relink archive/checksum, and signed `appcast.xml` to the same draft GitHub Release. Download and audit those exact assets and test the downloaded ZIP on a separate supported Mac before publication. Normal public 0.x releases use GitHub's latest channel; beta/RC releases need a separate feed because `/releases/latest` excludes prereleases. Published builds are immutable: subsequent changes need a new version and build.

The app scanner checks filenames and readable strings, including binary, NUL-padded, and UTF-16 text, and fails on unreadable entries, unexpected symlinks, private/debug artifacts, detected local paths, and common secret patterns without printing their contents. Only Sparkle's exact internal framework aliases are permitted, and their real files are scanned. The intentional public repository URL is exempt from local-name matching, not from path/credential checks. `--local-identities` additionally checks the login/full name, full-name words of at least four characters, configured Git name/email, available computer/host names, and readable hardware serial/UUID; marker values are not saved or reported. It does not prove compressed/encoded data is safe or that licenses are satisfied. Compiler path remapping and stripping do not sanitize arbitrary literals or prebuilt dependencies; old builds remain unchecked.
