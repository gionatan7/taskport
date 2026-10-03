import Foundation
import Testing
@testable import Taskport

struct ProjectOpenerTests {
    @Test func discoversOnlyRootWorkspaceFiles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/opener-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try ProjectOpener.workspaces(in: root).isEmpty)
        try Data().write(to: root.appendingPathComponent("Main.code-workspace"))
        #expect(try ProjectOpener.workspaces(in: root).map(\.lastPathComponent) == ["Main.code-workspace"])
        try Data().write(to: root.appendingPathComponent("Other.code-workspace"))
        let nested = root.appendingPathComponent("Folder.code-workspace")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("Nested.code-workspace"))
        try Data().write(to: root.appendingPathComponent("package.json"))
        #expect(try ProjectOpener.workspaces(in: root).map(\.lastPathComponent) == ["Main.code-workspace", "Other.code-workspace"])
    }
}
