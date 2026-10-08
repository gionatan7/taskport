# Taskport

A native macOS workspace for project tasks, with interactive Ghostty terminals.

Taskport is an experimental source preview, not a production-ready binary release. See [current limitations](docs/architecture.md#current-limitations).

## What it does

- Save projects and tasks; review VS Code tasks and package scripts before importing.
- Pin long-running services for Run all; keep one-offs and temporary experiments separate.
- Use interactive terminals with your zsh prompt, retained output, and two resizable panes.
- Give each server task its own local URL and optional, explicitly authorized Cloudflare tunnel.
- Control projects, tasks, and active sessions through the CLI and portable agent skill.

## Build and run

Requires macOS 14+ to run. Building requires full Xcode 27.x with Apple Swift 6.4.x (patch releases are accepted); Command Line Tools alone are not supported. Tested on Apple silicon. The build checks these requirements before downloading dependencies. Older Swift compilers can crash during optimized compilation. Dependencies are pinned; the first build downloads the terminal wrapper and framework into ignored project-local caches.

If another toolchain is selected, use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build.sh`. This selects an already-installed Xcode for that command without changing system settings. SwiftPM and the icon compiler use the same selected Xcode.

**The default build installs into `/Applications/Taskport.app`. Quit Taskport first.** It verifies and moves the new bundle, preserving the previous installation until replacement succeeds. It does not stop tasks, launch the app, or install the CLI.

```sh
bash scripts/build.sh
open /Applications/Taskport.app
```

For verification without installation or interruption of running tasks:

```sh
bash scripts/swift.sh test
bash scripts/build.sh --check
```

Packaging remaps compiler paths, strips debug/local symbols, and ad-hoc signs the app. Staging is cleaned afterward. Privacy scans are separate manual audits, not build steps; Bun is not needed to build. Ad-hoc signing and a successful build do not make a distributable release.

To prepare a **local binary candidate without installing or launching it**, run `bash scripts/prepare-release.sh`. This requires Bun and Python 3 for the privacy and ZIP audits. It produces an Apple silicon ZIP and SHA-256 checksum under ignored `build/release-candidate/`, scans local identity markers without reporting their values, excludes filesystem metadata, and verifies the extracted app. It refuses to overwrite an existing candidate. `bash scripts/build.sh --package OUTPUT_APP` is the lower-level packaging-only mode and does not run privacy scans. See [publication checks](docs/public-source.md) for the release checklist and privacy limitations.

Prepare the accompanying dependency sources and libintl relinking materials with `python3 scripts/prepare-source-release.py`. Downloads, the temporary Zig compiler, and caches remain project-local and are cleaned afterward. It retains a source/relink archive and checksum beside the ZIP, with neutral metadata and a local-identity audit. The [relinking instructions](docs/dependency-relinking.md) describe the tested modified-library path; it needs no Metal Toolchain or paid Apple account. Publish both archives together.

The active icon source is `Resources/Taskport-Pills.icon`; edit it in Icon Composer.

## Using Taskport

Add a folder, review imports in Tasks, and pin the services you want Run all to start. The + button adds an app-local task. Imported commands stay unchanged; editing creates a local override after a notice, while pinning alone does not.

Each task tab is a real terminal: type commands or use Ctrl-C. The Terminal panes menu shows another task beside or below it without duplicating its process. Closing an unpinned tab discards its output, not its saved task. Project folder changes require idle terminals; relative task paths follow the new folder, but absolute paths stay unchanged. No files move or tasks re-import automatically.

Sidebar play/stop controls reflect pinned services. Project and global Stop all also interrupt unpinned work and manually entered commands. The subtitle shows detected listening TCP ports, or `Stopped` when none are detected—even if a non-network task is running.

Set a Local URL on each server task. Task links nests by task when several have URLs. A tunnel gets its own tab; stopping the server also stops its tunnel. UI-started tunnels copy the link and show an in-app notice after connection registration, not merely a URL announcement. This is not an origin-health check. `cloudflared` must already be on the shell's PATH; Taskport never installs it.

Temporary tasks disappear after success or an explicit stop; failures stay inspectable until dismissed. Temporary tasks and tunnels never survive relaunch.

Definitions are stored privately in macOS Application Support, not this checkout. Settings → General → Resume running tasks on launch is enabled by default and restarts previously running pinned services as new processes; it does not restore scrollback. Turning it off clears the resume list without stopping current work. Close hides the window and retains sessions; Quit stops owned sessions, confirming when work is active.

## CLI and agents

Taskport → Settings → Integrations installs or uninstalls `~/.local/bin/taskport`, a symlink to the bundled CLI. Ensure that directory is on PATH; installation does not modify shell configuration or overwrite another command. Keep the app at its installed location.

```sh
taskport launch
taskport projects list
taskport sessions list
taskport ports list
taskport help
```

The same pane installs the bundled [Taskport skill](skills/taskport/SKILL.md). Select one or more standard user-wide locations: Shared (`~/.agents/skills`, the default for Codex and compatible agents), Claude Code, Cursor, GitHub Copilot, Gemini CLI, or OpenCode. Each installation links to the app's bundled instructions and stays current with app updates; no source checkout is needed. Confirmations list the affected paths. Existing skills are left untouched, and uninstall removes only this app's links, not the app, CLI, or projects. Custom agent configuration directories are not detected; install there manually if needed.

Read [CLI guidance](docs/cli.md) for task control, asynchronous results, and permission boundaries.

Before choosing a new server port, `taskport ports list` returns TCP listening ports visible to your user, including servers outside Taskport. It works even when the app is closed; the result is a snapshot, not a reservation.

## Development and publication

[Architecture](docs/architecture.md) describes persistence, process ownership, native UI, and compatibility limits. [Publication checks](docs/public-source.md) cover privacy and the additional requirements for binary releases. `Examples/ReviewProject` contains harmless heartbeat and exit-code tasks for manual testing.

Taskport's original material is [GPL-3.0-only](LICENSE), without warranty. Commercial use and resale are allowed under its terms. Third-party components retain their own licenses; see [dependency notices and provenance](THIRD_PARTY_NOTICES.md).
