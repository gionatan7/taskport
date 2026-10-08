import Foundation
import Testing
@testable import Taskport

struct AgentSkillInstallationTests {
    @Test func destinationsUseStandardUserLocations() {
        let home = URL(fileURLWithPath: "/example/user", isDirectory: true)
        let paths = AgentSkillDestination.allCases.map { $0.directory(in: home).path }
        #expect(paths == ["/example/user/.agents/skills", "/example/user/.claude/skills",
                          "/example/user/.cursor/skills", "/example/user/.copilot/skills",
                          "/example/user/.gemini/skills", "/example/user/.config/opencode/skills"])
        #expect(Set(paths).count == paths.count)
        #expect(AgentSkillDestination.allCases.first == .shared)
    }

    @Test func installsAndRemovesOnlyItsOwnLink() throws {
        let root = testDirectory("skill-install")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example App.app")
        let installation = AgentSkillInstallation(bundle: bundle, directory: AgentSkillDestination.shared.directory(in: root))
        let instructions = Data("---\nname: taskport\ndescription: Example skill\n---\nUse taskport.\n".utf8)
        try FileManager.default.createDirectory(at: installation.source, withIntermediateDirectories: true)
        try instructions.write(to: installation.source.appendingPathComponent("SKILL.md"))

        #expect(installation.status == .notInstalled)
        try installation.install()
        try installation.install()
        #expect(installation.status == .installed)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installation.destination.path) == installation.source.path)
        #expect(try Data(contentsOf: installation.destination.appendingPathComponent("SKILL.md")) == instructions)

        // Updating the bundled instructions updates every installed link, without writing to an agent's folder.
        let updated = Data("Updated instructions".utf8)
        try updated.write(to: installation.source.appendingPathComponent("SKILL.md"))
        #expect(try Data(contentsOf: installation.destination.appendingPathComponent("SKILL.md")) == updated)
        try installation.uninstall()
        #expect(installation.status == .notInstalled)
        #expect(FileManager.default.fileExists(atPath: installation.source.appendingPathComponent("SKILL.md").path))
        #expect(throws: (any Error).self) { try installation.uninstall() }
    }

    @Test func refusesExistingFilesDirectoriesAndLinks() throws {
        let root = testDirectory("skill-existing")
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = AgentSkillInstallation(bundle: root.appendingPathComponent("Example.app"), directory: root.appendingPathComponent("skills"))
        try FileManager.default.createDirectory(at: installation.source, withIntermediateDirectories: true)
        try Data("Bundled skill".utf8).write(to: installation.source.appendingPathComponent("SKILL.md"))
        try FileManager.default.createDirectory(at: installation.destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let personal = Data("Existing personal skill".utf8)
        try personal.write(to: installation.destination)
        #expect(installation.status == .occupied)
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(throws: (any Error).self) { try installation.uninstall() }
        #expect(try Data(contentsOf: installation.destination) == personal)
        try FileManager.default.removeItem(at: installation.destination)

        try FileManager.default.createDirectory(at: installation.destination, withIntermediateDirectories: true)
        try personal.write(to: installation.destination.appendingPathComponent("SKILL.md"))
        #expect(installation.status == .occupied)
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(throws: (any Error).self) { try installation.uninstall() }
        #expect(try Data(contentsOf: installation.destination.appendingPathComponent("SKILL.md")) == personal)
        try FileManager.default.removeItem(at: installation.destination)

        let other = root.appendingPathComponent("other-skill")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try personal.write(to: other.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(atPath: installation.destination.path, withDestinationPath: other.path)
        #expect(installation.status == .occupied)
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(throws: (any Error).self) { try installation.uninstall() }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installation.destination.path) == other.path)
        #expect(try Data(contentsOf: other.appendingPathComponent("SKILL.md")) == personal)
    }

    @Test func danglingForeignLinkIsNeverReplaced() throws {
        let root = testDirectory("skill-dangling")
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = AgentSkillInstallation(bundle: root.appendingPathComponent("Example.app"), directory: root.appendingPathComponent("skills"))
        try FileManager.default.createDirectory(at: installation.source, withIntermediateDirectories: true)
        try Data("Bundled skill".utf8).write(to: installation.source.appendingPathComponent("SKILL.md"))
        try FileManager.default.createDirectory(at: installation.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("missing-skill").path
        try FileManager.default.createSymbolicLink(atPath: installation.destination.path, withDestinationPath: missing)
        #expect(installation.status == .occupied)
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(throws: (any Error).self) { try installation.uninstall() }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installation.destination.path) == missing)
    }

    @Test func missingBundleDoesNotCreateAgentFolders() throws {
        let root = testDirectory("skill-missing-bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = AgentSkillInstallation(bundle: root.appendingPathComponent("Missing.app"), directory: root.appendingPathComponent("skills"))
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: installation.source.appendingPathComponent("SKILL.md"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(!FileManager.default.fileExists(atPath: installation.destination.deletingLastPathComponent().path))
    }

    @Test func severalDestinationsStayIndependent() throws {
        let root = testDirectory("skill-multiple")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example.app")
        let first = AgentSkillInstallation(bundle: bundle, directory: AgentSkillDestination.shared.directory(in: root))
        let second = AgentSkillInstallation(bundle: bundle, directory: AgentSkillDestination.claudeCode.directory(in: root))
        try FileManager.default.createDirectory(at: first.source, withIntermediateDirectories: true)
        try Data("Bundled skill".utf8).write(to: first.source.appendingPathComponent("SKILL.md"))
        try first.install()
        try second.install()
        try first.uninstall()
        #expect(first.status == .notInstalled)
        #expect(second.status == .installed)
    }
}
