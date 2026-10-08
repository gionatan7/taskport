# Local control

Build with `bash scripts/build.sh`. The app bundles `Contents/MacOS/taskport-cli`. Taskport → Settings → Integrations installs or uninstalls `~/.local/bin/taskport`, a symlink to that executable. Ensure this directory is on PATH; the installer never changes shell configuration or overwrites another command. Developers may still use `bash scripts/taskport`. Names differ from the GUI executable to avoid collisions on case-insensitive volumes.

Integrations also installs the portable agent skill into selected standard user-wide folders, defaulting to `~/.agents/skills` for Codex and compatible agents. It links each `taskport` skill folder to `Contents/Resources/AgentSkills/taskport` in this app and confirms paths before changes. Existing files or other links are never replaced; move an existing skill aside yourself before installing the bundled version. Uninstall removes only links to this app. The skill invokes `taskport` from PATH and has no checkout dependency. Custom agent configuration directories require manual installation.

Global installation does not bypass agent sandbox permissions. If access to the socket or macOS launch services is denied, request execution approval instead of treating the app as missing or launching a server directly.

## Interface

See `taskport help` for the maintained command grammar (`bash scripts/taskport help` is the checkout-local developer alternative). Supported operations:

- Projects: list, add, edit name/folder.
- Tasks: list, add, edit name/command/cwd/kind/pinning/environment overrides/URL/temporary status, start/stop selected IDs or all pinned services.
- Sessions: active terminal tasks/manual commands across projects; `--all` includes idle open shells.
- Ports: `taskport ports list` reports TCP listeners visible to the current user across the Mac, including servers outside Taskport. This command runs directly in the CLI without the app or socket.
- Status: all project summaries and task state. Session “threads” mean Taskport terminals, not Codex chats.

IDs are UUIDs from list responses. Task selections are validated in full before execution, then per-task outcomes describe partial failures. `start_requested` and `stop_requested` acknowledge asynchronous work; inspect status for completion. Active starts return `already_active`. Stop targets only the managed task, never an unrelated manually entered command. Restart is stop → bounded status checks → start after exit and `terminalInUse == false`. A stubborn process needs user attention/explicit force stop in the app.

Add/edit never execute commands. Command definitions apply on the next start. Imported name/command/cwd/environment edits require `--confirm-local-override` after explaining the notice; originals remain unchanged. Pinning and run classification apply immediately and do not create overrides or require that flag. `--pinned true` classifies a task as long-running; unpinning leaves its classification unchanged. Environment values are omitted from list responses, but commands and paths may still be private. Do not attach raw CLI output to public issues without review.

Change a project's folder with `taskport projects edit PROJECT_ID --directory /example/projects/new-folder`, or Edit project → Folder → Change… in the app. The destination must be an existing absolute directory and cannot belong to another registered project; symlinks are resolved. Stop all tasks and tunnels in that project, finish manually running commands, and clear unfinished terminal input first. Wait for terminals to become idle; starting, stopping, or closing shells also block changes. Idle shells close automatically after saving, preserving tabs and output. Wait for their `shellPID` to reach zero before starting tasks again; the next start opens fresh shells with the new cwd and environment.

The project ID, tasks, pins, overrides, URLs, and pane layout stay saved. Relative task directories and `${workspaceFolder}` resolve against the new folder. Absolute task paths, command literals, and environment literals stay unchanged; review those if they refer to the old location. No files are moved and no tasks are automatically re-imported. Use Import tasks separately to review definitions in the new folder.

`--env-file` accepts a JSON string dictionary, including empty and multiline values. The native editor preserves those values through separate name/value rows. Task editor saves compare against their opening snapshot: a concurrent CLI edit or task removal causes an explicit conflict instead of being overwritten by the older GUI form. Project editor saves check name, folder, and icon for conflicts while preserving concurrent task/pane changes. CLI mutations remain serialized on the app's main actor.

