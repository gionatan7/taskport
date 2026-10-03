import AppKit
import Testing
@testable import Taskport

struct ShellTests {
    @Test @MainActor func retainedSurfaceReplaysViewportBeforeFirstAndReplacementShell() async throws {
        _ = NSApplication.shared
        let root = testDirectory("retained-viewport")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TaskSession(taskID: UUID(), projectID: UUID(), dataDirectory: root)
        defer { session.terminate() }
        let view = TaskTerminalView(frame: NSRect(x: 0, y: 0, width: 620, height: 420))
        view.configuration = session.terminal.configuration
        view.delegate = session.terminal
        view.controller = session.terminal.controller
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await waitUntil { session.terminal.surfaceSize?.columns ?? 0 > 0 }
        let surface = try #require(session.terminal.surface)
        let viewport = try #require(session.terminal.surfaceSize)
        #expect(viewport.columns != 100 || viewport.rows != 24)
        let task = ProjectTask(definition: TaskDefinition(name: "Viewport", command: "stty size > size.txt"))
        for _ in 0..<2 {
            try session.start(task: task, directory: root.path, focus: false)
            try await waitUntil { session.phase == .exited(0) && session.shellReady }
            let size = try String(contentsOf: root.appendingPathComponent("size.txt"), encoding: .utf8)
            #expect(size.trimmingCharacters(in: .whitespacesAndNewlines) == "\(viewport.rows) \(viewport.columns)")
            session.resetIdleShell()
            try await waitUntil { session.shellPID == 0 }
            #expect(session.terminal.surface === surface)
        }
    }

    @Test func fragmentedMarkersPreserveOutput() {
        let input = Data("hello\u{1B}]777;taskport;test;busy\u{7}world\u{1B}]777;taskport;test;ready;17\u{7}$ ".utf8)
        for size in 1...input.count {
            var parser = ShellEvents(token: "test")
            var output = Data()
            var events: [ShellEvents.Event] = []
            for start in stride(from: 0, to: input.count, by: size) {
                let result = parser.consume(input.subdata(in: start..<min(start + size, input.count)))
                output.append(result.output)
                events += result.events
            }
            #expect(String(decoding: output, as: UTF8.self) == "helloworld$ ")
            #expect(events == [.busy, .ready(17)])
        }
    }

    @Test func foreignMarkersDoNotChangeState() {
        var parser = ShellEvents(token: "expected")
        let input = Data("\u{1B}]777;taskport;other;ready;0\u{7}".utf8)
        let result = parser.consume(input)
        #expect(result.events.isEmpty)
        #expect(result.output == input)
    }

    @Test @MainActor func realPTYTracksExitInterruptAndCleanup() async throws {
        let directory = testDirectory("pty")
        let hooks = directory.appendingPathComponent("hooks")
        try ShellBootstrap.prepare(in: hooks)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = PTYProcess()
        var parser = ShellEvents(token: "test")
        var events: [ShellEvents.Event] = []
        var output = ""
        var exitCode: Int32?
        process.onOutput = { data in
            let result = parser.consume(data)
            events += result.events
            output += String(decoding: result.output, as: UTF8.self)
        }
        process.onExit = { exitCode = $0 }
        try process.start(directory: directory.path, arguments: ["/bin/zsh", "-il"], environment: [
            "HOME": directory.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "xterm-256color",
            "ZDOTDIR": hooks.path, "TASKPORT_BOOTSTRAP_DIR": hooks.path,
            "TASKPORT_USER_ZDOTDIR": directory.path, "TASKPORT_SESSION_TOKEN": "test"
        ])
        defer { process.terminate() }
        try await waitUntil { events.contains(.ready(0)) }
        events.removeAll()
        process.write(Data("(exit 17)\r".utf8))
        try await waitUntil { events.contains(.ready(17)) }
        #expect(events.contains(.busy))
        events.removeAll()
        process.write(Data("sleep 30\r".utf8))
        try await waitUntil { events.contains(.busy) && process.foregroundPID != process.pid }
        let foreground = process.foregroundPID
        process.interrupt()
        try await waitUntil { events.contains(where: { if case .ready = $0 { true } else { false } }) }
        #expect(kill(foreground, 0) == -1)

        // Commands larger than a PTY input line are delivered via a private script.
        let taskFile = hooks.appendingPathComponent("task.zsh")
        for _ in 0..<3 {
            events.removeAll()
            let definition = TaskDefinition(name: "Long command", command: ": '\(String(repeating: "x", count: 12000))'; exit 23")
            let line = try ShellBootstrap.writeTask(definition, directory: directory.path, to: taskFile)
            #expect(line.utf8.count < 1000)
            process.write(Data(line.utf8))
            try await waitUntil { events.contains(.ready(23)) }
        }
        #expect(try FileManager.default.attributesOfItem(atPath: taskFile.path)[.posixPermissions] as? Int == 0o600)

        events.removeAll()
        let nested = TaskDefinition(name: "Nested child", command: "sleep 30 & print -r -- TASKPORT_TEST_CHILD=$!; wait")
        process.write(Data(try ShellBootstrap.writeTask(nested, directory: directory.path, to: taskFile).utf8))
        try await waitUntil { output.range(of: #"TASKPORT_TEST_CHILD=\d+"#, options: .regularExpression) != nil }
        let childRange = try #require(output.range(of: #"TASKPORT_TEST_CHILD=\d+"#, options: .regularExpression))
        let child = try #require(Int32(output[childRange].split(separator: "=").last!))
        #expect(kill(child, 0) == 0)
        let shellPID = process.pid
        process.terminate()
        try await waitUntil { exitCode != nil }
        try await waitUntil { kill(child, 0) == -1 }
        #expect(kill(shellPID, 0) == -1)
        #expect(!output.isEmpty)
    }
}

@MainActor func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw WorkspaceError("Timed out waiting for a test process event.")
}
