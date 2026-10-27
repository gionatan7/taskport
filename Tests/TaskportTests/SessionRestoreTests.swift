import Foundation
import TaskportControl
import Testing
@testable import Taskport

struct SessionRestoreTests {
    @Test func lifecycleArgumentsAreExplicitAndStrict() throws {
        #expect(try CLIArguments.parse(["restart", "--restore"]).operation == "app.restart")
        #expect(try CLIArguments.parse(["quit", "--save-session", "--include-one-offs", "--include-tunnels"]).flags ==
            ["save-session", "include-one-offs", "include-tunnels"])
        #expect(try CLIArguments.parse(["launch", "--restore"]).operation == "app.launch")
        #expect(try CLIArguments.parse(["restore", "status"]).operation == "app.restore-status")
        for arguments in [["restart"], ["quit"], ["launch", "--include-tunnels"],
                          ["restart", "--restore", "--restore"], ["quit", "--save-session", "extra"],
                          ["launch", "--restore", "--unknown", "value"]] {
            #expect(throws: (any Error).self) { try CLIArguments.parse(arguments) }
        }
    }

    @Test func privateBoundedExpiringCheckpointAndExclusiveLifecycleLease() throws {
        let directory = testDirectory("handoff-file")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let checkpoint = SessionHandoff(id: UUID(), sourceProcessID: 42, entries: [], openTaskIDs: [])
        try checkpoint.save(in: directory)
        let file = directory.appendingPathComponent("session-restore.json")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(try SessionHandoff.load(in: directory).id == checkpoint.id)
        #expect(throws: (any Error).self) { try SessionHandoff.load(in: directory, now: Date().addingTimeInterval(86_401)) }
        #expect(throws: (any Error).self) { try SessionHandoff.consume(UUID(), in: directory) }
        #expect(try SessionHandoff.consume(checkpoint.id, in: directory).id == checkpoint.id)
        #expect(throws: (any Error).self) { try SessionHandoff.consume(checkpoint.id, in: directory) }
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory.appendingPathComponent("missing"))
        #expect(throws: (any Error).self) { try SessionHandoff.load(in: directory) }
        try SessionHandoff.discard(in: directory)
        let lease = try LifecycleLease(directory: directory)
        #expect(throws: (any Error).self) { try LifecycleLease(directory: directory) }
        _fixLifetime(lease)
    }

    @Test @MainActor func restoresOnlyActiveTasksIncludingTemporaryAndUnpinnedWithResumeDisabled() async throws {
        let root = testDirectory("session-restore")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let pinned = ProjectTask(definition: TaskDefinition(name: "Pinned", command: "sleep 60"), pinned: true)
        let unpinned = ProjectTask(definition: TaskDefinition(name: "Unpinned", command: "sleep 60"))
        let temporary = ProjectTask(definition: TaskDefinition(name: "Experiment", command: "sleep 60"), temporary: true)
        let idle = ProjectTask(definition: TaskDefinition(name: "Idle", command: "sleep 60"), pinned: true)
        let completed = ProjectTask(definition: TaskDefinition(name: "Completed", command: "true", kind: .oneOff))
        for task in [pinned, unpinned, temporary, idle, completed] { try store.saveTask(task, projectID: projectID) }
        try store.setResumeTasksOnLaunch(false)
        let active = [pinned, unpinned, temporary]
        for task in active + [completed] { try store.startTask(task.id, projectID: projectID, activate: false) }
        try await waitUntil { active.allSatisfy { store.session($0.id)?.phase == .running } && store.session(completed.id)?.phase == .exited(0) }
        try store.openTask(completed.id, projectID: projectID)
        let previousPID = store.session(temporary.id)?.shellPID
        let handoff = try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false)
        #expect(Set(handoff.entries.map(\.taskID)) == Set(active.map(\.id)))
        #expect(throws: (any Error).self) { try store.startTask(idle.id, projectID: projectID, activate: false) }
        #expect(throws: (any Error).self) { try store.setResumeTasksOnLaunch(true) }
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        #expect(store.selectedProject?.tasks.contains { $0.id == temporary.id } == true)
        let relaunched = WorkspaceStore(directory: store.persistence.directory)
        defer { relaunched.terminateAll() }
        relaunched.resumePinnedTasks(restoring: handoff.id)
        try await waitUntil { !relaunched.restoreInProgress }
        #expect(relaunched.restoreError == nil)
        #expect(Set(relaunched.restoreResults.filter { $0.outcome == "restarted" }.map(\.taskID)) == Set(active.map(\.id)))
        #expect(relaunched.session(idle.id) == nil)
        #expect(relaunched.session(completed.id) == nil)
        #expect(relaunched.session(temporary.id)?.shellPID != previousPID)
        #expect(!relaunched.resumeTasksOnLaunch)
        #expect(relaunched.selectedTaskID == completed.id)
        #expect(relaunched.visibleTasks(in: try #require(relaunched.selectedProject)).contains { $0.id == completed.id })
        #expect(throws: (any Error).self) { try SessionHandoff.load(in: store.persistence.directory) }
        relaunched.terminateAll()
        try await waitUntil { relaunched.openShellCount == 0 }
        let replay = WorkspaceStore(directory: store.persistence.directory)
        replay.resumePinnedTasks(restoring: handoff.id)
        #expect(replay.sessions.isEmpty)
        #expect(replay.restoreError != nil)
    }

    @Test @MainActor func manualInputAndChangedRunningDefinitionsBlockBeforeShutdown() async throws {
        let root = testDirectory("restore-guards")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        var task = ProjectTask(definition: TaskDefinition(name: "Service", command: "sleep 60"))
        try store.saveTask(task, projectID: projectID)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        task.definition.command = "sleep 61"
        try store.saveTask(task, projectID: projectID)
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false) }
        #expect(!store.preservingResumeState)
        #expect(store.session(task.id)?.phase == .running)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        // Start a fresh idle shell, then exercise real terminal input rather than changing internal flags.
        let prompt = ProjectTask(definition: TaskDefinition(name: "Prompt", command: "true"))
        try store.saveTask(prompt, projectID: projectID)
        try store.startTask(prompt.id, projectID: projectID, activate: false)
        let terminal = try #require(store.session(prompt.id))
        try await waitUntil { terminal.phase == .exited(0) && terminal.shellReady }
        guard case .inMemory(let memory) = terminal.terminal.configuration.backend else { Issue.record("Expected in-memory terminal"); return }
        memory.sendInput(Data("unfinished".utf8))
        try await waitUntil { terminal.hasPendingInput }
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false) }
        memory.sendInput(Data([3]))
        try await waitUntil { !terminal.hasPendingInput }
        memory.sendInput(Data("sleep 60\r".utf8))
        try await waitUntil { terminal.manualCommandRunning }
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false) }
        #expect(!store.preservingResumeState)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func oneOffsAndTunnelsRequireOptInAndCaptureExactOrigin() async throws {
        let root = testDirectory("restore-opt-in")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let once = ProjectTask(definition: TaskDefinition(name: "Build", command: "sleep 60", kind: .oneOff))
        let server = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), localURL: "http://localhost:3131")
        let tunnel = ProjectTask(definition: TaskDefinition(name: "Simulated tunnel", command: "sleep 60"),
            sourceKey: "builtin:cloudflare", temporary: true, tunnelForTaskID: server.id)
        for task in [once, server, tunnel] { try store.saveTask(task, projectID: projectID) }
        defer { store.terminateAll() }
        for task in [once, tunnel] { try store.startTask(task.id, projectID: projectID, activate: false) }
        try await waitUntil { [once, tunnel].allSatisfy { store.session($0.id)?.phase == .running } }
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: true) }
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: true, includeTunnels: false) }
        let handoff = try store.saveSessionHandoff(id: UUID(), includeOneOffs: true, includeTunnels: true)
        #expect(handoff.entries.first { $0.taskID == tunnel.id }?.confirmedTunnelURL == server.localURL)
        #expect(handoff.entries.first { $0.taskID == once.id } != nil)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        let edited = WorkspaceStore(directory: store.persistence.directory)
        var updatedServer = server
        updatedServer.localURL = "http://localhost:3132"
        try edited.saveTask(updatedServer, projectID: projectID)
        let relaunched = WorkspaceStore(directory: store.persistence.directory)
        defer { relaunched.terminateAll() }
        relaunched.resumePinnedTasks(restoring: handoff.id)
        try await waitUntil { !relaunched.restoreInProgress }
        #expect(relaunched.session(tunnel.id) == nil)
        #expect(relaunched.restoreResults.first { $0.taskID == tunnel.id }?.outcome == "failed")
        #expect(relaunched.restoreResults.first { $0.taskID == once.id }?.outcome == "restarted")
        relaunched.terminateAll()
        try await waitUntil { relaunched.openShellCount == 0 }
    }

    @Test @MainActor func changedOrMissingDefinitionsFailWithoutFallbackOrReplay() async throws {
        let root = testDirectory("restore-changed")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        var task = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), pinned: true)
        try store.saveTask(task, projectID: projectID)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        let handoff = try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        task.definition.environment = ["EXAMPLE": "changed"]
        let editor = WorkspaceStore(directory: store.persistence.directory)
        try editor.saveTask(task, projectID: projectID)
        let relaunched = WorkspaceStore(directory: store.persistence.directory)
        relaunched.resumePinnedTasks(restoring: handoff.id)
        try await waitUntil { !relaunched.restoreInProgress }
        #expect(relaunched.sessions.isEmpty)
        #expect(relaunched.restoreResults.first?.outcome == "failed")
        #expect(relaunched.document.runningPinnedTaskIDs == [])
    }
}
