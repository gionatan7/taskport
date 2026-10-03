import Foundation
import Testing
@testable import Taskport

@MainActor struct TaskEditorTests {
    @Test func environmentRowsPreserveLiteralValues() throws {
        let environment = [
            "MULTILINE": "first\nSECOND=still part of the first value\n",
            "EMPTY": "",
            "SPACING": "  leading\r\ntrailing  ",
            "SYMBOLS": "a=b 'quoted' \"double quoted\" $literal"
        ]
        let rows = TaskEnvironmentEntry.rows(from: environment)
        #expect(rows.map(\.name) == environment.keys.sorted())
        #expect(try TaskEnvironmentEntry.environment(from: rows) == environment)
        #expect(try TaskEnvironmentEntry.environment(from: []) == [:])
    }

    @Test func environmentRowsRejectDuplicateNamesIncludingEmptyValues() throws {
        let rows = [TaskEnvironmentEntry(name: "EXAMPLE", value: ""),
                    TaskEnvironmentEntry(name: "EXAMPLE", value: "second")]
        #expect(throws: WorkspaceError.self) { try TaskEnvironmentEntry.environment(from: rows) }
    }

    @Test func environmentRowsUseTaskValidation() throws {
        for invalidName in ["", "1NAME", "WITH SPACE", "WITH=EQUALS", "WITH\nNEWLINE", "TRAILING\n", "NULL\0"] {
            let environment = try TaskEnvironmentEntry.environment(from: [.init(name: invalidName, value: "text")])
            let task = TaskDefinition(name: "Example", command: "true", environment: environment)
            #expect(throws: WorkspaceError.self) { try task.validated() }
        }
        let environment = try TaskEnvironmentEntry.environment(from: [.init(name: "EXAMPLE", value: "null\0value")])
        #expect(throws: WorkspaceError.self) {
            try TaskDefinition(name: "Example", command: "true", environment: environment).validated()
        }
    }

    @Test func normalEditorSavePreservesEnvironmentAndPersistsChanges() throws {
        let directory = testDirectory("editor-save")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: directory.path)
        let original = ProjectTask(definition: TaskDefinition(name: "Before", command: "true",
            environment: ["TEXT": "first\nOTHER=not another variable\n", "EMPTY": ""]))
        try store.saveTask(original, projectID: projectID, replacing: nil)
        var edited = original
        edited.definition.name = "After"
        edited.definition.environment = try TaskEnvironmentEntry.environment(from: TaskEnvironmentEntry.rows(from: original.definition.environment))
        try store.saveTask(edited, projectID: projectID, replacing: original)
        #expect(store.selectedProject?.tasks == [edited])
        #expect(try store.persistence.load().projects.first?.tasks == [edited])
        #expect(edited.definition.environment == original.definition.environment)
    }

    @Test func editorSaveRejectsConcurrentTaskChangesWithoutOverwritingThem() throws {
        let directory = testDirectory("editor-conflict")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: directory.path)
        let original = ProjectTask(definition: TaskDefinition(name: "Before", command: "true"))
        try store.saveTask(original, projectID: projectID)
        var edited = original
        edited.definition.name = "Unsaved editor name"
        var newer = original
        newer.definition.command = "printf 'new command'"
        newer.localURL = "http://localhost:4321"
        newer.pinned = true
        try store.saveTask(newer, projectID: projectID)
        #expect(throws: WorkspaceError.self) {
            try store.saveTask(edited, projectID: projectID, replacing: original)
        }
        #expect(store.selectedProject?.tasks == [newer])
        #expect(try store.persistence.load().projects.first?.tasks == [newer])
    }

    @Test func editorSaveNeverResurrectsRemovedTasks() throws {
        let directory = testDirectory("editor-task-removed")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: directory.path)
        let original = ProjectTask(definition: TaskDefinition(name: "Temporary", command: "true"), temporary: true)
        try store.saveTask(original, projectID: projectID)
        try store.closeTab(original.id, projectID: projectID)
        #expect(throws: WorkspaceError.self) {
            try store.saveTask(original, projectID: projectID, replacing: original)
        }
        #expect(store.selectedProject?.tasks.isEmpty == true)
        #expect(try store.persistence.load().projects.first?.tasks.isEmpty == true)
    }

    @Test func editorSaveRejectsMissingProjectsAndNewTaskCollisions() throws {
        let directory = testDirectory("editor-project-removed")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: directory.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Example", command: "true"))
        try store.saveTask(task, projectID: projectID)
        #expect(throws: WorkspaceError.self) {
            try store.saveTask(task, projectID: projectID, replacing: nil)
        }
        try store.removeProject(projectID)
        #expect(throws: WorkspaceError.self) {
            try store.saveTask(task, projectID: projectID, replacing: task)
        }
        #expect(throws: WorkspaceError.self) {
            try store.saveTask(task, projectID: projectID, replacing: nil)
        }
        #expect(store.document.projects.isEmpty)
        #expect(try store.persistence.load().projects.isEmpty)
    }
}
