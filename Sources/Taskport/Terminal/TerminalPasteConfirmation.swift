import AppKit
import GhosttyTerminal

/// Holds at most one protected paste until a native sheet receives an explicit answer.
@MainActor
final class TerminalPasteConfirmation {
    typealias Presenter = (NSAlert, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void
    private let present: Presenter
    private var pending: (id: UUID, alert: NSAlert, respond: (Bool) -> Void)?

    init(present: @escaping Presenter = { alert, window, completion in
        alert.beginSheetModal(for: window, completionHandler: completion)
    }) {
        self.present = present
    }

    func request(kind: TerminalClipboardRequestKind, window: NSWindow?,
                 isValid: @escaping () -> Bool, respond: @escaping (Bool) -> Void) {
        // OSC 52 requests remain denied: this UI only confirms user-initiated pastes.
        guard kind == .paste, let window, window.attachedSheet == nil,
              pending == nil, isValid() else { respond(false); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Paste potentially unsafe text?"
        alert.informativeText = "This text could immediately run commands in the terminal. Paste only text you trust."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Paste")
        let id = UUID()
        pending = (id, alert, respond)
        present(alert, window) { [weak self] result in
            guard let self, let pending = self.pending, pending.id == id else { return }
            self.pending = nil
            pending.respond(result == .alertSecondButtonReturn && isValid())
        }
    }

    /// Resolve before dismissing the sheet; a delayed UI completion must not approve it.
    func cancel() {
        guard let pending else { return }
        self.pending = nil
        pending.respond(false)
        if let window = pending.alert.window.sheetParent {
            window.endSheet(pending.alert.window, returnCode: .cancel)
        }
    }

    deinit {
        MainActor.assumeIsolated { pending?.respond(false) }
    }
}
