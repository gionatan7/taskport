import Foundation
import Testing
import TaskportControl
@testable import Taskport

struct WorkspaceGroupTests {
    @Test @MainActor func bulkDisclosureIncludesDefaultGroupAndPreservesProjects() throws {
        let root = testDirectory("group-disclosure")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        #expect(!store.hasExpandedGroups)
        try store.setAllGroupsCollapsed(true)
        #expect(store.document.projectsGroupCollapsed == nil)
        let work = try store.saveGroup(name: "Work")
        let personal = try store.saveGroup(name: "Personal")
        _ = try store.addProject(name: "Example", directory: root.path, groupID: work)
        let projects = store.document.projects
        let selection = store.document.selectedProjectID
        try store.setGroupCollapsed(personal, true)
        #expect(store.hasExpandedGroups)
        try store.setAllGroupsCollapsed(true)
        #expect(store.document.groups.allSatisfy { $0.isCollapsed })
        #expect(store.document.projectsGroupCollapsed == true)
        #expect(!store.hasExpandedGroups)
        #expect(try store.persistence.load() == store.document)
        try store.setGroupCollapsed(nil, false)
        #expect(store.hasExpandedGroups) // The default Projects group counts, even when empty.
        try store.setAllGroupsCollapsed(false)
        #expect(store.document.groups.allSatisfy { !$0.isCollapsed })
        #expect(store.document.projectsGroupCollapsed == false)
        #expect(store.document.projects == projects)
        #expect(store.document.selectedProjectID == selection)
        #expect(try store.persistence.load() == store.document)
        let before = store.document
        store.blockWrites("Read only")
        #expect(throws: (any Error).self) { try store.setAllGroupsCollapsed(true) }
        #expect(store.document == before)
    }

    @Test @MainActor func groupOrderAndDefaultGroupDisclosurePersistWithoutChangingProjects() throws {
        let root = testDirectory("group-reordering")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let first = try store.saveGroup(name: "Work")
        let second = try store.saveGroup(name: "Personal")
        let third = try store.saveGroup(name: "Experiments")
        let project = try store.addProject(name: "Example", directory: root.path, groupID: first)
        let projects = store.document.projects
        try store.setGroupCollapsed(second, true)
        try store.moveGroup(third, relativeTo: first)
        #expect(store.document.groups.map(\.id) == [third, first, second])
        try store.moveGroup(third, relativeTo: first, after: true)
        #expect(store.document.groups.map(\.id) == [first, third, second])
        try store.moveGroup(first, relativeTo: nil)
        #expect(store.document.groups.map(\.id) == [third, second, first])
        try store.moveGroup(second, relativeTo: second)
        #expect(store.document.groups.map(\.id) == [third, second, first])
        #expect(store.document.groups.first(where: { $0.id == second })?.isCollapsed == true)
        #expect(store.document.projects == projects)
        #expect(store.document.selectedProjectID == project)
        #expect(throws: (any Error).self) { try store.moveGroup(UUID(), relativeTo: nil) }
        #expect(throws: (any Error).self) { try store.moveGroup(first, relativeTo: UUID()) }
        try store.setGroupCollapsed(nil, true)
        #expect(try store.persistence.load().projectsGroupCollapsed == true)
        try store.moveProject(project, toGroup: nil)
        #expect(store.document.projectsGroupCollapsed == false)
        #expect(store.selectedProject?.groupID == nil)
        #expect(try store.persistence.load() == store.document)
        store.blockWrites("Read only")
        #expect(throws: (any Error).self) { try store.moveGroup(first, relativeTo: second) }
    }

