import Foundation

public enum CLIArguments {
    public static let help = """
    Taskport — local project/task control (JSON output)

    taskport launch [--restore]
    taskport restart --restore [--include-one-offs] [--include-tunnels]
    taskport quit --save-session [--include-one-offs] [--include-tunnels]
    taskport restore status
    taskport status
    taskport groups list
    taskport groups add --name NAME
    taskport groups edit GROUP_ID --name NAME
    taskport groups remove GROUP_ID
    taskport projects list
    taskport projects add --directory PATH [--name NAME] [--group GROUP_ID]
    taskport projects edit PROJECT_ID [--name NAME] [--directory PATH] [--group GROUP_ID|none]
    taskport projects remove PROJECT_ID
    taskport tasks list PROJECT_ID
    taskport tasks logs PROJECT_ID TASK_ID [--lines 100]
    taskport tasks add PROJECT_ID --name NAME --command COMMAND
      [--cwd DIRECTORY] [--kind service|oneOff] [--pinned true|false] [--env-file JSON_FILE]
      [--url URL] [--temporary true|false]
    taskport tasks edit PROJECT_ID TASK_ID [same task options] [--confirm-local-override]
    taskport tasks start PROJECT_ID TASK_ID... | --all
    taskport tasks stop PROJECT_ID TASK_ID... | --all
    taskport sessions list [--all]
    taskport ports list
    taskport tunnels start PROJECT_ID TASK_ID --confirm-public-url URL
    taskport tunnels status PROJECT_ID TASK_ID
    taskport tunnels stop PROJECT_ID TASK_ID

    Tunnel commands take the server task ID, not the tunnel ID. Starting requires
    explicit authorization to expose the exact configured URL publicly. No UI is opened.
    Poll tunnels status for tasks[0].remoteURL; tasks: [] means no tunnel exists.

    Task start/stop --all selects pinned long-running tasks only, never one-offs or tunnels.
    Group removal keeps its projects, tasks, and files; projects become ungrouped.
    Project removal deletes only Taskport's saved entry and task definitions, never files.
    Stop tasks and manual commands and clear unfinished input before removing a project.
    tasks logs returns output and outputTruncated, capturing up to 128 KiB in memory per
    terminal since this app launch. --lines accepts 1–1000 (default 100). ANSI controls
    are omitted. Output may contain secrets; do not publish it. No disk log or stdin access.
    sessions list shows active tasks/manual commands; --all also includes idle open shells.
    ports list returns sorted unique TCP listening ports visible to your user (IPv4/IPv6),
    including non-Taskport servers. It works without the app running. This is a snapshot,
    not a reservation or a guarantee that a bind will succeed; UDP and hidden processes
    are not included. Inspection errors fail the command; they do not mean ports are free.
    Task status distinguishes starting/running/stopping/exited/failed from terminalInUse.
    Add/edit never run commands. Existing active tasks are reused. Stop sends Ctrl-C;
    wait for exited/stopped before starting again. No implicit restart or force-kill.
    Project folder changes require idle terminals, including stopped tunnels and cleared
    input. Idle shells close; tabs/output and tasks stay saved. Relative paths use the
    new folder; absolute task paths stay unchanged. Files and imports are not moved.
    --env-file replaces the task's environment overrides with a JSON string dictionary.
    URLs belong to tasks, not projects. Use --url '' to clear one.
    Temporary tasks cannot be pinned; they are removed after stop/success.
    Failures remain until closed or explicitly stopped. A missing temporary task ID after
    stop means removal completed; recreate it if needed rather than restarting that ID.
    Task output includes localURL, temporary, tunnelForTaskID, and active remoteURL.
    Imported edits change only Taskport's copy; explain the notice before confirming.
    Explicit restore restarts only previously starting/running tasks, including unpinned
    and temporary services, once, regardless of the normal resume setting. Commands start
    from the beginning; process memory and terminal output/input are not preserved.
    Manual commands/unfinished input block shutdown. Active one-offs and tunnels block
    unless explicitly included: one-offs run again, tunnel URLs can change. Already-stopping
    tasks are skipped. A private saved session expires after 24 hours and is consumed before
    execution. A normal launch discards it and uses the normal pinned-task resume setting.
    quit --save-session waits for app exit; launch --restore waits for per-task results.
    restore status inspects that launch's result. Failed restores are not retried automatically.
    Exit: 0 success, 1 operation/partial failure, 2 usage/connection/inspection failure.
    A connection timeout after submission has an unknown outcome: inspect status, don't
    blindly retry a mutation. No automatic retries or automatic app launch.
    """

