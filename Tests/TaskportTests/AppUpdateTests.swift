import AppKit
import Foundation
import TaskportControl
import Testing
@testable import Taskport

struct AppUpdateTests {
    @Test @MainActor func decliningInstallationNeverStopsTasksOrSavesAHandoff() async throws {
        let root = testDirectory("update-declined")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let project = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), temporary: true)
        try store.saveTask(task, projectID: project)
        try store.startTask(task.id, projectID: project, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        var sawSummary = false
        let updates = AppUpdates(store: store, defaults: MemoryUpdateDefaults()) { summary in
            #expect(summary.taskIDs == [task.id])
            #expect(summary.version == "0.0.2")
            sawSummary = true
            return nil
        }
        #expect(!updates.authorizeInstallation(.init(build: "2", version: "0.0.2")))
        #expect(updates.installation == nil)
        #expect(sawSummary)
        #expect(store.session(task.id)?.phase == .running)
        #expect(!store.shutdownInProgress)
        #expect(throws: (any Error).self) { try SessionHandoff.load(in: store.persistence.directory) }
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func approvedUpdatePreservesTemporaryServiceAndOverridesResumeSettingOnce() async throws {
        let root = testDirectory("update-approved")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let project = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Experiment", command: "sleep 60"), temporary: true)
        try store.saveTask(task, projectID: project)
        try store.setResumeTasksOnLaunch(false)
        try store.startTask(task.id, projectID: project, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        let oldPID = store.session(task.id)?.shellPID
        let updates = AppUpdates(store: store, defaults: MemoryUpdateDefaults()) { _ in UpdateRestartApproval() }
        var approvedExit = false
        #expect(updates.authorizeInstallation(.init(build: "2", version: "0.0.2")))
        #expect(store.session(task.id)?.phase == .running)
        #expect(updates.prepareTermination(for: .init(build: "2", version: "0.0.2")) { approvedExit = $0 } == .terminateLater)
        try await waitUntil { approvedExit }
        #expect(store.openShellCount == 0)
        let handoff = try SessionHandoff.load(in: store.persistence.directory)
        #expect(handoff.updateBuild == "2")
        #expect(handoff.entries.map(\.taskID) == [task.id])
        let relaunched = WorkspaceStore(directory: store.persistence.directory)
        defer { relaunched.terminateAll() }
        relaunched.resumePinnedTasks(restoring: handoff.id)
        try await waitUntil { !relaunched.restoreInProgress }
        #expect(relaunched.session(task.id)?.phase == .running)
        #expect(relaunched.session(task.id)?.shellPID != oldPID)
        #expect(!relaunched.resumeTasksOnLaunch)
        #expect(throws: (any Error).self) { try SessionHandoff.load(in: store.persistence.directory) }
        relaunched.terminateAll()
        try await waitUntil { relaunched.openShellCount == 0 }
    }

    @Test @MainActor func oneOffWithoutOptInBlocksBeforeAnyInterruption() async throws {
        let root = testDirectory("update-one-off")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let project = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Build", command: "sleep 60", kind: .oneOff))
        try store.saveTask(task, projectID: project)
        try store.startTask(task.id, projectID: project, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        let updates = AppUpdates(store: store, defaults: MemoryUpdateDefaults()) { summary in
            #expect(summary.oneOffCount == 1)
            return UpdateRestartApproval()
        }
        #expect(!updates.authorizeInstallation(.init(build: "2", version: "0.0.2")))
        #expect(updates.installation == nil)
        #expect(!store.shutdownInProgress)
        #expect(store.session(task.id)?.phase == .running)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func shutdownTimeoutRetainsApprovalAndOriginalSnapshotForRetry() async throws {
        let root = testDirectory("update-shutdown-retry")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        defer { store.terminateAll() }
        let project = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Experiment", command: "sleep 60"), temporary: true)
        try store.saveTask(task, projectID: project)
        try store.startTask(task.id, projectID: project, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        let defaults = MemoryUpdateDefaults()
        var approvalCount = 0
        let updates = AppUpdates(store: store, defaults: defaults) { _ in
            approvalCount += 1
            return UpdateRestartApproval()
        }
        let update = PendingAppUpdate(build: "2", version: "0.0.2")
        #expect(updates.authorizeInstallation(update))
        let saved = try SessionHandoff.load(in: store.persistence.directory)
        var firstReply: Bool?
        #expect(updates.prepareTermination(for: update, timeout: .zero) { firstReply = $0 } == .terminateLater)
        try await waitUntil { firstReply != nil }
        #expect(firstReply == false)
        #expect(updates.installation == update)
        #expect(!updates.isPreparingInstallation)
        #expect(store.shutdownInProgress && store.preservingResumeState)
        #expect(try SessionHandoff.load(in: store.persistence.directory).id == saved.id)
        #expect(throws: (any Error).self) { try store.setResumeTasksOnLaunch(false) }
        try await waitUntil { store.openShellCount == 0 }
        #expect(store.selectedProject?.tasks.contains { $0.id == task.id } == true)
        var retryReply: Bool?
        #expect(updates.prepareTermination(for: update) { retryReply = $0 } == .terminateLater)
        try await waitUntil { retryReply != nil }
        #expect(retryReply == true)
        #expect(approvalCount == 1)
        let retried = try SessionHandoff.load(in: store.persistence.directory)
        #expect(retried.id == saved.id)
        #expect(retried.entries.map(\.taskID) == [task.id])
        #expect(defaults.data(forKey: "TaskportUpdateWorkspace") != nil)
    }

    @Test @MainActor func failedWorkspaceSaveStillClearsConsumedUpdateLocator() throws {
        let root = testDirectory("update-restore-save-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), pinned: true)
        let project = Project(name: "Example", directory: root.path, tasks: [task])
        let persistence = WorkspacePersistence(directory: root)
        try persistence.save(WorkspaceDocument(projects: [project], runningPinnedTaskIDs: [task.id]))
        let defaults = MemoryUpdateDefaults()
        let saved = SessionHandoff(id: UUID(), sourceProcessID: getpid(),
            entries: [.init(projectID: project.id, taskID: task.id, fingerprint: try project.restoreFingerprint(for: task))],
            openTaskIDs: [task.id], updateBuild: "2")
        try saved.save(in: root)
        try UpdateWorkspace.save(directory: root, handoffID: saved.id, defaults: defaults)
        let store = WorkspaceStore(directory: root)
        let backup = root.appendingPathComponent("workspace-before-restore.json")
        try FileManager.default.moveItem(at: persistence.file, to: backup)
        try FileManager.default.createDirectory(at: persistence.file, withIntermediateDirectories: false)
        store.restoreSession(saved.id, updateDefaults: defaults)
        #expect(store.restoreError != nil)
        #expect(store.sessions.isEmpty)
        #expect(!store.shutdownInProgress)
        #expect(defaults.data(forKey: "TaskportUpdateWorkspace") == nil)
        #expect(throws: (any Error).self) { try SessionHandoff.load(in: root) }
    }

    @Test @MainActor func crashAfterConsumptionReopensSameWorkspaceWithoutAutomaticReplay() throws {
        let root = testDirectory("update-consumed-locator")
        defer { try? FileManager.default.removeItem(at: root) }
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 60"), pinned: true)
        let project = Project(name: "Example", directory: root.path, tasks: [task])
        try WorkspacePersistence(directory: root).save(WorkspaceDocument(projects: [project], runningPinnedTaskIDs: [task.id]))
        let defaults = MemoryUpdateDefaults()
        let saved = SessionHandoff(id: UUID(), sourceProcessID: getpid(), entries: [], openTaskIDs: [], updateBuild: "2")
        try saved.save(in: root)
        try UpdateWorkspace.save(directory: root, handoffID: saved.id, defaults: defaults)
        _ = try SessionHandoff.consume(saved.id, in: root) // Crash before preference cleanup.
        let launch = try UpdateWorkspace.resolveLaunch(fallback: root.appendingPathComponent("other-workspace"),
            explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults)
        #expect(launch.directory.path == root.standardizedFileURL.path)
        #expect(launch.handoffID == saved.id)
        let store = WorkspaceStore(directory: launch.directory)
        store.restoreSession(try #require(launch.handoffID), updateDefaults: defaults)
        #expect(store.resumeTasksOnLaunch)
        #expect(store.restoreError != nil)
        #expect(!store.isReadOnly)
        #expect(store.sessions.isEmpty)
        #expect(defaults.data(forKey: "TaskportUpdateWorkspace") == nil)
    }

    @Test func consumedLocatorRecoveryStillRejectsSymlinksAndNonPrivateDirectories() throws {
        let root = testDirectory("update-locator-guards")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = MemoryUpdateDefaults()
        let saved = SessionHandoff(id: UUID(), sourceProcessID: getpid(), entries: [], openTaskIDs: [], updateBuild: "2")
        try saved.save(in: root)
        try UpdateWorkspace.save(directory: root, handoffID: saved.id, defaults: defaults)
        _ = try SessionHandoff.consume(saved.id, in: root)
        let checkpoint = root.appendingPathComponent("session-restore.json")
        try FileManager.default.createSymbolicLink(at: checkpoint, withDestinationURL: root.appendingPathComponent("missing"))
        #expect(throws: (any Error).self) { try UpdateWorkspace.resolveLaunch(fallback: root, explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults) }
        UpdateWorkspace.discardConsumed(handoffID: saved.id, in: root, defaults: defaults)
        #expect(defaults.data(forKey: "TaskportUpdateWorkspace") != nil)
        try FileManager.default.removeItem(at: checkpoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        #expect(throws: (any Error).self) { try UpdateWorkspace.resolveLaunch(fallback: root, explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try SessionHandoff(id: UUID(), sourceProcessID: getpid(), entries: [], openTaskIDs: [], updateBuild: "2").save(in: root)
        #expect(throws: (any Error).self) { try UpdateWorkspace.resolveLaunch(fallback: root, explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults) }
    }

    @Test func implicitRestoreRequiresTheApprovedBuildAndAnExitedSourceProcess() throws {
        let root = testDirectory("update-relaunch-intent")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try SessionHandoff.restoreAfterUpdate(in: root, build: "2", processID: getpid()) == nil)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run(); child.waitUntilExit()
        let saved = SessionHandoff(id: UUID(), sourceProcessID: child.processIdentifier, entries: [], openTaskIDs: [], updateBuild: "2")
        try saved.save(in: root)
        #expect(throws: (any Error).self) { try SessionHandoff.restoreAfterUpdate(in: root, build: "1", processID: getpid()) }
        #expect(try SessionHandoff.restoreAfterUpdate(in: root, build: "2", processID: getpid()) == saved.id)
        try SessionHandoff(id: UUID(), sourceProcessID: getpid(), entries: [], openTaskIDs: [], updateBuild: "2").save(in: root)
        #expect(throws: (any Error).self) { try SessionHandoff.restoreAfterUpdate(in: root, build: "2", processID: getpid()) }
        try SessionHandoff(id: UUID(), sourceProcessID: child.processIdentifier, entries: [], openTaskIDs: []).save(in: root)
        #expect(try SessionHandoff.restoreAfterUpdate(in: root, build: "2", processID: getpid()) == nil)
        try SessionHandoff(id: UUID(), sourceProcessID: child.processIdentifier, entries: [], openTaskIDs: [], createdAt: Date().addingTimeInterval(-90_000)).save(in: root)
        #expect(try SessionHandoff.restoreAfterUpdate(in: root, build: "2", processID: getpid()) == nil)
        try SessionHandoff(id: UUID(), sourceProcessID: child.processIdentifier, entries: [], openTaskIDs: [], createdAt: Date().addingTimeInterval(-90_000), updateBuild: "2").save(in: root)
        #expect(throws: (any Error).self) { try SessionHandoff.restoreAfterUpdate(in: root, build: "2", processID: getpid()) }
    }

    @Test func customWorkspaceSurvivesRelaunchWithoutEnvironmentAndCannotRedirectAnExplicitWorkspace() throws {
        let root = testDirectory("update-custom-workspace")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run(); child.waitUntilExit()
        let defaults = MemoryUpdateDefaults()
        let fallback = root.appendingPathComponent("other-workspace")
        let saved = SessionHandoff(id: UUID(), sourceProcessID: child.processIdentifier, entries: [], openTaskIDs: [], updateBuild: "2")
        try saved.save(in: root)
        try UpdateWorkspace.save(directory: root, handoffID: saved.id, defaults: defaults)
        #expect(try UpdateWorkspace.resolveLaunch(fallback: fallback, explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults).directory.path == root.standardizedFileURL.path)
        #expect(try UpdateWorkspace.resolveLaunch(fallback: root, explicitDirectory: root.path, build: "2", processID: getpid(), defaults: defaults).directory.path == root.standardizedFileURL.path)
        #expect(throws: (any Error).self) { try UpdateWorkspace.resolveLaunch(fallback: fallback, explicitDirectory: fallback.path, build: "2", processID: getpid(), defaults: defaults) }
        #expect(throws: (any Error).self) { try UpdateWorkspace.resolveLaunch(fallback: fallback, explicitDirectory: nil, build: "1", processID: getpid(), defaults: defaults) }
        UpdateWorkspace.discard(handoffID: UUID(), defaults: defaults)
        #expect(try UpdateWorkspace.resolveLaunch(fallback: fallback, explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults).directory.path == root.standardizedFileURL.path)
        _ = try SessionHandoff.consume(saved.id, in: root)
        UpdateWorkspace.discard(handoffID: saved.id, defaults: defaults)
        #expect(try UpdateWorkspace.resolveLaunch(fallback: fallback, explicitDirectory: nil, build: "2", processID: getpid(), defaults: defaults).directory == fallback)
    }
}

/// Unit tests never write the real app's preferences or launch locator.
private final class MemoryUpdateDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Data] = [:]
    override func data(forKey defaultName: String) -> Data? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value as? Data }
    override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    override func synchronize() -> Bool { true }
}
