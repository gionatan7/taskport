import Foundation

public enum CLIArguments {
    public static let help = """
    Taskport — local project/task control (JSON output)

    taskport launch
    taskport status
    taskport projects list
    taskport projects add --directory PATH [--name NAME]
    taskport projects edit PROJECT_ID [--name NAME] [--directory PATH]
    taskport tasks list PROJECT_ID
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
    Temporary tasks cannot be pinned or resumed; they are removed after stop/success.
    Failures remain until closed or explicitly stopped. A missing temporary task ID after
    stop means removal completed; recreate it if needed rather than restarting that ID.
    Task output includes localURL, temporary, tunnelForTaskID, and active remoteURL.
    Imported edits change only Taskport's copy; explain the notice before confirming.
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
                if ["all", "confirm-local-override", "json"].contains(key) {
                    if key != "json" { flags.insert(key) }
                } else {
                    guard index + 1 < arguments.count, values[key] == nil else { throw ControlError("Missing or duplicate value for \(argument).") }
                    index += 1; values[key] = arguments[index]
                }
            } else { positional.append(argument) }
            index += 1
        }
        guard let noun = positional.first else { throw ControlError("Run taskport help for commands.") }
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
        let projectOperations = ["projects.edit", "tasks.list", "tasks.add", "tasks.edit", "tasks.start", "tasks.stop", "tunnels.start", "tunnels.status", "tunnels.stop"]
        var projectID: UUID?
        var taskIDs: [UUID] = []
        if projectOperations.contains(operation) {
            guard positional.count >= 3, let id = UUID(uuidString: positional[2]) else { throw ControlError("Use a project UUID from projects list.") }
            projectID = id
            taskIDs = try positional.dropFirst(3).map {
                guard let id = UUID(uuidString: $0) else { throw ControlError("Use task UUIDs from tasks list.") }
                return id
            }
            if operation == "tasks.edit" || operation.hasPrefix("tunnels.") {
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