    public static func parse(_ arguments: [String]) throws -> ControlRequest {
        var positional: [String] = [], values: [String: String] = [:], flags: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let key = String(argument.dropFirst(2))
                if ["all", "confirm-local-override", "json", "restore", "save-session", "include-one-offs", "include-tunnels"].contains(key) {
                    guard !flags.contains(key) else { throw ControlError("Duplicate option \(argument).") }
                    if key != "json" { flags.insert(key) }
                } else {
                    guard index + 1 < arguments.count, values[key] == nil else { throw ControlError("Missing or duplicate value for \(argument).") }
                    index += 1; values[key] = arguments[index]
                }
            } else { positional.append(argument) }
            index += 1
        }
        guard let noun = positional.first else { throw ControlError("Run taskport help for commands.") }
        if ["launch", "quit", "restart"].contains(noun) {
            let required: Set<String> = noun == "quit" ? ["save-session"] : noun == "restart" ? ["restore"] : []
            let allowed: Set<String> = noun == "launch" ? ["restore"] : required.union(["include-one-offs", "include-tunnels"])
            guard positional.count == 1, values.isEmpty, required.isSubset(of: flags), flags.isSubset(of: allowed) else {
                throw ControlError("Usage: taskport launch [--restore], restart --restore, or quit --save-session. See help for opt-ins.")
            }
            return ControlRequest(operation: "app.\(noun)", flags: flags)
        }
        if positional == ["restore", "status"], values.isEmpty, flags.isEmpty {
            return ControlRequest(operation: "app.restore-status")
        }
        if noun == "ports" {
            guard positional == ["ports", "list"], values.isEmpty, flags.isEmpty else {
                throw ControlError("Usage: taskport ports list")
            }
            return ControlRequest(operation: "ports.list")
        }
        if noun == "status" {
            guard positional.count == 1, values.isEmpty, flags.isEmpty else { throw ControlError("Usage: taskport status") }
            return ControlRequest(operation: "status")
        }
        guard positional.count >= 2 else { throw ControlError("Specify an operation; run taskport help.") }
        let operation = noun + "." + positional[1]
        if noun == "groups" {
            if ["groups.list", "groups.add"].contains(operation), positional.count == 2 {
                return ControlRequest(operation: operation, values: values, flags: flags)
            }
            guard ["groups.edit", "groups.remove"].contains(operation), positional.count == 3,
                  let groupID = UUID(uuidString: positional[2]) else { throw ControlError("Use a group UUID from groups list; run taskport help.") }
            return ControlRequest(operation: operation, values: values, flags: flags, groupID: groupID)
        }
        let projectOperations = ["projects.edit", "projects.remove", "tasks.list", "tasks.logs", "tasks.add", "tasks.edit", "tasks.start", "tasks.stop", "tunnels.start", "tunnels.status", "tunnels.stop"]
        var projectID: UUID?
        var taskIDs: [UUID] = []
        if projectOperations.contains(operation) {
            guard positional.count >= 3, let id = UUID(uuidString: positional[2]) else { throw ControlError("Use a project UUID from projects list.") }
            projectID = id
            taskIDs = try positional.dropFirst(3).map {
                guard let id = UUID(uuidString: $0) else { throw ControlError("Use task UUIDs from tasks list.") }
                return id
            }
            if ["tasks.edit", "tasks.logs"].contains(operation) || operation.hasPrefix("tunnels.") {
                guard taskIDs.count == 1 else { throw ControlError("This operation requires exactly one task ID.") }
            } else if !["tasks.start", "tasks.stop"].contains(operation), !taskIDs.isEmpty {
                throw ControlError("Unexpected extra IDs.")
            }
        } else {
            guard ["projects.list", "projects.add", "sessions.list"].contains(operation), positional.count == 2 else {
                throw ControlError("Unknown command or unexpected arguments; run taskport help.")
            }
        }
        if let path = values.removeValue(forKey: "env-file") {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            _ = try JSONDecoder().decode([String: String].self, from: data)
            values["environment"] = String(decoding: data, as: UTF8.self)
        }
        return ControlRequest(operation: operation, projectID: projectID, taskIDs: taskIDs, values: values, flags: flags)
    }
}