    @Test @MainActor func creatingGroupForProjectAssignsAtomicallyAndRejectsStaleProject() throws {
        let root = testDirectory("new-group-assignment")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "true"), pinned: true)
        try store.saveTask(task, projectID: projectID)
        let group = try store.saveGroup(name: "Work", assigning: projectID)
        #expect(store.selectedProject?.groupID == group)
        #expect(store.selectedProject?.tasks == [task])
        #expect(store.document.groups.first?.isCollapsed == false)
        #expect(try store.persistence.load() == store.document)
        let before = store.document
        #expect(throws: (any Error).self) { try store.saveGroup(name: "Orphan", assigning: UUID()) }
        #expect(throws: (any Error).self) { try store.saveGroup(name: "Work", assigning: projectID) }
        #expect(throws: (any Error).self) { try store.saveGroup(name: "projects", assigning: projectID) }
        #expect(store.document == before)
    }

    @Test @MainActor func groupsPersistAndRemovalKeepsProjectsAndTasks() throws {
        let root = testDirectory("groups")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let groupID = try store.saveGroup(name: "  Work  ")
        #expect(store.document.groups.first?.name == "Work")
        #expect(throws: (any Error).self) { try store.saveGroup(name: "work") }
        #expect(throws: (any Error).self) { try store.saveGroup(name: "  ") }
        try store.setGroupCollapsed(groupID, true)
        let original = try #require(store.document.groups.first)
        try store.saveGroup(name: "Studio", replacing: original)
        #expect(store.document.groups.first?.isCollapsed == true)
        let projectID = try store.addProject(name: "Example", directory: root.path, groupID: groupID)
        #expect(store.document.groups.first?.isCollapsed == false)
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "true"), pinned: true)
        try store.saveTask(task, projectID: projectID)
        try store.setGroupCollapsed(groupID, true)
        let saved = try store.persistence.load()
        #expect(saved.groups.first?.isCollapsed == true)
        #expect(saved.projects.first?.groupID == groupID)
        let snapshot = try #require(store.selectedProject)
        try store.removeGroup(groupID)
        #expect(store.document.groups.isEmpty)
        #expect(store.selectedProject?.id == snapshot.id)
        #expect(store.selectedProject?.tasks == snapshot.tasks)
        #expect(store.selectedProject?.groupID == nil)
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(store.sessions.isEmpty)
        #expect(try store.persistence.load() == store.document)
    }

    @Test @MainActor func assignmentAndReorderPreserveOtherGroupsAndSelection() throws {
        let root = testDirectory("group-order")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let group = try store.saveGroup(name: "Work")
        let first = try store.addProject(name: "First", directory: root.path, groupID: group)
        let middle = try store.addProject(name: "Ungrouped", directory: store.persistence.directory.path)
        let lastFolder = root.appendingPathComponent("last")
        try FileManager.default.createDirectory(at: lastFolder, withIntermediateDirectories: true)
        let last = try store.addProject(name: "Last", directory: lastFolder.path, groupID: group)
        store.moveProjects(inGroup: group, from: [1], to: 0)
        #expect(store.document.projects.map(\.id) == [last, middle, first])
        #expect(store.document.selectedProjectID == last)
        store.moveProjects(inGroup: group, from: [99], to: 0)
        #expect(store.document.projects.map(\.id) == [last, middle, first])
        try store.setGroupCollapsed(group, true)
        try store.moveProject(middle, toGroup: group)
        #expect(store.document.groups.first?.isCollapsed == false)
        #expect(store.document.projects.first { $0.id == middle }?.groupID == group)
        try store.moveProject(first, toGroup: nil)
        #expect(store.document.projects.first { $0.id == first }?.groupID == nil)
        #expect(throws: (any Error).self) { try store.moveProject(last, toGroup: UUID()) }
        #expect(try store.persistence.load() == store.document)
    }

    @Test @MainActor func staleEditorsAndInvalidGroupsCannotOverwriteSavedState() throws {
        let root = testDirectory("group-validation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let group = try store.saveGroup(name: "Work")
        let project = try store.addProject(name: "Example", directory: root.path)
        let original = try #require(store.selectedProject)
        try store.moveProject(project, toGroup: group)
        #expect(throws: (any Error).self) { try store.updateProject(original, replacing: original) }
        let oldGroup = try #require(store.document.groups.first)
        try store.removeGroup(group)
        #expect(throws: (any Error).self) { try store.saveGroup(name: "Revived", replacing: oldGroup) }
        #expect(throws: (any Error).self) { try store.addProject(name: "Invalid", directory: root.path, groupID: group) }
        store.blockWrites("Read only")
        #expect(throws: (any Error).self) { try store.saveGroup(name: "New") }
    }

    @Test @MainActor func v2MigrationPreservesDefinitionsAndPrivateBackup() throws {
        let root = testDirectory("v2-groups")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(name: "Example", directory: root.path,
            tasks: [ProjectTask(definition: TaskDefinition(name: "Web", command: "true"), pinned: true)])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceDocument(projects: [project]))) as? [String: Any])
        object["version"] = 2
        object.removeValue(forKey: "groups")
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let persistence = WorkspacePersistence(directory: root)
        try bytes.write(to: persistence.file)
        let migrated = try persistence.load()
        #expect(migrated.version == 3)
        #expect(migrated.groups.isEmpty)
        #expect(migrated.projects == [project])
        try persistence.save(migrated)
        let backup = root.appendingPathComponent("workspace-v2.json")
        #expect(try Data(contentsOf: backup) == bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int == 0o600)
        var invalid = migrated
        invalid.projects[0].groupID = UUID()
        try persistence.save(invalid)
        #expect(throws: (any Error).self) { try persistence.load() }
    }

    @Test @MainActor func cliManagesGroupsAndRemovesOnlyProjectDefinitions() throws {
        let root = testDirectory("group-cli")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let control = WorkspaceControl(store: store)
        let added = control.handle(try CLIArguments.parse(["groups", "add", "--name", "Work"]))
        let group = try #require(added.groupID)
        let created = control.handle(try CLIArguments.parse(["projects", "add", "--directory", root.path, "--group", group.uuidString]))
        let project = try #require(created.projectID)
        #expect(control.handle(.init(operation: "status")).projects?.first?.groupID == group)
        #expect(control.handle(.init(operation: "groups.list")).groups?.first?.projectCount == 1)
        #expect(control.handle(try CLIArguments.parse(["groups", "edit", group.uuidString, "--name", "Personal"])).ok)
        #expect(control.handle(try CLIArguments.parse(["projects", "edit", project.uuidString, "--group", "none"])).ok)
        #expect(store.selectedProject?.groupID == nil)
        #expect(control.handle(try CLIArguments.parse(["projects", "edit", project.uuidString, "--group", "bad"])).ok == false)
        #expect(control.handle(try CLIArguments.parse(["groups", "remove", group.uuidString])).ok)
        let task = ProjectTask(definition: TaskDefinition(name: "Web", command: "true"), pinned: true)
        try store.saveTask(task, projectID: project)
        let unrelated = UUID()
        try store.commit { $0.runningPinnedTaskIDs = [task.id, unrelated] }
        #expect(control.handle(try CLIArguments.parse(["projects", "remove", project.uuidString])).ok)
        #expect(store.document.projects.isEmpty)
        #expect(store.document.runningPinnedTaskIDs == [unrelated])
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(control.handle(.init(operation: "projects.remove", projectID: project)).ok == false)
        #expect(throws: (any Error).self) { try CLIArguments.parse(["projects", "remove", project.uuidString, UUID().uuidString]) }
        #expect(throws: (any Error).self) { try CLIArguments.parse(["groups", "remove", group.uuidString, "extra"]) }
    }

    @Test @MainActor func deletionRefusesBusyTerminalsAndGroupingDoesNotStopThem() async throws {
        let root = testDirectory("group-busy")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let project = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Service", command: "sleep 30"), pinned: true)
        try store.saveTask(task, projectID: project)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: project, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        let session = try #require(store.session(task.id))
        let group = try store.saveGroup(name: "Work", assigning: project)
        #expect(store.selectedProject?.groupID == group)
        try store.moveProject(project, toGroup: nil)
        try store.moveProject(project, toGroup: group)
        try store.removeGroup(group)
        #expect(store.session(task.id) === session)
        #expect(session.phase == .running)
        #expect(WorkspaceControl(store: store).handle(.init(operation: "projects.remove", projectID: project)).ok == false)
        #expect(store.document.projects.count == 1)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
        try store.removeProject(project)
        #expect(store.document.projects.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
