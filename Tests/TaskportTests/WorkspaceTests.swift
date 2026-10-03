import Foundation
import Testing
@testable import Taskport

struct WorkspaceTests {
    @Test @MainActor func unchangedSelectionDoesNotReplaceTheSavedFile() throws {
        let root = testDirectory("no-op-save")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Saved", command: "true"))
        try store.saveTask(task, projectID: projectID)
        var inode = try FileManager.default.attributesOfItem(atPath: store.persistence.file.path)[.systemFileNumber] as? NSNumber
        var replacements = 0
        for _ in 0..<10 {
            try store.openTask(task.id, projectID: projectID)
            let next = try FileManager.default.attributesOfItem(atPath: store.persistence.file.path)[.systemFileNumber] as? NSNumber
            if inode != next { replacements += 1 }
            inode = next
        }
        print("PERFORMANCE workspace replacements: \(replacements) for 10 unchanged task selections")
        #expect(replacements == 0)
        #expect(store.sessions.isEmpty)
        var changed = try #require(store.selectedProject)
        changed.name = "Changed"
        try store.updateProject(changed)
        let updated = try FileManager.default.attributesOfItem(atPath: store.persistence.file.path)[.systemFileNumber] as? NSNumber
        #expect(updated != inode)
        #expect(try store.persistence.load() == store.document)
    }

    @Test func pinnedStatusExcludesOneOffs() {
        let service = ProjectTask(definition: TaskDefinition(name: "Web", command: "sleep 10"), pinned: true)
        let other = ProjectTask(definition: TaskDefinition(name: "API", command: "sleep 10"), pinned: true)
        let once = ProjectTask(definition: TaskDefinition(name: "Check", command: "true", kind: .oneOff), pinned: true)
        let tunnel = ProjectTask(definition: TaskDefinition(name: "Tunnel", command: "true"), pinned: true, sourceKey: "builtin:cloudflare")
        #expect(!tunnel.participatesInStatus)
        #expect(ProjectStatus.compute(tasks: [service, other, once], running: [once.id]) == .stopped)
        #expect(ProjectStatus.compute(tasks: [service, other, once], running: [service.id, once.id]) == .partial)
        #expect(ProjectStatus.compute(tasks: [service, other, once], running: [service.id, other.id]) == .running)
    }

    @Test func pinningDoesNotCreateOverride() {
        let definition = TaskDefinition(name: "Web", command: "bun run dev")
        var task = ProjectTask(definition: definition, importedDefinition: definition)
        task.pinned = true
        #expect(!task.isOverridden)
        task.definition.command = "bun run preview"
        #expect(task.isOverridden)
        task.definition = definition
        #expect(!task.isOverridden)
    }

    @Test @MainActor func importedTasksCanBePinnedWithoutAnOverride() throws {
        let directory = testDirectory("pin-import")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: directory.path)
        let definition = TaskDefinition(name: "Watch", command: "true", kind: .oneOff)
        let task = ProjectTask(definition: definition, importedDefinition: definition)
        try store.importTasks([task], projectID: id)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).isEmpty)
        try store.togglePin(task, projectID: id)
        let project = try #require(store.selectedProject)
        let pinned = try #require(project.tasks.first)
        #expect(pinned.participatesInStatus)
        #expect(!pinned.isOverridden)
        #expect(pinned.importedDefinition == definition)
        #expect(store.visibleTasks(in: project).count == 1)
        #expect(store.sessions.isEmpty)
        #expect(try store.persistence.load().projects.first?.tasks.first == pinned)
    }

    @Test func localAddressValidation() throws {
        #expect(try LocalAddress.validate("http://localhost:3000") == "http://localhost:3000")
        #expect(throws: (any Error).self) { try LocalAddress.validate("javascript:alert(1)") }
        #expect(throws: (any Error).self) { try LocalAddress.validate("https://example.test/path") }
    }

    @Test func persistenceRoundTripAndCorruptionPreservation() throws {
        let directory = testDirectory("persistence")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WorkspacePersistence(directory: directory)
        var document = WorkspaceDocument()
        document.projects.append(Project(name: "Example", directory: "/example/projects/web-app"))
        try persistence.save(document)
        #expect(try persistence.load() == document)
        let permissions = try FileManager.default.attributesOfItem(atPath: persistence.file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try Data("broken".utf8).write(to: persistence.file)
        #expect(throws: (any Error).self) { try persistence.load() }
        #expect(try String(contentsOf: persistence.file, encoding: .utf8) == "broken")
    }
}

func testDirectory(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/test-\(name)-\(UUID().uuidString)")
}
