# Taskport

## Product and UI

- macOS-only, Swift with SwiftUI and AppKit. The native app is the product; do not maintain a separate browser mockup.
- Prefer native `NavigationSplitView`, sidebar `List`, toolbar items, `Button`, `Menu`, popovers, forms, sheets, alerts, and SF Symbols. Do not reproduce browser chrome in SwiftUI.
- Follow current Apple HIG and WWDC guidance; see `docs/architecture.md`. Let standard controls adopt the platform's current materials. Keep terminal content opaque and readable.
- Task menus with independent edit/pin buttons use a native popover containing standard controls, not custom-drawn menu items.
- Task configuration, runtime status, and UI state are separate. An idle shell is not a running task.
- Project folder edits preserve IDs, tasks, overrides, links, tabs, and output. Require idle terminals (including stopped tunnels and cleared input), then close idle shells so the next start uses a fresh cwd/environment. Relative paths follow the new folder; absolute/literal paths stay unchanged. Never move files or automatically re-import tasks on a folder edit.
- Only pinned long-running tasks affect Run all and sidebar status. One-offs and tunnels do not.
- URLs belong to tasks, not projects. One linked task uses a flat Local/Remote menu; several use per-task submenus. Temporary tasks are unpinned, removed after stop/success, retained on failure until dismissed, and discarded on ordinary launches. Explicit CLI session restore is the exception. Stopping a server also stops its associated tunnel.
- Imported definitions remain unchanged. Confirm before the first local edit, and show `Local override` beneath modified tasks. Pinning alone is not a definition override.
- Closing a window keeps sessions alive; explicit Quit confirms and stops owned sessions. Never promise cleanup without testing process groups.

## Dependencies and builds

- Packaging requires full Xcode 27.x and Apple Swift 6.4.x; `scripts/check-toolchain.sh` rejects unsupported versions before SwiftPM resolution. Swift commands use `xcrun` so they match the selected Xcode; use a command-scoped `DEVELOPER_DIR` rather than changing system selection. Test the preflight with `bun test scripts/check-toolchain.test.mjs`.
- Use `bash scripts/swift.sh build` for project-local SwiftPM/compiler caches.
- Use `bash scripts/build.sh` for release packaging, signing, and automatic installation. Verify Swift behavior with `bash scripts/swift.sh test`. Privacy scanning is a separate manual pre-release audit: `bun scripts/check-app-privacy.mjs APP_BUNDLE`; test the scanner with `bun test scripts/check-app-privacy.test.mjs`. Bun is not required to build or install.
- After successful normal packaging, the build script calls `bash scripts/install.sh STAGED_APP` to move the fresh signature-verified bundle into `/Applications/Taskport.app`. `bash scripts/build.sh --check` is the explicit verification-only exception: it builds/signs/verifies the same package and removes staging without installing; it does not run a privacy scan. Quit running Taskport instances before installing; never stop user tasks without authorization. Keep only the installed app bundle and launch only `/Applications/Taskport.app`, not a build-folder copy. If the user says they will relaunch, leave the app closed. Ignored SwiftPM debug/test outputs are not packaged apps or publication inputs.
- For user-requested binary release preparation, `bash scripts/prepare-release.sh` retains the audited ZIP, checksum, and signed `appcast.xml` in ignored `build/release-candidate/`. It uses `build.sh --package OUTPUT_APP`, which skips installation and refuses to overwrite a destination. Prepare and verify the matching source/relink archive separately. Remove diagnostic/extracted bundles after the audit; publish only after supported-machine testing.
- Release artifacts are prepared locally with the documented Xcode toolchain and the signing key in macOS Keychain, not CI. Version/build and `CHANGELOG.md` change together in one release commit; tag that exact commit as `vX.Y.Z`. Upload both archives/checksums and the signed feed to a draft first. Normal public 0.x releases use GitHub's latest channel; explicitly designated beta/RC builds need a separate feed before using the prerelease flag. Download/audit draft assets and complete separate-Mac acceptance before publishing. Keep app binaries out of Git history.
- For an authorized install/restart with running work, use `bash scripts/build.sh --restore`: it finishes packaging/preflight before `quit --save-session`, installs only after app exit, then uses `launch --restore`. The running app must already support lifecycle commands. Ordinary `build.sh`, `--check`, and `--package` never stop tasks. Restore includes previously active pinned/unpinned/temporary services, not all definitions; manual commands/input block it. Active one-offs and tunnels require separately authorized `--include-one-offs` / `--include-tunnels`. Commands start fresh, one-offs may repeat side effects, and tunnel URLs may change. Inspect `taskport restore status` and per-task failures rather than retrying blindly. Installation failure leaves the saved session for recovery with `launch --restore` after confirming rollback.
- Launch Taskport through a native app-launch tool or `taskport launch`, never by executing its GUI binary inside a sandboxed shell. User-authorized isolated screenshot fixtures are an exception to the installed-bundle rule: if they need a custom launch environment, request approved execution outside the sandbox, keep their data/config separate from the user's workspace, and verify the UI/control socket before capturing.
- Pin terminal-wrapper versions exactly and retain `Package.resolved`. Do not depend on an unpinned branch or another checkout on the developer's machine.
- Preserve `LICENSES/` verbatim texts and update their SHA-256 manifest with reviewed dependency changes. Packaging includes them, `LICENSE`, and `THIRD_PARTY_NOTICES.md`; `scripts/verify-licenses.sh` checks integrity/inclusion before signing. Test this check with `bun test scripts/verify-licenses.test.mjs`. It is not a privacy scan or proof of source/relinking compliance.
- Keep Ghostty-specific calls in the terminal integration layer. No alternative terminal renderer or fallback mock in the native app.
- Do not install global tools, change Xcode selection, or edit shared caches/settings without permission.

## Public-repository readiness

- No telemetry, secrets, signing identities, personal project paths, or machine-specific dependencies in native source/build configuration.
- Preserve third-party attribution. Review dependency changes and binary provenance before updating pins.
- All committed examples must be fictional. Run `bun scripts/check-public-source.mjs` before sharing; manually review staged content and history too.
- Read shell and Ghostty configuration only at runtime; never copy user configuration, terminal transcripts, or resolved personal paths into this repository. Import terminal appearance through an explicit key allowlist.
- Taskport's original project material is licensed under GNU GPL version 3 only (`GPL-3.0-only`); preserve the root LICENSE and third-party licenses/notices. Do not create a remote or publish releases without being asked.
