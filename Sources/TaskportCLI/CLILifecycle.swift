import AppKit
import MachO
import TaskportControl

@MainActor enum CLILifecycle {
    static func perform(_ request: ControlRequest) async throws -> ControlResponse {
        if let path = ProcessInfo.processInfo.environment["TASKPORT_DATA_DIR"], !path.hasPrefix("/") {
            throw ControlError("TASKPORT_DATA_DIR must be absolute. No lifecycle action was performed.")
        }
        let directory = ControlPaths.directory
        let restoring = request.flags.contains("restore")
        if request.operation == "app.launch", !restoring {
            let lease = FileManager.default.fileExists(atPath: directory.path) ? try LifecycleLease(directory: directory) : nil
            defer { _fixLifetime(lease) }
            try await launch(handoffID: nil)
            var response = ControlResponse(); response.state = "launch_requested"; return response
        }
        let lease = try LifecycleLease(directory: directory)
        defer { _fixLifetime(lease) }
        if request.operation != "app.launch" {
            let id = UUID()
            let quitting = try LocalSocket.request(.init(operation: "app.quit", values: ["handoff-id": id.uuidString],
                flags: request.flags.intersection(["include-one-offs", "include-tunnels"])))
            guard quitting.ok else { return quitting }
            guard quitting.handoffID == id, let pid = quitting.processID, pid > 1 else {
                throw ControlError("Invalid quit acknowledgement. Inspect Taskport before retrying; it may be shutting down.")
            }
            let deadline = Date().addingTimeInterval(15)
            while kill(pid, 0) == 0 || errno != ESRCH {
                guard Date() < deadline else {
                    throw ControlError("Taskport did not exit; nothing was installed or relaunched. Inspect status and the app before retrying.")
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try LifecycleLease.requireStopped(directory: directory)
            if request.operation == "app.quit" {
                var response = quitting; response.state = "session_saved"; return response
            }
        }
        try LifecycleLease.requireStopped(directory: directory)
        let saved = try SessionHandoff.load(in: directory)
        guard kill(saved.sourceProcessID, 0) != 0, errno == ESRCH else {
            throw ControlError("The saved session's original app is still running. Nothing was relaunched.")
        }
        try await launch(handoffID: saved.id)
        let deadline = Date().addingTimeInterval(75)
        while Date() < deadline {
            if let response = try? LocalSocket.request(.init(operation: "app.restore-status")) {
                if response.handoffID == saved.id, response.state != "restoring" { return response }
                if let id = response.handoffID, id != saved.id {
                    throw ControlError("Another launch owns this workspace. No automatic retry was attempted.")
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ControlError("Restore result timed out. Query restore status, task status, and logs; do not rerun commands blindly.")
    }

    private static func launch(handoffID: UUID?) async throws {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var path = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&path, &size) == 0 else { throw ControlError("Couldn't locate the bundled CLI executable.") }
        let executable = URL(fileURLWithPath: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).resolvingSymlinksInPath()
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard bundle.pathExtension == "app" else { throw ControlError("Use the CLI bundled in Taskport.app, or scripts/taskport.") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = handoffID != nil
        if let handoffID { configuration.arguments = ["--restore-session", handoffID.uuidString] }
        if let path = ProcessInfo.processInfo.environment["TASKPORT_DATA_DIR"] {
            guard path.hasPrefix("/") else { throw ControlError("TASKPORT_DATA_DIR must be absolute.") }
            configuration.environment = ["TASKPORT_DATA_DIR": path]
        }
        do { _ = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) }
        catch { throw ControlError("Couldn't launch Taskport. Check execution permissions before rebuilding. \(error.localizedDescription)") }
    }
}
