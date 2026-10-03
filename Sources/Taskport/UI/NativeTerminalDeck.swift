import GhosttyTerminal
import SwiftUI

/// Retain session-backed hosts and only visible placeholders. Switching panes keeps surfaces alive.
struct NativeTerminalDeck: NSViewRepresentable {
    let store: WorkspaceStore

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> TaskSplitView {
        let view = TaskSplitView()
        view.arrangesAllSubviews = false
        view.dividerStyle = .thin
        view.isVertical = true
        view.delegate = context.coordinator
        view.setAccessibilityLabel("Terminal panes")
        return view
    }

    func updateNSView(_ view: TaskSplitView, context: Context) {
        context.coordinator.update(view, store: store)
    }

    @MainActor final class Coordinator: NSObject, NSSplitViewDelegate {
        var hosts: [UUID: NSHostingView<TaskPane>] = [:]
        var layoutKey = ""
        var isUpdating = false
        var onResize: ((Double) -> Void)?
        var resizeTask: Task<Void, Never>?

        func update(_ view: TaskSplitView, store: WorkspaceStore) {
            let project = store.selectedProject
            let primary = project?.selectedTaskID
            let secondary = project?.split?.taskID
            let visible = [primary, secondary].compactMap { $0 }
            let visibleIDs = Set(visible)
            let axis = project?.split?.axis ?? .sideBySide
            let nextLayoutKey = "\(project?.id.uuidString ?? "")-\(visible)-\(axis)"
            let sessions = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.id, $0) })
            let allIDs = Set(store.document.projects.flatMap(\.tasks).map(\.id))
            let retainedIDs = Set(sessions.keys).union(visibleIDs).intersection(allIDs)
            for id in Array(hosts.keys) where !retainedIDs.contains(id) {
                if let host = hosts.removeValue(forKey: id) {
                    view.removeArrangedSubview(host)
                    host.removeFromSuperview()
                }
            }
            for owner in store.document.projects {
                for task in owner.tasks where retainedIDs.contains(task.id) {
                    let pane = TaskPane(task: task, projectID: owner.id, store: store, showHeader: secondary != nil && visibleIDs.contains(task.id))
                    let host: NSHostingView<TaskPane>
                    if let existing = hosts[task.id] { host = existing; host.rootView = pane }
                    else {
                        host = NSHostingView(rootView: pane)
                        host.sizingOptions = []
                        host.frame = view.bounds
                        hosts[task.id] = host
                        view.addSubview(host)
                    }
                    host.isHidden = !visibleIDs.contains(task.id)
                    host.setAccessibilityHidden(host.isHidden)
                    if let session = sessions[task.id], session.terminal.isSurfaceVisible == host.isHidden {
                        DispatchQueue.main.async { [weak host, weak session] in
                            guard let host, let session else { return }
                            session.terminal.isSurfaceVisible = !host.isHidden
                        }
                    }
                }
            }
            onResize = { ratio in
                if let project { store.saveSplitRatio(ratio, projectID: project.id, axis: axis) }
            }
            view.onPositionChanged = { [weak self] ratio in self?.saveUserRatio(ratio) }
            guard layoutKey != nextLayoutKey else { return }
            isUpdating = true
            view.applyingRatio = true
            resizeTask?.cancel()
            layoutKey = nextLayoutKey
            view.isVertical = axis == .sideBySide
            for arranged in view.arrangedSubviews { view.removeArrangedSubview(arranged) }
            for id in visible {
                if let host = hosts[id] { view.addArrangedSubview(host) }
            }
            view.proportion = project?.split?.ratio ?? 0.5
            view.adjustSubviews()
            view.applyingRatio = false
            view.applyProportion()
            isUpdating = false
            if let primary, let session = sessions[primary] {
                DispatchQueue.main.async { session.terminal.requestFocus() }
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            min(splitView.isVertical ? 180 : 110, (splitView.isVertical ? splitView.bounds.width : splitView.bounds.height) * 0.35)
        }
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            return length - min(splitView.isVertical ? 180 : 110, length * 0.35)
        }
        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? TaskSplitView,
                  !view.applyingRatio, view.arrangedSubviews.count == 2 else { return }
            // Layout/toolbar/window restoration also posts this notification. Only a
            // user divider move may replace the authoritative saved proportion.
            guard (notification.userInfo?["NSSplitViewUserResizeKey"] as? NSNumber)?.boolValue == true else { return }
            let length = view.isVertical ? view.bounds.width : view.bounds.height
            guard length > 0 else { return }
            let first = view.arrangedSubviews[0].frame
            let ratio = (view.isVertical ? first.width : first.height) / length
            view.proportion = ratio
            saveUserRatio(ratio)
        }

        func saveUserRatio(_ ratio: Double) {
            guard !isUpdating else { return }
            resizeTask?.cancel()
            let callback = onResize
            resizeTask = Task {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                callback?(ratio)
            }
        }
    }
}

