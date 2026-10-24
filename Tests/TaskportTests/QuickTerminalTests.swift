import AppKit
import SwiftUI
import TaskportControl
import Testing
@testable import Taskport

struct QuickTerminalTests {
    @Test @MainActor func quickShellsAreProjectScopedAndNeverBecomeSavedTasks() async throws {
        let root = testDirectory("quick-terminal")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let first = try store.openQuickTerminal(projectID: projectID)
        let second = try store.openQuickTerminal(projectID: projectID)
        let terminal = try #require(store.session(first))
        try await waitUntil { terminal.shellReady && store.session(second)?.shellReady == true }
        #expect(store.selectedTaskID == second)
        #expect(terminal.quickTerminalName == "Terminal")
        #expect(store.session(second)?.quickTerminalName == "Terminal 2")
        #expect(store.selectedProject?.tasks.isEmpty == true)
        #expect(try store.persistence.load().projects.first?.selectedTaskID == nil)
        #expect(store.status(of: try #require(store.selectedProject)) == .stopped)
        try store.selectQuickTerminal(first, projectID: projectID)
        store.selectProject(projectID)
        #expect(store.selectedTaskID == first)
        guard case .inMemory(let memory) = terminal.terminal.configuration.backend else { Issue.record("Expected in-memory terminal"); return }
        memory.sendInput(Data("printf 'quick-terminal-marker\\n'; pwd\r".utf8))
        try await waitUntil { terminal.shellReady && terminal.output.tail(lines: 30).text.contains("quick-terminal-marker") }
        let control = WorkspaceControl(store: store)
        let logs = control.handle(.init(operation: "tasks.logs", projectID: projectID, taskIDs: [first]))
        #expect(logs.ok && logs.output?.contains(root.path) == true)
        let sessions = try #require(control.handle(.init(operation: "sessions.list", flags: ["all"])).tasks)
        #expect(Set(sessions.map(\.id)) == [first, second])
        #expect(sessions.allSatisfy { $0.kind == "terminal" && $0.command.isEmpty && !$0.pinned })
        #expect(control.handle(.init(operation: "tasks.list", projectID: projectID)).tasks?.isEmpty == true)
        let saved = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), pinned: true)
        try store.saveTask(saved, projectID: projectID)
        try store.openTask(saved.id, projectID: projectID)
        #expect(store.selectedTaskID == saved.id)
        #expect(terminal.shellPID > 0)
        try store.selectQuickTerminal(first, projectID: projectID)
        try store.closeTab(first, projectID: projectID)
        try await waitUntil { store.session(first) == nil }
        #expect(store.selectedTaskID == second)
        try store.closeTab(second, projectID: projectID)
        try await waitUntil { store.openShellCount == 0 }
        #expect(store.selectedTaskID == saved.id)
        #expect(try store.persistence.load().projects.first?.tasks == [saved])
    }

    @Test @MainActor func manualWorkRequiresConfirmationAndIdleShellsAreNotReplayed() async throws {
        let root = testDirectory("quick-terminal-restore")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let id = try store.openQuickTerminal(projectID: projectID)
        let terminal = try #require(store.session(id))
        try await waitUntil { terminal.shellReady }
        guard case .inMemory(let memory) = terminal.terminal.configuration.backend else { Issue.record("Expected in-memory terminal"); return }
        memory.sendInput(Data("sleep 60\r".utf8))
        try await waitUntil { terminal.manualCommandRunning }
        #expect(store.activeCount == 1)
        #expect(store.status(of: try #require(store.selectedProject)) == .stopped)
        #expect(WorkspaceControl(store: store).handle(.init(operation: "sessions.list")).tasks?.first?.id == id)
        #expect(throws: (any Error).self) { try store.closeTab(id, projectID: projectID) }
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false) }
        memory.sendInput(Data([3]))
        try await waitUntil { !terminal.manualCommandRunning && terminal.shellReady }
        memory.sendInput(Data("unfinished".utf8))
        try await waitUntil { terminal.hasPendingInput }
        #expect(throws: (any Error).self) { try store.closeTab(id, projectID: projectID) }
        #expect(throws: (any Error).self) { try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false) }
        memory.sendInput(Data([3]))
        try await waitUntil { !terminal.hasPendingInput }
        let handoff = try store.saveSessionHandoff(id: UUID(), includeOneOffs: false, includeTunnels: false)
        #expect(handoff.entries.isEmpty && !handoff.openTaskIDs.contains(id))
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        let restored = WorkspaceStore(directory: store.persistence.directory)
        restored.resumePinnedTasks(restoring: handoff.id)
        try await waitUntil { !restored.restoreInProgress }
        #expect(restored.restoreError == nil && restored.sessions.isEmpty)
        #expect(restored.document.projects.first?.tasks.isEmpty == true)
    }

    @Test @MainActor func quickTerminalMountsWithoutTasksAndSidebarUsesNativeOverlayScrolling() async throws {
        _ = NSApplication.shared
        let root = testDirectory("quick-terminal-native")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let project = try store.addProject(name: "Example", directory: root.path)
        let id = try store.openQuickTerminal(projectID: project)
        let terminal = try #require(store.session(id))
        let controller = NSHostingController(rootView: WorkspaceView(store: store))
        let host = controller.view
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.contentViewController = nil; window.close() }
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await waitUntil { terminal.shellReady && terminal.terminal.attachedPlatformView != nil }
        host.layoutSubtreeIfNeeded()
        var sidebar: NSScrollView?
        try await waitUntil {
            var pending: [NSView] = [host], lists: [NSScrollView] = [], panes: [TaskSplitView] = []
            while let view = pending.popLast() {
                if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { lists.append(scroll); sidebar = scroll }
                if let split = view as? TaskSplitView { panes.append(split) }
                pending.append(contentsOf: view.subviews)
            }
            return !lists.isEmpty && lists.allSatisfy { $0.scrollerStyle == .overlay }
                && panes.contains { $0.arrangedSubviews.count == 1 }
        }
        let scroll = try #require(sidebar)
        scroll.scrollerStyle = .legacy // SwiftUI can reapply the system style after its own layout.
        try await waitUntil { scroll.scrollerStyle == .overlay }
        #expect(store.selectedProject?.tasks.isEmpty == true)
        try store.closeTab(id, projectID: project)
        try await waitUntil { store.openShellCount == 0 }
    }
}
