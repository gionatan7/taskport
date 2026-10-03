import Foundation
import Testing
@testable import Taskport

struct TaskImporterTests {
    @Test func inheritedExecutionSettingsAreNotSilentlyDropped() throws {
        for settings in [
            #""options":{"cwd":"${workspaceFolder}/web"}"#,
            #""options":{"env":{"EXAMPLE_MODE":"test"}}"#,
            #""options":{"shell":{"executable":"fish"}}"#,
            #""osx":{"options":{"cwd":"${workspaceFolder}/mac"}}"#,
            #""command":"echo", "args":["global argument"]"#
        ] {
            let data = Data("{\(settings),\"tasks\":[{\"label\":\"Example\",\"command\":\"true\"}]}".utf8)
            let result = try TaskImporter.parseVSCode(data)
            #expect(result.tasks.isEmpty)
            #expect(result.warnings.count == 1)
        }
    }

    @Test func jsoncPreservesStringsAndImportsServices() throws {
        let data = Data(#"""
        { // project commands
          "tasks": [
            {"label":"Web", "type":"shell", "command":"printf 'http://localhost // /* text */'", "isBackground":true,
             "options":{"cwd":"${workspaceFolder}/web"},},
            {"label":"Check", "type":"process", "command":"echo", "args":["two words", "it's quoted"]},
          ],
        }
        """#.utf8)
        let result = try TaskImporter.parseVSCode(data)
        #expect(result.warnings.isEmpty)
        #expect(result.tasks.count == 2)
        #expect(result.tasks[0].definition.kind == .service)
        #expect(result.tasks[0].definition.command.contains("// /* text */"))
        #expect(result.tasks[0].definition.directory == "${workspaceFolder}/web")
        #expect(result.tasks[1].definition.command == "'echo' 'two words' 'it'\\''s quoted'")
        #expect(result.tasks.allSatisfy { !$0.pinned && !$0.isOverridden })
    }

    @Test func unsupportedSemanticsAreNotExecuted() throws {
        let data = Data(#"""
        {"tasks":[
          {"label":"Compound","dependsOn":["Web"]},
          {"label":"Provider","type":"npm","command":"dev"},
          {"label":"Variable","command":"${workspaceFolder}/run"},
          {"label":"Invalid environment","command":"true","options":{"env":{"BAD-NAME":"value"}}},
          {"label":"Custom shell","command":"true","options":{"shell":{"executable":"fish"}}}
        ]}
        """#.utf8)
        let result = try TaskImporter.parseVSCode(data)
        #expect(result.tasks.isEmpty)
        #expect(result.warnings.count == 5)
    }

    @Test func packageRunnerUsesProjectLockfileWithoutRunningScripts() throws {
        let directory = testDirectory("import")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = Data(#"{"scripts":{"dev":"echo never executed", "check":"exit 1"}}"#.utf8)
        try package.write(to: directory.appendingPathComponent("package.json"))
        try Data().write(to: directory.appendingPathComponent("bun.lock"))
        let result = try TaskImporter.discover(in: directory)
        #expect(result.tasks.map(\.definition.command) == ["bun run 'check'", "bun run 'dev'"])
        #expect(result.tasks.allSatisfy { $0.definition.kind == .oneOff && !$0.pinned })
        #expect(try Data(contentsOf: directory.appendingPathComponent("package.json")) == package)
    }
}
