import AppKit
import GhosttyTerminal
import Testing
@testable import Taskport

struct TerminalPointerTests {
    @Test @MainActor func ghosttySelectionStopsAfterMissingMouseUp() async throws {
        _ = NSApplication.shared
        let state = TerminalViewState(configSource: .generated("font-family = Menlo\nfont-size = 12"), theme: .init())
        let memory = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let view = TaskTerminalView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(memory))
        view.delegate = state
        view.controller = state.controller
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        memory.receive(String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789\r\n", count: 10))
        try await Task.sleep(for: .milliseconds(100))
        let surface = try #require(state.surface)
        func event(_ type: NSEvent.EventType, x: Double, y: Double = 290) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
        }
        view.mouseDown(with: try event(.leftMouseDown, x: 10))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 100))
        let selection = try #require(surface.readSelection())
        #expect(!selection.isEmpty)
        // Omit mouseUp: a later hover must not grow the completed drag selection.
        view.mouseMoved(with: try event(.mouseMoved, x: 300, y: 250))
        #expect(surface.readSelection() == selection)
        view.mouseDown(with: try event(.leftMouseDown, x: 10))
        view.mouseUp(with: try event(.leftMouseUp, x: 10))
        let clicked = surface.readSelection()
        view.mouseMoved(with: try event(.mouseMoved, x: 300, y: 250))
        #expect(surface.readSelection() == clicked)
    }

    @Test @MainActor func missingReleaseIsRecoveredBeforeHover() throws {
        let view = TaskTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        func event(_ type: NSEvent.EventType, x: Double) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 100),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
        }
        view.mouseDown(with: try event(.leftMouseDown, x: 10))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 20))
        #expect(view.lastLeftMouseEvent?.locationInWindow.x == 20)
        // Intentionally omit mouseUp, reproducing the stale Ghostty press.
        view.mouseMoved(with: try event(.mouseMoved, x: 200))
        #expect(view.lastLeftMouseEvent == nil)
        view.mouseDown(with: try event(.leftMouseDown, x: 10))
        view.mouseUp(with: try event(.leftMouseUp, x: 10))
        #expect(view.lastLeftMouseEvent == nil)
        view.mouseDown(with: try event(.leftMouseDown, x: 10))
        _ = view.resignFirstResponder()
        #expect(view.lastLeftMouseEvent == nil)
    }
}
