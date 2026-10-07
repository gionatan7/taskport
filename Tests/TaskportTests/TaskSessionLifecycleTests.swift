import AppKit
import SwiftUI
import TaskportControl
import Testing
@testable import Taskport

struct TaskSessionLifecycleTests {
    @Test @MainActor func temporaryCLITasksCompleteAndRecreateWithNativeWorkspaceAttached() async throws {
        _ = NSApplication.shared
        let root = testDirectory("temporary-ui-lifecycle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let service = ProjectTask(definition: TaskDefinition(name: "Saved service", command: "sleep 60"), pinned: true)
        try store.saveTask(service, projectID: projectID)
        defer { store.terminateAll() }

        let host = NSHostingView(rootView: WorkspaceView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Taskport lifecycle test"
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try store.startTask(service.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(service.id)?.phase == .running }
        let servicePID = try #require(store.session(service.id)?.shellPID)
        let control = WorkspaceControl(store: store)

        for iteration in 0..<30 {
            let exitCode = iteration.isMultiple(of: 3) ? 1 : 0
            let added = control.handle(.init(operation: "tasks.add", projectID: projectID,
                values: ["name": "Experiment", "command": "printf 'Experiment output\\n'; exit \(exitCode)",
                         "kind": "oneOff", "temporary": "true"]))
            #expect(added.ok)
            let taskID = try #require(added.taskID)
            #expect(control.handle(.init(operation: "tasks.start", projectID: projectID, taskIDs: [taskID])).ok)
            if iteration.isMultiple(of: 2) { try store.openTask(taskID, projectID: projectID) }
            host.layoutSubtreeIfNeeded()
            if exitCode == 0 {
                try await waitUntil { store.session(taskID) == nil }
            } else {
                try await waitUntil { store.session(taskID)?.phase == .exited(1) }
                #expect(control.handle(.init(operation: "tasks.stop", projectID: projectID, taskIDs: [taskID])).ok)
                try await waitUntil { store.session(taskID) == nil }
            }
            host.layoutSubtreeIfNeeded()
            #expect(store.selectedProject?.tasks.map(\.id) == [service.id])
            #expect(store.session(service.id)?.phase == .running)
            #expect(store.session(service.id)?.shellPID == servicePID)
        }
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }
}
