import SwiftUI

struct TaskTabBar: View {
    let project: Project
    let store: WorkspaceStore
    @State private var forceStopID: UUID?
    @State private var closingTask: ProjectTask?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.visibleTasks(in: project)) { task in
                    let session = store.session(task.id)
                    let phase = session?.phase ?? .stopped
                    HStack(spacing: 4) {
                        Button {
                            store.perform { try store.openTask(task.id, projectID: project.id) }
                        } label: {
                            HStack(spacing: 8) {
                                ActivityDot(color: phase == .running ? .green : .gray,
                                    lastOutputAt: phase == .running ? session?.lastOutputAt ?? .distantPast : .distantPast)
                                Text(task.definition.name).lineLimit(1)
                                if case .exited(let code) = phase, code != 0 { Image(systemName: "exclamationmark.circle") }
                            }.padding(.vertical, 7).padding(.leading, 9).padding(.trailing, 4)
                        }
                        .accessibilityLabel("\(task.definition.name), \(phase.label)")
                        .accessibilityAddTraits(project.selectedTaskID == task.id ? .isSelected : [])
                        Button {
                            if phase.isActive { store.stopTask(task.id, projectID: project.id) }
                            else if task.isTunnel { store.errorMessage = "Start a tunnel from Task links after confirming public exposure." }
                            else { store.perform { try store.startTask(task.id, projectID: project.id) } }
                        } label: {
                            Image(systemName: phase.isActive ? "stop.fill" : "play.fill")
                                .font(.caption).frame(width: 28, height: 28)
                        }
                        .help("\(phase.isActive ? "Stop" : "Start") \(task.definition.name)")
                        .accessibilityLabel("\(phase.isActive ? "Stop" : "Start") \(task.definition.name)")
                        if !task.pinned {
                            Button { requestClose(task) } label: {
                                Image(systemName: "xmark").font(.caption).frame(width: 28, height: 28)
                            }
                            .help("Close \(task.definition.name)")
                            .accessibilityLabel("Close \(task.definition.name)")
                            .disabled(store.isReadOnly)
                        }
                    }
                    .buttonStyle(.borderless)
                    .background(project.selectedTaskID == task.id ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 7))
                    .help(session?.manualCommandRunning == true ? "Terminal in use" : phase.label)
                    .contextMenu {
                        if !task.pinned { Button("Close tab") { requestClose(task) }.disabled(store.isReadOnly) }
                        if let session, session.shellPID > 0 {
                            Button("Force stop terminal…", role: .destructive) { forceStopID = task.id }
                        }
                    }
                }
            }.padding(.horizontal, 10).padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task tabs")
        .confirmationDialog("Force stop this terminal?", isPresented: Binding(
            get: { forceStopID != nil }, set: { if !$0 { forceStopID = nil } }
        ), titleVisibility: .visible) {
            Button("Force stop terminal", role: .destructive) {
                if let id = forceStopID { store.session(id)?.terminate() }
                forceStopID = nil
            }
        } message: { Text("This closes the shell and terminates processes in its session. Unsaved work may be lost. Terminal output stays visible.") }
        .confirmationDialog("Stop and close \(closingTask?.definition.name ?? "terminal")?", isPresented: Binding(
            get: { closingTask != nil }, set: { if !$0 { closingTask = nil } }
        ), titleVisibility: .visible) {
            Button("Stop and close", role: .destructive) {
                if let task = closingTask { store.perform { try store.closeTab(task.id, projectID: project.id, confirmed: true) } }
                closingTask = nil
            }
            Button("Cancel", role: .cancel) { closingTask = nil }
        } message: { Text(closingTask?.temporary == true
            ? "The terminal and its processes will close. This temporary task and its output will be removed."
            : "The terminal and its processes will close, and its output will be discarded. The saved task remains in Tasks.") }
    }

    private func requestClose(_ task: ProjectTask) {
        let session = store.session(task.id)
        if session?.phase.isActive == true || session?.manualCommandRunning == true || session?.hasPendingInput == true { closingTask = task }
        else { store.perform { try store.closeTab(task.id, projectID: project.id) } }
    }
}
