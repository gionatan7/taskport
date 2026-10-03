# Taskport

## Product and UI

- macOS-only, Swift with SwiftUI and AppKit. The native app is the product; do not maintain a separate browser mockup.
- Prefer native `NavigationSplitView`, sidebar `List`, toolbar items, `Button`, `Menu`, popovers, forms, sheets, alerts, and SF Symbols. Do not reproduce browser chrome in SwiftUI.
- Follow current Apple HIG and WWDC guidance; see `docs/architecture.md`. Let standard controls adopt the platform's current materials. Keep terminal content opaque and readable.
- Task menus with independent edit/pin buttons use a native popover containing standard controls, not custom-drawn menu items.
- Task configuration, runtime status, and UI state are separate. An idle shell is not a running task.
- Project folder edits preserve IDs, tasks, overrides, links, tabs, and output. Require idle terminals (including stopped tunnels and cleared input), then close idle shells so the next start uses a fresh cwd/environment. Relative paths follow the new folder; absolute/literal paths stay unchanged. Never move files or automatically re-import tasks on a folder edit.
- Only pinned long-running tasks affect Run all and sidebar status. One-offs and tunnels do not.
- URLs belong to tasks, not projects. One linked task uses a flat Local/Remote menu; several use per-task submenus. Temporary tasks are unpinned, removed after stop/success, retained on failure until dismissed, and never resumed after relaunch. Stopping a server also stops its associated tunnel.
- Imported definitions remain unchanged. Confirm before the first local edit, and show `Local override` beneath modified tasks. Pinning alone is not a definition override.
- Closing a window keeps sessions alive; explicit Quit confirms and stops owned sessions. Never promise cleanup without testing process groups.

## Dependencies and builds

- Use `bash scripts/swift.sh build` for project-local SwiftPM/compiler caches.
- Use `bash scripts/build.sh` for release packaging, signing, and automatic installation. Verify Swift behavior with `bash scripts/swift.sh test`. Privacy scanning is a separate manual pre-release audit: `bun scripts/check-app-privacy.mjs APP_BUNDLE`; test the scanner with `bun test scripts/check-app-privacy.test.mjs`. Bun is not required to build or install.
- After successful normal packaging, the build script calls `bash scripts/install.sh STAGED_APP` to move the fresh signature-verified bundle into `/Applications/Taskport.app`. `bash scripts/build.sh --check` is the explicit verification-only exception: it builds/signs/verifies the same package and removes staging without installing; it does not run a privacy scan. Quit running Taskport instances before installing; never stop user tasks without authorization. Keep only the installed app bundle and launch only `/Applications/Taskport.app`, not a build-folder copy. If the user says they will relaunch, leave the app closed. Ignored SwiftPM debug/test outputs are not packaged apps or publication inputs.
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
