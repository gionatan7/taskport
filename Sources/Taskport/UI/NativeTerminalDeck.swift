import GhosttyTerminal
import SwiftUI

/// Retain session-backed hosts and the selected placeholder so tab switches keep surfaces alive.
struct NativeTerminalDeck: NSViewRepresentable {
    let store: WorkspaceStore

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> TaskTerminalContainer {
        let view = TaskTerminalContainer()
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Terminal")
        return view
    }

    func updateNSView(_ view: TaskTerminalContainer, context: Context) {
        context.coordinator.update(view, store: store)
    }

    @MainActor final class Coordinator {
        var hosts: [UUID: NSHostingView<TaskTerminalContent>] = [:]
        var selectedID: UUID?

        func update(_ view: TaskTerminalContainer, store: WorkspaceStore) {
            let selected = store.selectedTaskID
            let sessions = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.id, $0) })
            let allIDs = Set(store.document.projects.flatMap(\.tasks).map(\.id)).union(sessions.values.filter(\.isQuickTerminal).map(\.id))
            var retainedIDs = Set(sessions.keys)
            if let selected { retainedIDs.insert(selected) }
            retainedIDs.formIntersection(allIDs)
            for id in Array(hosts.keys) where !retainedIDs.contains(id) {
                hosts.removeValue(forKey: id)?.removeFromSuperview()
            }
            for owner in store.document.projects {
                let tabs: [(id: UUID, task: ProjectTask?)] = owner.tasks.map { ($0.id, $0) }
                    + store.sessions.filter { $0.projectID == owner.id && $0.isQuickTerminal }.map { ($0.id, nil) }
                for tab in tabs where retainedIDs.contains(tab.id) {
                    let content = TaskTerminalContent(task: tab.task, terminalID: tab.id, projectID: owner.id, store: store)
                    let host: NSHostingView<TaskTerminalContent>
                    if let existing = hosts[tab.id] { host = existing; host.rootView = content }
                    else {
                        host = NSHostingView(rootView: content)
                        host.sizingOptions = []
                        host.autoresizingMask = []
                        host.frame = view.bounds
                        hosts[tab.id] = host
                        view.addSubview(host)
                    }
                    host.isHidden = tab.id != selected
                    host.setAccessibilityHidden(host.isHidden)
                    if let session = sessions[tab.id], session.terminal.isSurfaceVisible == host.isHidden {
                        DispatchQueue.main.async { [weak host, weak session] in
                            guard let host, let session else { return }
                            session.terminal.isSurfaceVisible = !host.isHidden
                        }
                    }
                }
            }
            guard selectedID != selected else { return }
            selectedID = selected
            view.needsLayout = true
            if let selected, let session = sessions[selected] {
                DispatchQueue.main.async { session.terminal.requestFocus() }
            }
        }
    }
}

/// Hidden terminals retain their last size; the selected terminal fills the available space.
final class TaskTerminalContainer: NSView {
    override func layout() {
        super.layout()
        for host in subviews where !host.isHidden && host.frame != bounds { host.frame = bounds }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        needsLayout = true
    }
}

struct TaskTerminalContent: View {
    let task: ProjectTask?
    let terminalID: UUID
    let projectID: UUID
    let store: WorkspaceStore
    @FocusState private var focused: Bool

    var body: some View {
        if let session = store.session(terminalID) {
            TerminalSurfaceView(context: session.terminal).terminalFocused($focused)
        } else if let task {
            ContentUnavailableView {
                Label(task.definition.name, systemImage: "terminal")
            } description: {
                Text(task.definition.command).font(.system(.body, design: .monospaced))
            } actions: {
                Button("Start task", action: start)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func start() {
        store.perform {
            guard let task else { return }
            guard !task.isTunnel else { throw WorkspaceError("Start a tunnel from Task links after confirming public exposure.") }
            try store.startTask(task.id, projectID: projectID, activate: false)
            store.session(task.id)?.terminal.requestFocus()
        }
    }
}
