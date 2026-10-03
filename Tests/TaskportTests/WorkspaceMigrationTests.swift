import Foundation
import Testing
@testable import Taskport

struct WorkspaceMigrationTests {
    @Test @MainActor func unchangedStartupStillPersistsMigrationAndPrivateBackup() throws {
        let root = testDirectory("migration-startup")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var legacy = WorkspaceDocument(runningPinnedTaskIDs: [])
        legacy.version = 1
        let bytes = try JSONEncoder().encode(legacy)
        let persistence = WorkspacePersistence(directory: root)
        try bytes.write(to: persistence.file)
        let store = WorkspaceStore(directory: root)
        let before = store.document
        store.resumePinnedTasks()
        #expect(store.document == before)
        #expect(try Data(contentsOf: root.appendingPathComponent("workspace-v1.json")) == bytes)
        let saved = try JSONDecoder().decode(WorkspaceDocument.self, from: Data(contentsOf: persistence.file))
        #expect(saved.version == 2)
        #expect(saved == store.document)
    }

    @Test func migratesURLsAndKeepsPrivateBackup() throws {
        let watch = ProjectTask(definition: TaskDefinition(name: "Watch", command: "npm run watch"), pinned: true)
        let jar = ProjectTask(definition: TaskDefinition(name: "Launch JAR", command: "bash ./script/launch.sh"), pinned: true)
        let tunnel = ProjectTask(definition: TaskDefinition(name: "Tunnel", command: "cloudflared tunnel"), sourceKey: "builtin:cloudflare")
        let data = try legacyData([watch, jar, tunnel], address: "https://example.local:2443")
        let result = try WorkspaceMigration.decode(data)
        #expect(result.version == 2)
        #expect(result.projects[0].linkedTasks.map(\.id) == [jar.id])
        #expect(result.projects[0].tasks[2].tunnelForTaskID == jar.id)
        #expect(result.projects[0].tasks[2].temporary)
        let root = testDirectory("migration")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = WorkspacePersistence(directory: root)
        try data.write(to: persistence.file)
        try persistence.save(result)
        let backup = root.appendingPathComponent("workspace-v1.json")
        #expect(try Data(contentsOf: backup) == data)
        #expect(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int == 0o600)
        #expect(try persistence.load() == result)
        let encoded = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: persistence.file)) as? [String: Any])
        #expect((encoded["projects"] as? [[String: Any]])?.first?["localURL"] == nil)
    }

    @Test func portAndPinnedPreferencesWithoutGuessingTies() throws {
        let unpinned = ProjectTask(definition: TaskDefinition(name: "dev", command: "bun dev"))
        let pinned = ProjectTask(definition: TaskDefinition(name: "dev", command: "bun run 'dev'"), pinned: true)
        #expect(try WorkspaceMigration.decode(legacyData([unpinned, pinned], address: "http://localhost:5174"))
            .projects[0].linkedTasks.first?.id == pinned.id)
        let explicit = ProjectTask(definition: TaskDefinition(name: "Other", command: "serve --port 3002"))
        #expect(try WorkspaceMigration.decode(legacyData([pinned, explicit], address: "http://localhost:3002"))
            .projects[0].linkedTasks.first?.id == explicit.id)
        let duplicate = ProjectTask(definition: pinned.definition, pinned: true)
        #expect(throws: (any Error).self) { try WorkspaceMigration.decode(legacyData([pinned, duplicate], address: "http://localhost:3000")) }
        let empty = try WorkspaceMigration.decode(legacyData([pinned], address: ""))
        #expect(empty.projects[0].linkedTasks.isEmpty)
        #expect(!empty.projects[0].tasks[0].temporary)
    }

    private func legacyData(_ tasks: [ProjectTask], address: String) throws -> Data {
        let project = Project(name: "Example", directory: "/example/project", tasks: tasks)
        var document = WorkspaceDocument(projects: [project])
        document.version = 1
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        var projects = try #require(object["projects"] as? [[String: Any]])
        projects[0]["localURL"] = address
        var legacyTasks = try #require(projects[0]["tasks"] as? [[String: Any]])
        for index in legacyTasks.indices { legacyTasks[index].removeValue(forKey: "temporary") }
        projects[0]["tasks"] = legacyTasks
        object["projects"] = projects
        return try JSONSerialization.data(withJSONObject: object)
    }
}