Exit codes: 0 success, 1 operation/partial failure, 2 usage/transport/inspection failure. A timeout after submission does not prove a mutation failed. No automatic retries; query state before deciding whether to retry. No logs API, force-kill command, or arbitrary terminal-input command is exposed.

`tunnels start PROJECT_ID TASK_ID --confirm-public-url URL` starts or reuses the server task's tunnel without activating a window. The explicit confirmation must exactly match the current task URL, including when reusing a tunnel. `tunnels status PROJECT_ID TASK_ID` returns the tunnel in `tasks` (empty if absent), with its phase and active `remoteURL`. Poll status for readiness; start acknowledges launch, not public availability. `tunnels stop PROJECT_ID TASK_ID` interrupts only that server's tunnel. All three accept the server task ID, not the tunnel ID. No UI confirmation is required for CLI requests; Taskport must already be running in the logged-in session and the Mac must be awake. Public exposure still requires user authorization. Tests use simulated tunnels, not public connections.

`remoteURL` remains absent until the tunnel has advertised its URL and logged a registered connection. This is a startup signal, not a health probe or a promise of ongoing availability; verify the public page separately. Only UI-started tunnels automatically copy their link and show an in-app notice. CLI starts never alter the clipboard or require that sheet/notice to complete.

`tasks add/edit --url URL` stores an optional HTTP(S) origin on that task; `--url ''` clears it. Project-level `--url` is no longer accepted. URL and temporary status are metadata, not imported-definition overrides. Task responses include `localURL`, `temporary`, and (for tunnel terminals) `tunnelForTaskID` plus `remoteURL` while active. Changing a URL requires its tunnel to be stopped first.

`--temporary true` creates an unpinned experiment. Its task and terminal are removed after successful completion or an explicit stop, once the process exits. Failure output stays until dismissed; stopping an already-inactive temporary task returns `removed`. A disappearing ID after stop is completion, not a transport failure. To rerun a removed experiment, add it again and use its new ID. Temporary tasks are discarded on relaunch and never resume. Stopping a server also stops its associated tunnel; other task tunnels remain independent.

## Choosing a web-server port

```sh
taskport ports list
```

Example response: `{"ok":true,"ports":[3000,5173,8080]}`. `ports` is sorted and deduplicated across IPv4/IPv6 and local interfaces. It uses macOS's built-in `/usr/sbin/lsof` with machine-readable output, not saved task URLs or the app's per-project cache. Only port numbers are returned, not process arguments, paths, or remote endpoints. Diagnostics and malformed output fail the command instead of returning a misleading empty/partial list.

Choose an unlisted port above 1023, avoiding other saved tasks' configured ports where practical. Configure the server and its task URL together; use Vite's `strictPort` to prevent silent fallback. Then start through Taskport and verify the task, its actual listening port, and a local response. The list is a snapshot, not a reservation or a guarantee of a successful bind: macOS may hide protected/other-user processes; UDP, outgoing connections, bound-but-not-listening sockets, and ports claimed afterward are outside its scope. Sandboxed agents may need execution approval for inspection, but the command never requests sudo or changes services.

## Transport and ownership

One newline-delimited JSON request/response per Unix-domain socket connection; 1 MiB limit, ten-second I/O timeout, at most eight concurrent clients. The private data directory must be owner-only (0700) and not a symlink; the socket is 0600. Both client and server check peer UID. This is a same-user automation boundary, not protection against malicious software already running as that user.

An exclusive `flock` prevents competing app instances from serving/writing the same workspace. Only a stale owned socket is replaced, after obtaining that lock. Startup control errors leave the store read-only. Socket I/O runs off the main actor; store mutations remain serialized on it. The app cleans up its socket on normal Quit; a later app launch recovers a stale socket after a crash. The lock file remains as a harmless private coordination file.

`TASKPORT_DATA_DIR` can isolate tests; app and CLI must use the same directory. macOS Unix socket paths are limited in length; overly long custom directories fail clearly. `launch` opens the bundled app and returns before it is ready: query status afterward. It does not install or launch a daemon.
