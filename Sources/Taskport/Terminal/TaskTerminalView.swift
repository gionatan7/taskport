import AppKit
import GhosttyTerminal

/// Recover a release consumed by a hosting view, menu, or window transition.
/// Ghostty otherwise keeps extending the selection on ordinary mouse movement.
final class TaskTerminalView: AppTerminalView {
    private(set) var lastLeftMouseEvent: NSEvent?
    var onDetach: (() -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window != nil, newWindow !== window { onDetach?() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        lastLeftMouseEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        lastLeftMouseEvent = event
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        lastLeftMouseEvent = nil
        super.mouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        if event.type == .mouseMoved, let previous = lastLeftMouseEvent {
            // Release at the last pressed position, before forwarding hover.
            // A left-button drag arrives as mouseDragged, never mouseMoved.
            mouseUp(with: previous)
        }
        super.mouseMoved(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if let previous = lastLeftMouseEvent { mouseUp(with: previous) }
        return super.resignFirstResponder()
    }
}
