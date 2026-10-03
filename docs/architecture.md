# Architecture

Taskport is a macOS 14+ SwiftUI/AppKit app. Its terminal view comes from the community `GhosttyTerminal` wrapper, not an official stable Ghostty Swift API. Exact dependency pins, prebuilt-artifact provenance, and licenses live in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Ownership and persistence

- `Sources/Taskport/Model`: project/task definitions, reviewed imports, versioned persistence, runtime orchestration.
- `Sources/Taskport/Terminal`: Ghostty surfaces, local appearance, shell integration, session lifecycle.
- `Sources/Taskport/UI`: native workspace, editors, menus, and pane presentation.
- `Sources/TaskportPTY`: C process/PTY and listener-discovery primitives.
- `Sources/TaskportControl` and `Sources/TaskportCLI`: local socket protocol and command-line client.

Projects have stable IDs, directories, icons, tasks, and saved pane selection/layout. Tasks separate command/cwd/environment definitions from pinning, run classification, URL, temporary status, and an optional imported snapshot. Tunnels reference their owner task. Only non-temporary pinned services participate in Run all/sidebar status.

`WorkspaceStore` is the single writer; UI and CLI mutations run on its main actor. Definitions/layouts are versioned JSON in private Application Support, not in the checkout. Runtime sessions and scrollback are not serialized. Startup reacquires an exclusive workspace lock and reloads the authoritative file before cleanup, migration, or resume. Lock/load errors make the store read-only rather than overwriting data. Unchanged saves are skipped, while migration checkpoints and private backups still persist.

Resume is a saved intent to start fresh processes, not daemon/session restoration. It is enabled by default for previously running pinned services; explicit stops clear those IDs. One-offs, unpinned services, temporary tasks, and tunnels never resume. See [runtime privacy](public-source.md#runtime-privacy-and-trust).

## Import boundaries

Imports support VS Code JSONC, shell/process tasks with string arguments, task-level cwd/env, and task-level macOS overrides. Project-wide execution settings (including root `osx`) skip VS Code import with a warning rather than losing inherited behavior; package discovery is independent. Dependencies, custom shells, automatic-run settings, structured arguments, and unsupported variables require manual setup. Problem matchers are disclosed as unapplied.

`${workspaceFolder}` resolves in cwd/environment, not command/argument text where substitution could break quoting. Package scripts use the project lockfile's runner and begin as unpinned one-offs. Definitions are reviewed before import; source changes do not auto-sync. First command/name/cwd/environment edits require a local-override notice and never rewrite source files. Pinning alone is not an override. Editors reject conflicting concurrent changes rather than overwriting them.

## Terminal and process boundary

Ghostty owns rendering/input via its public `.inMemory` host-I/O backend. Taskport owns the native PTY and shell; the pinned wrapper's `.exec` process/TTY introspection is stubbed and is not used. There is no duplicate runner or fallback renderer.

The C bridge calls `forkpty` and execs `/bin/zsh -il`; no Swift runs in the forked child. Nonblocking I/O and process-exit sources feed each session. Private startup wrappers source user files in place, then nonce-tagged preexec/precmd markers distinguish managed commands, manual commands, and idle prompts. Task commands run through a private subshell script to scope cwd/env and avoid PTY input-line limits. Unfinished manual input blocks managed injection. Custom shell frameworks can disrupt these hooks; startup times out explicitly.

Ctrl-C uses foreground terminal semantics. Force stop and confirmed Quit signal owned POSIX-session processes and escalate after a grace period, retaining PID ownership until reaped. Intentionally detached processes in another session are outside cleanup guarantees. Hiding the window retains sessions; full Quit does not.

Session-backed native hosts/surfaces remain alive across hidden projects. Only visible unstarted tabs need placeholder hosts; saved definitions alone allocate no native pane. A session replays its last valid Ghostty grid size to a replacement PTY before dispatching a command. The two-pane layout never duplicates a session.

Activity means received output bytes, not repainting or cursor blink. Listening-port refresh batches all session owners into one process snapshot and rejects observations after shell identity changes. A detected TCP listener is not a readiness/health guarantee.

## Appearance, clipboard, and links

Local Ghostty config is read at runtime through a font/color/palette/selection/cursor allowlist, with bounded includes and local theme lookup. No original config is exported or copied into the repo; commands, env entries, keybindings, clipboard permissions, and window settings are not forwarded. Transparency and light/dark theme pairs are not imported. Changes affect new sessions. Taskport renders without an installed Ghostty app; the external Open in Ghostty action is separate.

Protected paste uses a native Cancel/Paste sheet, with Cancel as default. Approval requires the same live, visible surface. Command completion, stop, close, hiding, or loss of the target cancels or invalidates a pending request so it cannot paste into a returned shell. Program-initiated OSC52 clipboard permission requests remain denied; pasted contents are not included in diagnostics.

Each linked task owns an optional temporary Cloudflare tunnel. Public exposure requires explicit confirmation of its exact HTTP(S) origin, without credentials/path/query/fragment. Remote links require a URL plus connection-registration output, not merely a URL announcement. UI starts copy once and show an in-app notice; CLI starts do not change the clipboard. Registration is not an HTTP origin-health check. Stops are scoped to that server's tunnel; changing its URL requires stopping the tunnel first.

## Native UI

Use standard `NavigationSplitView`, sidebar `List`, toolbar items, buttons, menus, popovers, sheets, alerts, `NSOpenPanel`, and SF Symbols. Independent task edit/pin actions belong in a popover, not custom-drawn menu rows. Terminal panes use AppKit `NSSplitView`; their orientation/proportion persist. An empty project hides the tab strip.

Keep terminal content opaque and readable. Let native controls adopt current platform materials instead of simulating blur or glass. Use semantic labels rather than color alone; throttle output activity and respect Reduce Motion. Follow Apple's [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), and [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) guidance.

## Current limitations

- Zsh only; broader prompt-framework compatibility, stubborn/detached processes, and long-running stress acceptance need further testing.
- Terminal text accessibility/VoiceOver, IME, native selection/copy/paste, resize/reflow, multiple hidden surfaces, and Intel builds need broader live acceptance. Automated lifecycle tests are not complete accessibility or input-method certification.
- Two panes, not nested splits; no dependency/group runner, automatic source refresh, explicit saved-task removal, or complete keyboard tab navigation.
- No log-tail, force-kill, or arbitrary terminal-input CLI API. No Keychain storage or export feature.
- Tunnel tests simulate output/lifecycle without exposure. Real public-tunnel acceptance, origin reachability, and missing-cloudflared UX remain separate checks requiring authorization.
- Local development signing is not a distribution release; complete third-party notices/compliance and [publication checks](public-source.md) remain required.
