import Foundation

struct TaskImport: Identifiable {
    let id = UUID()
    var tasks: [ProjectTask] = []
    var warnings: [String] = []
}

/// Reads definitions only. Unsupported execution semantics are skipped, never guessed.
enum TaskImporter {
    static func discover(in directory: URL) throws -> TaskImport {
        var result = TaskImport()
        let vscode = directory.appendingPathComponent(".vscode/tasks.json")
        if FileManager.default.fileExists(atPath: vscode.path) {
            do {
                let imported = try parseVSCode(Data(contentsOf: vscode))
                result.tasks += imported.tasks
                result.warnings += imported.warnings
            } catch { result.warnings.append("Couldn't read .vscode/tasks.json. Check its JSON syntax.") }
        }
        let package = directory.appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: package.path) {
            do {
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: package)) as? [String: Any]
                let scripts = json?["scripts"] as? [String: String] ?? [:]
                let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                let runner = files.contains("bun.lock") || files.contains("bun.lockb") ? "bun" :
                    files.contains("pnpm-lock.yaml") ? "pnpm" : files.contains("yarn.lock") ? "yarn" : "npm"
                for name in scripts.keys.sorted() {
                    let definition = TaskDefinition(name: name, command: "\(runner) run \(ShellBootstrap.quote(name))", kind: .oneOff)
                    result.tasks.append(ProjectTask(definition: definition, source: "package.json",
                        sourceKey: "package:\(name)", importedDefinition: definition))
                }
            } catch { result.warnings.append("Couldn't read package.json. Check its JSON syntax.") }
        }
        return result
    }

    static func parseVSCode(_ data: Data) throws -> TaskImport {
        let json = try JSONSerialization.jsonObject(with: stripJSONC(data)) as? [String: Any]
        guard let tasks = json?["tasks"] as? [[String: Any]] else {
            throw WorkspaceError("No tasks array was found.")
        }
        var result = TaskImport()
        // Don't silently drop inherited execution semantics. Task-level overrides are
        // supported below; project-wide defaults require manual setup until resolved fully.
        let executionKeys = ["command", "args", "type", "options", "isBackground", "dependsOn", "runOptions"]
        let mac = json?["osx"] as? [String: Any] ?? [:]
        if executionKeys.contains(where: { json?[$0] != nil || mac[$0] != nil }) {
            result.warnings.append("Project-wide VS Code execution settings need manual setup. No VS Code tasks were imported; define their commands, working directories, environments, and shells explicitly.")
            return result
        }
        var labels: Set<String> = []
        for raw in tasks {
            var raw = raw
            if let mac = raw["osx"] as? [String: Any] { raw.merge(mac) { _, new in new } }
            let name = raw["label"] as? String ?? "Unnamed task"
            guard let command = raw["command"] as? String, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if raw["dependsOn"] != nil { result.warnings.append("\(name): compound tasks aren't supported yet.") }
                continue
            }
            let type = raw["type"] as? String ?? "shell"
            let options = raw["options"] as? [String: Any] ?? [:]
            guard ["shell", "process"].contains(type), raw["dependsOn"] == nil,
                  options["shell"] == nil, raw["runOptions"] == nil else {
                result.warnings.append("\(name): provider, dependency, custom-shell, or automatic-run settings need manual setup.")
                continue
            }
            guard labels.insert(name).inserted else {
                result.warnings.append("\(name): duplicate label skipped."); continue
            }
            let args = raw["args"] as? [String] ?? []
            if raw["args"] != nil && !(raw["args"] is [String]) {
                result.warnings.append("\(name): structured arguments need manual setup."); continue
            }
            let env = options["env"] as? [String: String] ?? [:]
            if options["env"] != nil && !(options["env"] is [String: String]) {
                result.warnings.append("\(name): environment values must be strings."); continue
            }
            let directory = options["cwd"] as? String ?? "."
            guard !([command] + args).contains(where: { $0.contains("${workspaceFolder}") }) else {
                result.warnings.append("\(name): workspaceFolder in command text needs manual setup. Use it in the working directory instead.")
                continue
            }
            let components = [command, directory] + args + Array(env.values)
            let unsupported = components.contains {
                $0.replacingOccurrences(of: "${workspaceFolder}", with: "").contains("${")
            }
            guard !unsupported else {
                result.warnings.append("\(name): unresolved VS Code variables need manual setup."); continue
            }
            let line = ([type == "process" ? ShellBootstrap.quote(command) : command] + args.map(ShellBootstrap.quote)).joined(separator: " ")
            let definition = TaskDefinition(name: name, command: line, directory: directory,
                kind: raw["isBackground"] as? Bool == true ? .service : .oneOff, environment: env)
            guard (try? definition.validated()) != nil else {
                result.warnings.append("\(name): invalid command or environment needs manual setup."); continue
            }
            result.tasks.append(ProjectTask(definition: definition, source: ".vscode/tasks.json",
                sourceKey: "vscode:\(name)", importedDefinition: definition))
            if raw["problemMatcher"] != nil {
                result.warnings.append("\(name): problem matchers aren't applied; terminal output remains available.")
            }
        }
        return result
    }

    /// Removes comments and trailing commas while preserving quoted strings and escapes.
    static func stripJSONC(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var clean: [UInt8] = []
        var i = 0
        var quoted = false
        var escaped = false
        while i < bytes.count {
            let byte = bytes[i]
            if quoted {
                clean.append(byte)
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
                i += 1; continue
            }
            if byte == 34 { quoted = true; clean.append(byte); i += 1; continue }
            if byte == 47, i + 1 < bytes.count, bytes[i + 1] == 47 {
                while i < bytes.count, bytes[i] != 10 { i += 1 }
                continue
            }
            if byte == 47, i + 1 < bytes.count, bytes[i + 1] == 42 {
                i += 2
                while i + 1 < bytes.count, !(bytes[i] == 42 && bytes[i + 1] == 47) { i += 1 }
                i = min(i + 2, bytes.count)
                clean.append(32); continue
            }
            clean.append(byte); i += 1
        }
        var result: [UInt8] = []
        quoted = false; escaped = false
        for index in clean.indices {
            let byte = clean[index]
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 44 {
                var next = index + 1
                while next < clean.count, [9, 10, 13, 32].contains(clean[next]) { next += 1 }
                if next < clean.count, [93, 125].contains(clean[next]) { continue }
            }
            result.append(byte)
        }
        return Data(result)
    }
}
