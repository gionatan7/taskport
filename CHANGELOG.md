# Changelog

## 0.1.0

First public release of Taskport, a native macOS workspace for project tasks and interactive Ghostty terminals.

- Saved projects, collapsible/reorderable groups, and reviewed imports from VS Code tasks and package scripts.
- Pinned services with Run all, individual task control, one-offs, and temporary experiments.
- Interactive terminals, two resizable task panes, and runtime-only quick terminal tabs.
- Per-task local links and optional, explicitly authorized Cloudflare tunnels.
- A bundled CLI and installable agent skill for projects, groups, tasks, logs, active sessions, and occupied TCP ports.
- Signed Sparkle updates with confirmation before installation and restoration of previously running services.

### Requirements and installation

Apple silicon (M1 or later), macOS 14 or later. Xcode is not required to run the app. Optional tunnels require an existing `cloudflared` installation.

Download `Taskport-0.1.0-macos-arm64.zip`, unzip it, and move `Taskport.app` into Applications. The app is ad-hoc signed, not notarized by Apple. If macOS blocks it, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**. Managed Macs may prohibit this approval. [Apple's first-launch instructions](https://support.apple.com/en-us/102445).

Keep the ZIP's `.sha256` file beside it and verify with `shasum -a 256 -c Taskport-0.1.0-macos-arm64.zip.sha256`. The accompanying source/relink archive includes the matching Taskport and dependency sources; GitHub's automatic source archives do not replace it.

This is an early 0.x release, without warranty. Zsh is the supported shell; Intel, VoiceOver, and input-method support need broader testing. Commands run as your user. Restored services start fresh processes, not preserved terminal history or interactive state. [Current limitations](https://github.com/gionatan7/taskport/blob/main/docs/architecture.md#current-limitations).
