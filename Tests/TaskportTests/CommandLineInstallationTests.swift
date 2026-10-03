import Foundation
import Testing
@testable import Taskport

struct CommandLineInstallationTests {
    @Test func installsAndRemovesOnlyItsOwnLink() throws {
        let root = testDirectory("cli-install")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example App.app")
        let installer = CommandLineInstallation(bundle: bundle, directory: root.appendingPathComponent("bin"))
        try FileManager.default.createDirectory(at: installer.executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: installer.executable.path, contents: Data(), attributes: [.posixPermissions: 0o700]))
        try installer.install()
        try installer.install()
        #expect(installer.isInstalled)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.destination.path) == installer.executable.path)
        try installer.uninstall()
        #expect(!installer.isInstalled)
        #expect(FileManager.default.fileExists(atPath: installer.executable.path))

        let unrelated = Data("Unrelated command".utf8)
        try unrelated.write(to: installer.destination)
        #expect(throws: (any Error).self) { try installer.install() }
        #expect(throws: (any Error).self) { try installer.uninstall() }
        #expect(try Data(contentsOf: installer.destination) == unrelated)
        try FileManager.default.removeItem(at: installer.destination)
        try FileManager.default.createSymbolicLink(atPath: installer.destination.path, withDestinationPath: root.appendingPathComponent("missing").path)
        #expect(throws: (any Error).self) { try installer.install() }
        #expect(throws: (any Error).self) { try installer.uninstall() }
    }

    @Test @MainActor func projectIconPersistsAcrossEditing() throws {
        let root = testDirectory("project-icon")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        _ = try store.addProject(name: "Example", directory: root.path, iconName: "terminal")
        var project = try #require(store.selectedProject)
        #expect(project.iconName == "terminal")
        project.iconName = "globe"
        try store.updateProject(project)
        #expect(try store.persistence.load().projects.first?.iconName == "globe")
    }
}
