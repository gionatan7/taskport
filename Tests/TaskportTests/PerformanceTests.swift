import AppKit
import Testing
@testable import Taskport

struct PerformanceTests {
    @Test @MainActor func hostCacheTracksSessionsAndVisiblePlaceholdersNotSavedDefinitions() async throws {
        _ = NSApplication.shared
        let root = testDirectory("host-cache")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tasks = (0..<200).map {
            ProjectTask(definition: TaskDefinition(name: "Task \($0)", command: "printf 'TASKPORT_HOST_OUTPUT\\n'"))
        }
        let project = Project(name: "Many definitions", directory: root.path, tasks: tasks, selectedTaskID: tasks[2].id)
        let persistence = WorkspacePersistence(directory: root.appendingPathComponent("data"))
        try persistence.save(WorkspaceDocument(projects: [project], selectedProjectID: project.id))
        let store = WorkspaceStore(directory: persistence.directory)
        defer { store.terminateAll() }
        for task in tasks.prefix(2) { try store.startTask(task.id, projectID: project.id, activate: false) }
        try await waitUntil { store.sessions.allSatisfy { $0.phase == .exited(0) } }
        let coordinator = NativeTerminalDeck.Coordinator()
        let view = TaskSplitView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        coordinator.update(view, store: store)
        print("PERFORMANCE native hosts: \(coordinator.hosts.count) for 200 definitions, 2 sessions, 1 visible placeholder")
        #expect(coordinator.hosts.count == 3)
        let firstHost = try #require(coordinator.hosts[tasks[0].id])
        let secondHost = try #require(coordinator.hosts[tasks[1].id])
        let firstSession = try #require(store.session(tasks[0].id))
        try store.openTask(tasks[3].id, projectID: project.id)
        coordinator.update(view, store: store)
        #expect(coordinator.hosts.count == 3)
        #expect(coordinator.hosts[tasks[2].id] == nil)
        #expect(coordinator.hosts[tasks[0].id] === firstHost)
        #expect(coordinator.hosts[tasks[1].id] === secondHost)
        try store.openTask(tasks[0].id, projectID: project.id)
        try store.setSplit(projectID: project.id, taskID: tasks[1].id)
        coordinator.update(view, store: store)
        #expect(coordinator.hosts.count == 2)
        #expect(view.arrangedSubviews.count == 2)
        #expect(coordinator.hosts[tasks[0].id] === firstHost)
        #expect(store.session(tasks[0].id) === firstSession)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        try await waitUntil { firstSession.terminal.surface != nil }
        let surface = try #require(firstSession.terminal.surface)
        guard case .inMemory(let memory) = firstSession.terminal.configuration.backend else {
            Issue.record("Expected the host-I/O backend"); return
        }
        try await waitUntil { memory.readViewportText()?.contains("TASKPORT_HOST_OUTPUT") == true }
        try store.setSplit(projectID: project.id, taskID: nil)
        try store.openTask(tasks[4].id, projectID: project.id)
        coordinator.update(view, store: store)
        #expect(coordinator.hosts[tasks[0].id] === firstHost)
        #expect(firstHost.isHidden)
        #expect(firstSession.terminal.surface === surface)
        try store.openTask(tasks[0].id, projectID: project.id)
        coordinator.update(view, store: store)
        view.layoutSubtreeIfNeeded()
        #expect(firstSession.terminal.surface === surface)
        #expect(memory.readViewportText()?.contains("TASKPORT_HOST_OUTPUT") == true)
        try store.closeTab(tasks[1].id, projectID: project.id)
        try await waitUntil { store.session(tasks[1].id) == nil }
        coordinator.update(view, store: store)
        #expect(coordinator.hosts.count == 1)
        #expect(coordinator.hosts[tasks[0].id] === firstHost)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func portScanWorkloadWithTwentyOwnedSessions() async throws {
        let root = testDirectory("port-scan-workload")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let processes = (0..<20).map { _ in PTYProcess() }
        defer { processes.forEach { $0.terminate() } }
        for process in processes {
            try process.start(directory: root.path, arguments: ["/bin/sleep", "60"], environment: ["PATH": "/usr/bin:/bin"])
        }
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            let result = ListeningPorts.scan(shellPIDs: processes.map(\.pid))
            samples.append(start.duration(to: clock.now))
            #expect(result.isEmpty)
        }
        print("PERFORMANCE port scan: median \(samples.sorted()[2]) for 20 owned sessions, 5 samples")
        processes.forEach { $0.terminate() }
        try await waitUntil { processes.allSatisfy { $0.pid == 0 } }
    }
}
