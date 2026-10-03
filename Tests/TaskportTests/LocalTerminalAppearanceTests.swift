import Foundation
import Testing
@testable import Taskport

struct LocalTerminalAppearanceTests {
    @Test func appearanceOnly() {
        let config = LocalTerminalAppearance.render([
            ("foreground", "#abcdef"), ("palette", "2=#aabbcc"), ("font-size", "15"),
            ("command", "do-not-run"), ("env", "PRIVATE=not-for-export"),
            ("keybind", "super+a=text:private"), ("clipboard-read", "allow"),
            ("config-file", "/example/private.conf"), ("background-opacity", "0.2")
        ])
        #expect(config.contains("foreground = #abcdef"))
        #expect(config.contains("palette = 2=#aabbcc"))
        #expect(config.contains("font-size = 15"))
        #expect(!config.contains("private"))
        #expect(!config.contains("command"))
        #expect(!config.contains("clipboard"))
        #expect(config.contains("background-opacity = 1"))
    }

    @Test func rejectsInjectedDirectives() {
        let config = LocalTerminalAppearance.render([
            ("font-family", "Mono\ncommand = do-not-run"),
            ("foreground", "ffffff\renv = PRIVATE=not-for-export")
        ])
        #expect(!config.contains("do-not-run"))
        #expect(!config.contains("PRIVATE"))
    }

    @Test func missingConfigUsesEngineDefaults() {
        let config = LocalTerminalAppearance.load(
            home: URL(fileURLWithPath: "/example/missing-home"), environment: [:], ghosttyApplication: nil
        )
        #expect(config == LocalTerminalAppearance.render([]))
    }

    @Test func filePrecedenceIncludesAndThemeFiltering() throws {
        // Scratch data lives under the checkout, never in real user configuration.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/appearance-tests-\(UUID().uuidString)")
        let xdg = root.appendingPathComponent(".config/ghostty")
        let mac = root.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")
        try FileManager.default.createDirectory(at: xdg.appendingPathComponent("themes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "foreground = 111111\nconfig-file = extra\nforeground = 222222\ntheme = Example".write(
            to: xdg.appendingPathComponent("config.ghostty"), atomically: true, encoding: .utf8)
        try "foreground = 333333\nconfig-file = config.ghostty\nenv = PRIVATE=not-for-export".write(
            to: xdg.appendingPathComponent("extra"), atomically: true, encoding: .utf8)
        try "background = 123456\ncommand = do-not-run".write(
            to: xdg.appendingPathComponent("themes/Example"), atomically: true, encoding: .utf8)
        try "foreground = 444444".write(to: mac.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        let config = LocalTerminalAppearance.load(home: root, environment: [:], ghosttyApplication: nil)
        #expect(config.hasPrefix("background = 123456"))
        let foreground = config.split(separator: "\n").filter { $0.hasPrefix("foreground") }
        #expect(foreground == ["foreground = 111111", "foreground = 222222", "foreground = 333333", "foreground = 444444"])
        #expect(!config.contains("command"))
        #expect(!config.contains("PRIVATE"))
        #expect(!config.contains(root.path))
    }
}
