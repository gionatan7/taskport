import AppKit
import GhosttyTerminal
import Testing
@testable import Taskport

struct TerminalPasteConfirmationTests {
    @Test @MainActor func commandCompletionCancelsPasteButIdleShellCanApprove() async throws {
        _ = NSApplication.shared
        let root = testDirectory("paste-completion")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        var answer: ((NSApplication.ModalResponse) -> Void)?
        let confirmation = TerminalPasteConfirmation { _, _, completion in answer = completion }
        let session = TaskSession(taskID: UUID(), projectID: UUID(), dataDirectory: root,
            pasteConfirmation: confirmation)
        defer { session.terminate() }
        let task = ProjectTask(definition: TaskDefinition(name: "Paste target", command: "sleep 0.3"))
        try session.start(task: task, directory: root.path, focus: false)
        try await waitUntil { session.phase == .running }
        var responses: [Bool] = []
        confirmation.request(kind: .paste, window: window, isValid: { true }) { responses.append($0) }
        let staleAnswer = try #require(answer)
        try await waitUntil { session.phase == .exited(0) && session.shellReady }
        #expect(responses == [false])
        staleAnswer(.alertSecondButtonReturn)
        #expect(responses == [false])

        // A manual command returning to the same shell also changes the paste target.
        guard case .inMemory(let memory) = session.terminal.configuration.backend else {
            Issue.record("Expected the host-I/O backend"); return
        }
        memory.sendInput(Data("sleep 0.3\r".utf8))
        try await waitUntil { session.manualCommandRunning }
        confirmation.request(kind: .paste, window: window, isValid: { true }) { responses.append($0) }
        let manualAnswer = try #require(answer)
        try await waitUntil { session.shellReady && !session.manualCommandRunning }
        manualAnswer(.alertSecondButtonReturn)
        #expect(responses == [false, false])

        confirmation.request(kind: .paste, window: window, isValid: { true }) { responses.append($0) }
        let idleAnswer = try #require(answer)
        idleAnswer(.alertSecondButtonReturn)
        #expect(responses == [false, false, true])
        session.terminate()
        try await waitUntil { session.shellPID == 0 }
    }

    @Test @MainActor func denyProgramRequestsAndMissingWindows() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let confirmation = TerminalPasteConfirmation { _, _, _ in
            Issue.record("A denied request must not present a sheet")
        }
        for kind: TerminalClipboardRequestKind in [.osc52Read, .osc52Write] {
            var result: Bool?
            confirmation.request(kind: kind, window: window, isValid: { true }) { result = $0 }
            #expect(result == false)
        }
        var result: Bool?
        confirmation.request(kind: .paste, window: nil, isValid: { true }) { result = $0 }
        #expect(result == false)
        result = nil
        confirmation.request(kind: .paste, window: window, isValid: { false }) { result = $0 }
        #expect(result == false)
    }

    @Test @MainActor func explicitPasteAndCancel() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        var answer: ((NSApplication.ModalResponse) -> Void)?
        let confirmation = TerminalPasteConfirmation { alert, _, completion in
            #expect(alert.buttons.map(\.title) == ["Cancel", "Paste"])
            answer = completion
        }
        for accepted in [false, true] {
            var responses: [Bool] = []
            confirmation.request(kind: .paste, window: window, isValid: { true }) { responses.append($0) }
            #expect(responses.isEmpty)
            let complete = try #require(answer)
            complete(accepted ? .alertSecondButtonReturn : .alertFirstButtonReturn)
            complete(.alertSecondButtonReturn)
            #expect(responses == [accepted])
        }
    }

    @Test @MainActor func teardownAndStaleSheetCannotApprove() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        var answer: ((NSApplication.ModalResponse) -> Void)?
        let confirmation = TerminalPasteConfirmation { _, _, completion in answer = completion }
        var responses: [Bool] = []
        var valid = true
        confirmation.request(kind: .paste, window: window, isValid: { valid }) { responses.append($0) }
        valid = false
        let invalidatedAnswer = try #require(answer)
        invalidatedAnswer(.alertSecondButtonReturn)
        #expect(responses == [false])

        confirmation.request(kind: .paste, window: window, isValid: { true }) { responses.append($0) }
        let staleAnswer = try #require(answer)
        var overlappingResult: Bool?
        confirmation.request(kind: .paste, window: window, isValid: { true }) { overlappingResult = $0 }
        #expect(overlappingResult == false)
        confirmation.cancel()
        confirmation.cancel()
        staleAnswer(.alertSecondButtonReturn)
        #expect(responses == [false, false])

        confirmation.request(kind: .paste, window: window, isValid: { true }) { responses.append($0) }
        staleAnswer(.alertSecondButtonReturn)
        #expect(responses == [false, false])
        let latestAnswer = try #require(answer)
        latestAnswer(.alertSecondButtonReturn)
        #expect(responses == [false, false, true])
    }

    @Test @MainActor func releasedConfirmationDeniesAndSessionInstallsHook() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        var confirmation: TerminalPasteConfirmation? = TerminalPasteConfirmation { _, _, _ in }
        var result: Bool?
        confirmation?.request(kind: .paste, window: window, isValid: { true }) { result = $0 }
        confirmation = nil
        #expect(result == false)
        let session = TaskSession(taskID: UUID(), projectID: UUID(), dataDirectory: testDirectory("paste-hook"))
        #expect(session.terminal.onClipboardConfirmationRequest != nil)
    }
}
