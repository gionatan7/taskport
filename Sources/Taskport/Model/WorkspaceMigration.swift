import Foundation

/// One-way conversion of project URLs to task metadata. Never executes project commands.
enum WorkspaceMigration {
    static func decode(_ data: Data) throws -> WorkspaceDocument {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int, [1, 2].contains(version) else {
            throw WorkspaceError("Unsupported workspace version. The saved file has not been changed.")
        }
        if version == 1 {
            guard var projects = object["projects"] as? [[String: Any]] else { throw WorkspaceError("Invalid projects in workspace.") }
            for index in projects.indices {
                guard var tasks = projects[index]["tasks"] as? [[String: Any]] else { throw WorkspaceError("Invalid tasks in workspace.") }
                for taskIndex in tasks.indices { tasks[taskIndex]["temporary"] = false }
                let address = projects[index].removeValue(forKey: "localURL") as? String ?? ""
                if !address.isEmpty {
                    let candidates = tasks.indices.filter {
                        tasks[$0]["sourceKey"] as? String != "builtin:cloudflare"
                            && (tasks[$0]["definition"] as? [String: Any])?["kind"] as? String == "service"
                    }
                    let ranked = candidates.map { ($0, score(tasks[$0], address: address)) }.sorted { $0.1 > $1.1 }
                    guard let best = ranked.first, ranked.count == 1 || best.1 > ranked[1].1 else {
                        throw WorkspaceError("Couldn't uniquely assign the local URL for \(projects[index]["name"] as? String ?? "a project"). The original workspace is unchanged.")
                    }
                    tasks[best.0]["localURL"] = try LocalAddress.validate(address)
                    for tunnelIndex in tasks.indices where tasks[tunnelIndex]["sourceKey"] as? String == "builtin:cloudflare" {
                        tasks[tunnelIndex]["tunnelForTaskID"] = tasks[best.0]["id"]
                        tasks[tunnelIndex]["temporary"] = true
                    }
                }
                projects[index]["tasks"] = tasks
            }
            object["projects"] = projects
            object["version"] = 2
        }
        return try JSONDecoder().decode(WorkspaceDocument.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func score(_ task: [String: Any], address: String) -> Int {
        let definition = task["definition"] as? [String: Any] ?? [:]
        let command = (definition["command"] as? String ?? "").lowercased()
        let name = (definition["name"] as? String ?? "").lowercased()
        var score = task["pinned"] as? Bool == true ? 1 : 0
        if let port = URLComponents(string: address)?.port,
           command.range(of: "(?<![0-9])\(port)(?![0-9])", options: .regularExpression) != nil { score += 100 }
        if command.contains("launch.sh") || command.contains("java ") || name.contains("jar") { score += 20 }
        if command.contains(" dev") || command.contains("'dev'") || command.contains("serve") || name.contains("web") { score += 10 }
        if command.contains("watch") || command.contains("rollup") { score -= 10 }
        return score
    }
}
