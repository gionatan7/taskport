import Foundation

/// Editable rows keep values literal, including empty strings, newlines, and equals signs.
struct TaskEnvironmentEntry: Identifiable {
    let id = UUID()
    var name = ""
    var value = ""

    static func rows(from environment: [String: String]) -> [Self] {
        environment.sorted { $0.key < $1.key }.map { Self(name: $0.key, value: $0.value) }
    }

    /// Name and value validity is checked by TaskDefinition when the task is saved.
    static func environment(from rows: [Self]) throws -> [String: String] {
        var environment: [String: String] = [:]
        for row in rows {
            guard environment.updateValue(row.value, forKey: row.name) == nil else {
                throw WorkspaceError("Each environment variable must have a unique name. Remove or rename the duplicate.")
            }
        }
        return environment
    }
}
