import Foundation
import Testing
@testable import Taskport

struct ResumeTests {
    @Test @MainActor func resumeSettingPersistsWithoutStoppingCurrentTasks() async throws {
        let directory = testDirectory("resume-setting")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        #expect(store.resumeTasksOnLaunch)
        let projectID = try store.addProject(name: "Example", directory: directory.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Pinned", command: "sleep 60"), pinned: true)
        try store.saveTask(task, projectID: projectID)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        try store.setResumeTasksOnLaunch(false)
        #expect(store.session(task.id)?.phase == .running)
        #expect(store.document.runningPinnedTaskIDs == [])
        #expect(try store.persistence.load().resumeTasksOnLaunch == false)
        try store.setResumeTasksOnLaunch(true)
        #expect(store.document.runningPinnedTaskIDs == [task.id])
        try store.setResumeTasksOnLaunch(false)
        store.prepareToQuit()
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        let relaunched = WorkspaceStore(directory: store.persistence.directory)
        relaunched.resumePinnedTasks()
        #expect(!relaunched.resumeTasksOnLaunch)
        #expect(relaunched.sessions.isEmpty)
        try relaunched.setResumeTasksOnLaunch(true)
        #expect(relaunched.sessions.isEmpty)
        #expect(try relaunched.persistence.load().resumeTasksOnLaunch == true)
    }

    @Test @MainActor func disabledResumeClearsStaleIDsAndStillRemovesTemporaryTasks() throws {
        let directory = testDirectory("resume-disabled")
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = ProjectTask(definition: TaskDefinition(name: "Saved", command: "true"), pinned: true)
        let temporary = ProjectTask(definition: TaskDefinition(name: "Temporary", command: "true"), temporary: true)
        let project = Project(name: "Example", directory: directory.path, tasks: [task, temporary], selectedTaskID: temporary.id)
        let persistence = WorkspacePersistence(directory: directory)
        try persistence.save(WorkspaceDocument(projects: [project], selectedProjectID: project.id,
            runningPinnedTaskIDs: [task.id], resumeTasksOnLaunch: false))
        let store = WorkspaceStore(directory: directory)
        store.resumePinnedTasks()
        #expect(store.sessions.isEmpty)
        #expect(store.document.runningPinnedTaskIDs == [])
        #expect(store.selectedProject?.tasks == [task])
        #expect(store.selectedTaskID == task.id)
    }

    @Test @MainActor func resumesOnlyRunningPinnedTasksAndExplicitStopClearsResume() async throws {
        let directory = testDirectory("resume")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Resume", directory: directory.path)
        let pinned = ProjectTask(definition: TaskDefinition(name: "Pinned", command: "sleep 60"), pinned: true)
        let idle = ProjectTask(definition: TaskDefinition(name: "Idle", command: "sleep 60"), pinned: true)
        let once = ProjectTask(definition: TaskDefinition(name: "Once", command: "sleep 60", kind: .oneOff))
        let tunnel = ProjectTask(definition: TaskDefinition(name: "Tunnel", command: "sleep 60"), sourceKey: "builtin:cloudflare")
        for task in [pinned, idle, once, tunnel] { try store.saveTask(task, projectID: projectID) }
        defer { store.terminateAll() }
        for task in [pinned, once, tunnel] { try store.startTask(task.id, projectID: projectID, activate: false) }
        try await waitUntil { [pinned, once, tunnel].allSatisfy { store.session($0.id)?.phase == .running } }
        #expect(store.document.runningPinnedTaskIDs == [pinned.id])
        // Pin/unpin changes update the resume set without changing the task command.
        try store.togglePin(pinned, projectID: projectID)
        #expect(store.document.runningPinnedTaskIDs == [])
        try store.saveTask(pinned, projectID: projectID)
        #expect(store.document.runningPinnedTaskIDs == [pinned.id])
        store.prepareToQuit()
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        #expect(try store.persistence.load().runningPinnedTaskIDs == [pinned.id])

        let relaunched = WorkspaceStore(directory: store.persistence.directory)
        defer { relaunched.terminateAll() }
        relaunched.resumePinnedTasks()
        try await waitUntil { relaunched.session(pinned.id)?.phase == .running }
        #expect(relaunched.sessions.map(\.id) == [pinned.id])
        relaunched.stopAll(in: try #require(relaunched.selectedProject))
        #expect(try relaunched.persistence.load().runningPinnedTaskIDs == [])
        relaunched.terminateAll()
        try await waitUntil { relaunched.openShellCount == 0 }
        let stopped = WorkspaceStore(directory: store.persistence.directory)
        stopped.resumePinnedTasks()
        #expect(stopped.sessions.isEmpty)
    }
}
