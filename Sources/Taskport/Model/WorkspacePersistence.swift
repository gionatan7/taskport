import Foundation
import TaskportControl

/// Private, atomic JSON storage. Never recover a malformed file by overwriting it.
struct WorkspacePersistence {
    let directory: URL
    var file: URL { directory.appendingPathComponent("workspace.json") }

    static var applicationDirectory: URL {
        ControlPaths.directory
    }

    func load() throws -> WorkspaceDocument {
        guard FileManager.default.fileExists(atPath: file.path) else { return WorkspaceDocument() }
        let document = try WorkspaceMigration.decode(Data(contentsOf: file))
        let projects = document.projects.map(\.id)
        let tasks = document.projects.flatMap(\.tasks).map(\.id)
        guard Set(projects).count == projects.count, Set(tasks).count == tasks.count else {
            throw WorkspaceError("The workspace contains duplicate IDs. The saved file has not been changed.")
        }
        return document
    }

    func save(_ document: WorkspaceDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Retain the private v1 snapshot before the first successful v2 write.
        let backup = directory.appendingPathComponent("workspace-v1.json")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
            let previous = try Data(contentsOf: file)
            if let object = try JSONSerialization.jsonObject(with: previous) as? [String: Any], object["version"] as? Int == 1 {
                guard FileManager.default.createFile(atPath: backup.path, contents: previous, attributes: [.posixPermissions: 0o600]) else {
                    throw WorkspaceError("Couldn't back up the old workspace before migrating it.")
                }
            }
        }
        // Write a private staging file before atomic replacement; never briefly expose secrets.
        let staging = directory.appendingPathComponent(".workspace-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.createFile(atPath: staging.path, contents: try encoder.encode(document),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw WorkspaceError("Couldn't write the workspace. Check the Application Support folder permissions.")
        }
        guard rename(staging.path, file.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
