import Foundation
import Testing
import TaskportControl
@testable import Taskport

struct TerminalOutputTests {
    @Test func stripsSplitTerminalControlsWithoutKeepingTheirPayloads() {
        var output = TerminalOutput()
        output.append(Data("first\r\n\u{1b}[3".utf8))
        output.append(Data("2mgreen\u{1b}[0m\u{1b}]52;c;hidden".utf8))
        #expect(output.tail(lines: 100).text == "first\ngreen")
        output.append(Data("payload\u{07} text\u{1b}Pignored\u{1b}".utf8))
        output.append(Data("\\ done\u{1b}(B\nlast\n".utf8))
        #expect(output.tail(lines: 100).text == "first\ngreen text done\nlast\n")
        #expect(output.tail(lines: 1).text == "last\n")
        #expect(output.tail(lines: 1).truncated)
    }

    @Test func keepsSplitUTF8AndBoundsMemoryAndLineCount() {
        var output = TerminalOutput()
        let bytes = Data("caffè 🌱\n".utf8)
        output.append(Data(bytes.prefix(5)))
        output.append(Data(bytes.dropFirst(5)))
        #expect(output.tail(lines: 100).text == "caffè 🌱\n")
        #expect(!output.tail(lines: 100).truncated)
        output.append(Data(repeating: 0x78, count: TerminalOutput.byteLimit + 10))
        #expect(output.tail(lines: 100).text.utf8.count == TerminalOutput.byteLimit)
        #expect(output.tail(lines: 100).truncated)
        #expect(TerminalOutput().tail(lines: 100).text.isEmpty)
    }

    @Test @MainActor func cliReadsOwnOutputAndValidatesSelectors() async throws {
        let root = testDirectory("logs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let project = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Output", command: "printf 'taskport-log-ready\\n'; sleep 30"))
        try store.saveTask(task, projectID: project)
        let control = WorkspaceControl(store: store)
        let request = try CLIArguments.parse(["tasks", "logs", project.uuidString, task.id.uuidString, "--lines", "10"])
        #expect(control.handle(request).output == "")
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: project, activate: false)
        try await waitUntil { control.handle(request).output?.contains("taskport-log-ready") == true }
        let response = control.handle(request)
        #expect(response.ok)
        #expect(response.taskID == task.id)
        #expect(response.output?.contains("\u{1b}") == false)
        for value in ["0", "-1", "1001", "abc"] {
            var invalid = request
            invalid.values["lines"] = value
            #expect(control.handle(invalid).ok == false)
        }
        var foreign = request
        foreign.taskIDs = [UUID()]
        #expect(control.handle(foreign).ok == false)
        #expect(throws: (any Error).self) { try CLIArguments.parse(["tasks", "logs", project.uuidString]) }
        #expect(throws: (any Error).self) { try CLIArguments.parse(["tasks", "logs", project.uuidString, task.id.uuidString, UUID().uuidString]) }
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }
}
