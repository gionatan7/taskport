import Foundation
import Testing
@testable import Taskport

struct WorkspaceActionsTests {
    @Test @MainActor func reorderPersistsWithoutChangingSelection() throws {
        let directory = testDirectory("reorder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let first = try store.addProject(name: "First", directory: directory.path)
        let second = try store.addProject(name: "Second", directory: store.persistence.directory.path)
        store.moveProjects(from: [1], to: 0)
        #expect(store.document.projects.map(\.id) == [second, first])
        #expect(store.document.selectedProjectID == second)
        #expect(try store.persistence.load() == store.document)
        store.moveProjects(from: [0], to: 2)
        #expect(store.document.projects.map(\.id) == [first, second])
    }

    @Test @MainActor func closeTabsPreservesDefinitionsAndRepairsSplit() throws {
        let directory = testDirectory("close-tabs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: directory.path)
        let first = ProjectTask(definition: TaskDefinition(name: "First", command: "true", kind: .oneOff))
        let second = ProjectTask(definition: TaskDefinition(name: "Second", command: "true", kind: .oneOff))
        try store.saveTask(first, projectID: id)
        try store.saveTask(second, projectID: id)
        try store.setSplit(projectID: id, taskID: second.id)
        try store.closeTab(first.id, projectID: id)
        #expect(store.selectedTaskID == second.id)
        #expect(store.selectedProject?.split == nil)
        try store.closeTab(second.id, projectID: id)
        #expect(store.selectedTaskID == nil)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).isEmpty)
        #expect(try store.persistence.load().projects.first?.tasks.count == 2)
        try store.openTask(first.id, projectID: id)
        try store.openTask(second.id, projectID: id)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).count == 2)
        try store.togglePin(first, projectID: id)
        #expect(throws: (any Error).self) { try store.closeTab(first.id, projectID: id) }
    }

    @Test @MainActor func stopAllIsProjectScopedAndBusyCloseRequiresConfirmation() async throws {
        let directory = testDirectory("project-stop")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let first = try store.addProject(name: "First", directory: directory.path)
        let second = try store.addProject(name: "Second", directory: store.persistence.directory.path)
        let once = ProjectTask(definition: TaskDefinition(name: "Unpinned", command: "sleep 30", kind: .oneOff))
        let other = ProjectTask(definition: TaskDefinition(name: "Other", command: "sleep 30"), pinned: true)
        try store.saveTask(once, projectID: first)
        try store.saveTask(other, projectID: second)
        defer { store.terminateAll() }
        try store.startTask(once.id, projectID: first, activate: false)
        try store.startTask(other.id, projectID: second, activate: false)
        let project = try #require(store.document.projects.first { $0.id == first })
        #expect(store.hasRunningTasks(in: project))
        #expect(throws: (any Error).self) { try store.closeTab(once.id, projectID: first) }
        store.stopAll(in: project)
        #expect(store.session(once.id)?.phase == .stopping)
        #expect(store.session(other.id)?.phase == .starting)
        try store.closeTab(once.id, projectID: first, confirmed: true)
        #expect(store.visibleTasks(in: try #require(store.document.projects.first { $0.id == first })).isEmpty)
        #expect(throws: (any Error).self) { try store.startTask(once.id, projectID: first) }
        try await waitUntil { store.session(once.id) == nil }
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        #expect(!store.hasRunningTasks(in: project))
    }
}
