import Foundation

/// Standard user-wide skill locations; Shared is Codex's default location.
enum AgentSkillDestination: String, CaseIterable, Identifiable {
    case shared, claudeCode, cursor, copilot, geminiCLI, openCode

    var id: String { rawValue }

    var name: String {
        switch self {
        case .shared: "Shared"
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        case .geminiCLI: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }

    var relativePath: String {
        switch self {
        case .shared: ".agents/skills"
        case .claudeCode: ".claude/skills"
        case .cursor: ".cursor/skills"
        case .copilot: ".copilot/skills"
        case .geminiCLI: ".gemini/skills"
        case .openCode: ".config/opencode/skills"
        }
    }

    func directory(in home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(relativePath, isDirectory: true)
    }
}

/// Links the app's bundled skill. Existing files and links from other installers are never replaced.
struct AgentSkillInstallation {
    enum Status: Equatable {
        case notInstalled, installed, occupied, inaccessible
    }

    let source: URL
    let destination: URL

    init(bundle: URL = Bundle.main.bundleURL, directory: URL) {
        source = bundle.appendingPathComponent("Contents/Resources/AgentSkills/taskport", isDirectory: true)
        destination = directory.appendingPathComponent("taskport", isDirectory: true)
    }

    var status: Status {
        let files = FileManager.default
        do {
            let attributes = try files.attributesOfItem(atPath: destination.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink,
               try files.destinationOfSymbolicLink(atPath: destination.path) == source.path {
                return .installed
            }
            return .occupied
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .notInstalled
        } catch {
            return .inaccessible
        }
    }

    func install() throws {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        let instructions = source.appendingPathComponent("SKILL.md")
        guard files.fileExists(atPath: instructions.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw WorkspaceError("The bundled Taskport skill is missing. Reinstall Taskport before trying again.")
        }
        if status == .installed { return }
        guard status == .notInstalled else {
            throw WorkspaceError("Couldn't install at \(destination.path). Move the existing skill aside or check folder permissions, then try again. Nothing has been replaced.")
        }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Creating a link fails if another file or even a dangling link appears after the status check.
        do {
            try files.createSymbolicLink(atPath: destination.path, withDestinationPath: source.path)
        } catch {
            throw WorkspaceError("Couldn't install at \(destination.path). Check folder permissions and existing files, then try again. Nothing has been replaced.")
        }
    }

    func uninstall() throws {
        guard status == .installed else {
            throw WorkspaceError("This skill isn't linked to this Taskport app. Nothing has been removed.")
        }
        try FileManager.default.removeItem(at: destination)
    }
}
