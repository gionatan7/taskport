import AppKit
import Testing
import TaskportControl
@testable import Taskport

struct TaskLinkTests {
    @Test @MainActor func tunnelCopyIsUIOnlyAndOnce() throws {
        let root = testDirectory("tunnel-copy")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        clipboard.setString("User clipboard", forType: .string)
        let taskID = UUID()
        let url = try #require(URL(string: "https://example.trycloudflare.com"))
        store.completeTunnelCopy(taskID, url: url, pasteboard: clipboard)
        #expect(clipboard.string(forType: .string) == "User clipboard")
        #expect(store.tunnelCopyNotice == nil)
        store.pendingTunnelCopies.insert(taskID)
        store.completeTunnelCopy(taskID, url: url, pasteboard: clipboard)
        #expect(clipboard.string(forType: .string) == url.absoluteString)
        #expect(store.tunnelCopyNotice != nil)
        #expect(store.pendingTunnelCopies.isEmpty)
        let notice = store.tunnelCopyNotice
        clipboard.clearContents()
        clipboard.setString("New user clipboard", forType: .string)
        store.completeTunnelCopy(taskID, url: url, pasteboard: clipboard)
        #expect(clipboard.string(forType: .string) == "New user clipboard")
        #expect(store.tunnelCopyNotice == notice)
    }
    @Test @MainActor func taskMetadataAndCLI() throws {
        let root = testDirectory("task-links")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let control = WorkspaceControl(store: store)
        let definition = TaskDefinition(name: "Web", command: "true")
        let imported = ProjectTask(definition: definition, importedDefinition: definition)
        try store.saveTask(imported, projectID: projectID)
        #expect(store.selectedProject?.linkedTasks.isEmpty == true)
        let edit = try CLIArguments.parse(["tasks", "edit", projectID.uuidString, imported.id.uuidString,
            "--url", "http://localhost:3000", "--temporary", "true"])
        #expect(control.handle(edit).ok)
        let task = try #require(store.selectedProject?.linkedTasks.first)
        #expect(task.temporary && !task.pinned && !task.isOverridden)
        #expect(throws: (any Error).self) { try store.togglePin(task, projectID: projectID) }
        let second = control.handle(.init(operation: "tasks.add", projectID: projectID,
            values: ["name": "API", "command": "true", "url": "http://localhost:3001"]))
        #expect(second.ok)
        #expect(store.selectedProject?.linkedTasks.count == 2)
        #expect(!control.handle(.init(operation: "projects.edit", projectID: projectID, values: ["url": "http://localhost:3001"])).ok)
        #expect(!control.handle(.init(operation: "tasks.edit", projectID: projectID, taskIDs: [imported.id], values: ["url": "file:///private"])).ok)
        #expect(control.handle(.init(operation: "tasks.edit", projectID: projectID, taskIDs: [imported.id], values: ["url": ""])).ok)
        let info = try #require(control.handle(.init(operation: "tasks.list", projectID: projectID)).tasks?.first)
        #expect(info.localURL == nil && info.temporary)
        #expect(control.handle(.init(operation: "tasks.stop", projectID: projectID, taskIDs: [imported.id])).results?.first?.outcome == "removed")
        #expect(store.selectedProject?.tasks.count == 1)
        #expect(store.sessions.isEmpty)
        #expect(try store.persistence.load() == store.document)
    }

