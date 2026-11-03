import Foundation
import Testing
import TaskportControl
@testable import Taskport

struct TaskRemovalTests {
    @Test func argumentsRequireExactlyOneTaskID() throws {
        let project = UUID(), task = UUID()
        let request = try CLIArguments.parse(["tasks", "remove", project.uuidString, task.uuidString])
        #expect(request.operation == "tasks.remove")
        #expect(request.projectID == project && request.taskIDs == [task])
        for arguments in [
            ["tasks", "remove"],
            ["tasks", "remove", project.uuidString],
            ["tasks", "remove", project.uuidString, task.uuidString, UUID().uuidString],
            ["tasks", "remove", "invalid", task.uuidString],
            ["tasks", "remove", project.uuidString, "invalid"]
        ] {
            #expect(throws: ControlError.self) { try CLIArguments.parse(arguments) }
        }
    }

    @Test @MainActor func removalPersistsWithoutEditingImportedSourcesOrResurrectingTasks() throws {
        let root = testDirectory("task-removal")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("package.json")
        let contents = Data(#"{"scripts":{"build":"true"}}"#.utf8)
        try contents.write(to: source)
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let definition = TaskDefinition(name: "Build", command: "bun run build")
        let imported = ProjectTask(definition: definition, pinned: true, source: "package.json",
            sourceKey: "package:build", importedDefinition: definition)
        let remaining = ProjectTask(definition: TaskDefinition(name: "Other", command: "true"))
        for task in [imported, remaining] { try store.saveTask(task, projectID: projectID) }
        try store.openTask(remaining.id, projectID: projectID)
        try store.openTask(imported.id, projectID: projectID)
        try store.commit { $0.runningPinnedTaskIDs = [imported.id, remaining.id] }
        let control = WorkspaceControl(store: store)
        let request = try CLIArguments.parse(["tasks", "remove", projectID.uuidString, imported.id.uuidString])
        let response = control.handle(request)
        #expect(response.ok && response.projectID == projectID && response.taskID == imported.id)
        #expect(store.selectedProject?.tasks == [remaining])
        #expect(store.selectedTaskID == remaining.id)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).map(\.id) == [remaining.id])
        #expect(store.document.runningPinnedTaskIDs == [remaining.id])
        #expect(store.sessions.isEmpty)
        #expect(try Data(contentsOf: source) == contents)
        #expect(try store.persistence.load() == store.document)
        #expect(WorkspaceStore(directory: store.persistence.directory).document == store.document)
        #expect(throws: WorkspaceError.self) { try store.saveTask(imported, projectID: projectID, replacing: imported) }
        #expect(!control.handle(request).ok)
        #expect(control.handle(.init(operation: "tasks.remove", projectID: projectID, taskIDs: [remaining.id])).ok)
        #expect(store.selectedProject?.tasks.isEmpty == true && store.selectedTaskID == nil)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).isEmpty)
        #expect(try store.persistence.load() == store.document)
        #expect(try Data(contentsOf: source) == contents)
    }

    @Test @MainActor func invalidRequestsAndReadOnlyWorkspacesLeaveDefinitionsUntouched() throws {
        let root = testDirectory("task-removal-validation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let first = try store.addProject(name: "First", directory: root.path)
        let second = try store.addProject(name: "Second", directory: store.persistence.directory.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Example", command: "true"))
        try store.saveTask(task, projectID: first)
        try store.openTask(task.id, projectID: first)
        let control = WorkspaceControl(store: store)
        let before = store.document
        for request in [
            ControlRequest(operation: "tasks.remove", projectID: first),
            .init(operation: "tasks.remove", projectID: first, taskIDs: [task.id, UUID()]),
            .init(operation: "tasks.remove", projectID: second, taskIDs: [task.id]),
            .init(operation: "tasks.remove", projectID: UUID(), taskIDs: [task.id]),
            .init(operation: "tasks.remove", projectID: first, taskIDs: [UUID()]),
            .init(operation: "tasks.remove", projectID: first, taskIDs: [task.id], flags: ["all"]),
            .init(operation: "tasks.remove", projectID: first, taskIDs: [task.id], values: ["name": "Ignored"])
        ] {
            #expect(!control.handle(request).ok)
            #expect(store.document == before)
            #expect(try store.persistence.load() == before)
        }
        store.blockWrites("Read-only test workspace")
        #expect(!control.handle(.init(operation: "tasks.remove", projectID: first, taskIDs: [task.id])).ok)
        #expect(store.document == before)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).map(\.id) == [task.id])
        #expect(try store.persistence.load() == before)
    }

    @Test @MainActor func busyTerminalsBlockRemovalAndIdleShellsAreReaped() async throws {
        let root = testDirectory("task-removal-shells")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 30"), pinned: true)
        let other = ProjectTask(definition: TaskDefinition(name: "Other", command: "sleep 30"), pinned: true)
        for saved in [task, other] { try store.saveTask(saved, projectID: projectID) }
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try store.startTask(other.id, projectID: projectID, activate: false)
        let terminal = try #require(store.session(task.id))
        let control = WorkspaceControl(store: store)
        let request = ControlRequest(operation: "tasks.remove", projectID: projectID, taskIDs: [task.id])
        #expect(!control.handle(request).ok)
        try await waitUntil { terminal.phase == .running && store.session(other.id)?.phase == .running }
        let otherPID = store.session(other.id)?.shellPID
        #expect(!control.handle(request).ok)
        #expect(terminal.phase == .running)
        store.stopTask(task.id, projectID: projectID)
        #expect(!control.handle(request).ok)
        try await waitUntil { terminal.canStart && terminal.shellReady }
        guard case .inMemory(let memory) = terminal.terminal.configuration.backend else {
            Issue.record("Expected the host-I/O backend"); return
        }
        memory.sendInput(Data("sleep 30\n".utf8))
        try await waitUntil { terminal.manualCommandRunning }
        #expect(!control.handle(request).ok)
        #expect(terminal.manualCommandRunning)
        terminal.stop(includeManual: true, focus: false)
        try await waitUntil { terminal.canStart && terminal.shellReady }
        memory.sendInput(Data("unfinished".utf8))
        try await waitUntil { terminal.hasPendingInput }
        #expect(!control.handle(request).ok)
        #expect(terminal.hasPendingInput)
        memory.sendInput(Data([3]))
        try await waitUntil { terminal.canStart && terminal.shellReady }
        #expect(control.handle(request).ok)
        #expect(store.selectedProject?.tasks == [other])
        try await waitUntil { store.session(task.id) == nil && terminal.shellPID == 0 }
        #expect(store.session(other.id)?.phase == .running)
        #expect(store.session(other.id)?.shellPID == otherPID)
        #expect(try store.persistence.load() == store.document)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func removalRejectsActiveTunnelsAndCleansUpFailedAssociatedTunnels() async throws {
        let root = testDirectory("task-removal-tunnels")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let owner = ProjectTask(definition: TaskDefinition(name: "Web", command: "true"), pinned: true)
        let other = ProjectTask(definition: TaskDefinition(name: "API", command: "true"), pinned: true)
        let tunnel = ProjectTask(definition: TaskDefinition(name: "Failed tunnel", command: "false"),
            sourceKey: "builtin:cloudflare", temporary: true, tunnelForTaskID: owner.id)
        let otherTunnel = ProjectTask(definition: TaskDefinition(name: "Other tunnel", command: "true"),
            sourceKey: "builtin:cloudflare", temporary: true, tunnelForTaskID: other.id)
        for task in [owner, other, tunnel, otherTunnel] { try store.saveTask(task, projectID: projectID) }
        defer { store.terminateAll() }
        try store.openTask(tunnel.id, projectID: projectID)
        try store.startTask(tunnel.id, projectID: projectID, activate: false)
        let control = WorkspaceControl(store: store)
        let request = ControlRequest(operation: "tasks.remove", projectID: projectID, taskIDs: [owner.id])
        #expect(!control.handle(request).ok)
        #expect(store.selectedProject?.tasks.count == 4)
        let terminal = try #require(store.session(tunnel.id))
        try await waitUntil { terminal.phase == .exited(1) && terminal.shellReady }
        store.pendingTunnelCopies.insert(tunnel.id)
        #expect(control.handle(request).ok)
        #expect(store.selectedProject?.tasks == [other, otherTunnel])
        #expect(store.selectedTaskID == other.id)
        #expect(store.pendingTunnelCopies.isEmpty)
        try await waitUntil { store.session(tunnel.id) == nil && terminal.shellPID == 0 }
        #expect(try store.persistence.load() == store.document)
    }
}