/// SwiftUI initially mounts with zero bounds; defer restoration until a real layout exists.
final class TaskSplitView: NSSplitView {
    var proportion = 0.5
    var applyingRatio = false
    var onPositionChanged: ((Double) -> Void)?

    override func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        let userChange = !applyingRatio
        let length = isVertical ? bounds.width : bounds.height
        if userChange, length > 1 { proportion = position / length }
        super.setPosition(position, ofDividerAt: dividerIndex)
        if userChange, length > 1, arrangedSubviews.count == 2 {
            let first = arrangedSubviews[0].frame
            proportion = (isVertical ? first.width : first.height) / length
            onPositionChanged?(proportion)
        }
    }

    override func adjustSubviews() {
        let previous = applyingRatio
        applyingRatio = true
        super.adjustSubviews()
        applyingRatio = previous
    }

    override func layout() {
        applyingRatio = true
        super.layout()
        applyingRatio = false
        applyProportion()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        applyingRatio = true
        super.resizeSubviews(withOldSize: oldSize)
        applyingRatio = false
        applyProportion()
    }

    func applyProportion() {
        let length = isVertical ? bounds.width : bounds.height
        guard length > 1, arrangedSubviews.count == 2 else { return }
        applyingRatio = true
        setPosition(length * min(0.85, max(0.15, proportion)), ofDividerAt: 0)
        applyingRatio = false
    }
}

struct TaskPane: View {
    let task: ProjectTask
    let projectID: UUID
    let store: WorkspaceStore
    let showHeader: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let session = store.session(task.id)
        VStack(spacing: 0) {
            if showHeader {
                HStack {
                    Button(task.definition.name, systemImage: "terminal") { session?.terminal.requestFocus() }
                        .buttonStyle(.borderless).help("Focus \(task.definition.name) terminal")
                    Spacer()
                    Text(session?.manualCommandRunning == true ? "Terminal in use" : session?.phase.label ?? "Stopped")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        if session?.phase.isActive == true { store.stopTask(task.id, projectID: projectID) }
                        else { start() }
                    } label: {
                        Image(systemName: session?.phase.isActive == true ? "stop.fill" : "play.fill").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(session?.phase.isActive == true ? "Stop" : "Start") \(task.definition.name) in pane")
                }.padding(.horizontal, 10).background(.bar)
                Divider()
            }
            if let session {
                TerminalSurfaceView(context: session.terminal).terminalFocused($focused)
            } else {
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
        .overlay { if showHeader && focused { Rectangle().stroke(Color.accentColor.opacity(0.6), lineWidth: 1).allowsHitTesting(false) } }
    }

    private func start() {
        store.perform {
            guard !task.isTunnel else { throw WorkspaceError("Start a tunnel from Task links after confirming public exposure.") }
            try store.startTask(task.id, projectID: projectID, activate: false)
            store.session(task.id)?.terminal.requestFocus()
        }
    }
}