    @Test @MainActor func temporarySuccessStopAndFailure() async throws {
        let root = testDirectory("temporary")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        defer { store.terminateAll() }
        let success = ProjectTask(definition: TaskDefinition(name: "Success", command: "true"), temporary: true)
        let failure = ProjectTask(definition: TaskDefinition(name: "Failure", command: "false"), temporary: true)
        let interruptedFailure = ProjectTask(definition: TaskDefinition(name: "Exit 130", command: "exit 130"), temporary: true)
        let stopped = ProjectTask(definition: TaskDefinition(name: "Stop", command: "sleep 60"), temporary: true)
        let keyboardStop = ProjectTask(definition: TaskDefinition(name: "Ctrl-C", command: "sleep 60"), temporary: true)
        for task in [success, failure, interruptedFailure, stopped, keyboardStop] {
            try store.saveTask(task, projectID: projectID)
            try store.startTask(task.id, projectID: projectID, activate: false)
        }
        try await waitUntil {
            store.session(success.id) == nil && store.session(failure.id)?.phase == .exited(1)
                && store.session(interruptedFailure.id)?.phase.isActive != true && store.session(stopped.id)?.phase == .running
                && store.session(keyboardStop.id)?.phase == .running
        }
        #expect(store.session(interruptedFailure.id)?.phase == .exited(130))
        #expect(store.selectedProject?.tasks.contains { $0.id == interruptedFailure.id } == true)
        #expect(store.session(interruptedFailure.id)?.stopWasRequested == false)
        guard case .inMemory(let memory) = try #require(store.session(keyboardStop.id)).terminal.configuration.backend else {
            Issue.record("Expected the host-I/O backend"); return
        }
        memory.sendInput(Data([3]))
        try await waitUntil { store.session(keyboardStop.id) == nil }
        #expect(store.selectedProject?.tasks.contains { $0.id == keyboardStop.id } == false)
        #expect(store.selectedProject?.tasks.contains { $0.id == success.id } == false)
        #expect(store.selectedProject?.tasks.contains { $0.id == failure.id } == true)
        #expect(store.document.runningPinnedTaskIDs ?? [] == [])
        try store.openTask(stopped.id, projectID: projectID)
        try store.setSplit(projectID: projectID, taskID: failure.id)
        store.stopTask(stopped.id, projectID: projectID)
        try await waitUntil { store.session(stopped.id) == nil }
        #expect(store.selectedTaskID == failure.id)
        #expect(store.selectedProject?.split == nil)
        try store.closeTab(failure.id, projectID: projectID)
        try store.closeTab(interruptedFailure.id, projectID: projectID)
        try await waitUntil { store.openShellCount == 0 }
        #expect(store.selectedProject?.tasks.isEmpty == true)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).isEmpty)
    }

    @Test @MainActor func tunnelsAreIsolatedAndURLChangesRequireStop() async throws {
        let root = testDirectory("tunnel-ownership")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        defer { store.terminateAll() }
        var first = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), localURL: "http://localhost:3000")
        let second = ProjectTask(definition: TaskDefinition(name: "API", command: "sleep 60"), localURL: "http://localhost:3001")
        // Simulate tunnel processes locally; no real public exposure in tests.
        let tunnel1 = ProjectTask(definition: TaskDefinition(name: "Tunnel Web", command: "sleep 60"),
            sourceKey: "builtin:cloudflare", temporary: true, tunnelForTaskID: first.id)
        let tunnel2 = ProjectTask(definition: TaskDefinition(name: "Tunnel API", command: "sleep 60"),
            sourceKey: "builtin:cloudflare", temporary: true, tunnelForTaskID: second.id)
        for task in [first, second, tunnel1, tunnel2] { try store.saveTask(task, projectID: projectID) }
        let control = WorkspaceControl(store: store)
        let cliStart = try CLIArguments.parse(["tunnels", "start", projectID.uuidString, first.id.uuidString,
            "--confirm-public-url", "http://localhost:3000"])
        #expect(!control.handle(.init(operation: "tunnels.start", projectID: projectID, taskIDs: [first.id])).ok)
        #expect(!control.handle(.init(operation: "tunnels.start", projectID: projectID, taskIDs: [first.id],
            values: ["confirm-public-url": "http://localhost:9999"])).ok)
        #expect(!control.handle(.init(operation: "tunnels.start", projectID: projectID, taskIDs: [tunnel1.id],
            values: ["confirm-public-url": "http://localhost:3000"])).ok)
        #expect(throws: (any Error).self) { try CLIArguments.parse(["tunnels", "start", projectID.uuidString]) }
        #expect(throws: (any Error).self) {
            try store.startTunnel(for: first.id, projectID: projectID, confirmedURL: "http://localhost:9999")
        }
        #expect(store.sessions.isEmpty)
        for task in [first, second, tunnel1, tunnel2] { try store.startTask(task.id, projectID: projectID, activate: false) }
        try await waitUntil { store.sessions.allSatisfy { $0.phase == .running } }
        let selected = store.selectedTaskID
        let pid = store.session(tunnel1.id)?.shellPID
        #expect(control.handle(cliStart).tasks?.first?.id == tunnel1.id)
        #expect(store.session(tunnel1.id)?.shellPID == pid)
        #expect(store.selectedTaskID == selected)
        let status = try CLIArguments.parse(["tunnels", "status", projectID.uuidString, first.id.uuidString])
        #expect(control.handle(status).tasks?.first?.phase == "running")
        #expect(store.tunnel(for: first.id, in: try #require(store.selectedProject))?.id == tunnel1.id)
        first.localURL = "http://localhost:3002"
        #expect(throws: (any Error).self) { try store.saveTask(first, projectID: projectID) }
        let stop = try CLIArguments.parse(["tunnels", "stop", projectID.uuidString, first.id.uuidString])
        #expect(control.handle(stop).ok)
        try await waitUntil { store.session(tunnel1.id) == nil }
        #expect(control.handle(status).tasks?.isEmpty == true)
        #expect(control.handle(stop).ok)
        #expect(store.session(first.id)?.phase == .running)
        #expect(store.session(tunnel2.id)?.phase == .running)
        #expect(store.session(second.id)?.phase == .running)
        try store.saveTask(first, projectID: projectID)
        store.stopAll()
        try await waitUntil { store.session(tunnel2.id) == nil }
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func temporaryTasksArePurgedOnRelaunch() throws {
        let root = testDirectory("temporary-relaunch")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let saved = ProjectTask(definition: TaskDefinition(name: "Saved", command: "true"))
        let temporary = ProjectTask(definition: TaskDefinition(name: "Experiment", command: "true"), temporary: true)
        try store.saveTask(saved, projectID: projectID)
        try store.saveTask(temporary, projectID: projectID)
        try store.openTask(temporary.id, projectID: projectID)
        try store.setSplit(projectID: projectID, taskID: saved.id)
        let reopened = WorkspaceStore(directory: store.persistence.directory)
        reopened.resumePinnedTasks()
        #expect(reopened.selectedProject?.tasks == [saved])
        #expect(reopened.selectedTaskID == saved.id)
        #expect(reopened.selectedProject?.split == nil)
        #expect(reopened.sessions.isEmpty)
        #expect(try reopened.persistence.load() == reopened.document)
    }
}
