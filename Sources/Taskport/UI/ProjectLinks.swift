import SwiftUI

struct ProjectLinks: View {
    let project: Project
    let store: WorkspaceStore
    @State private var pendingShare: PendingTunnelShare?

    var body: some View {
        if !project.linkedTasks.isEmpty {
            Menu {
                ProjectLinkActions(project: project, store: store, pendingShare: $pendingShare)
            } label: { Label("Task links", systemImage: "link") }
            .labelStyle(.iconOnly)
            .help("Local and remote task links")
            .modifier(TunnelSharingConfirmation(store: store, pendingShare: $pendingShare))
        }
    }
}

/// Shared by the toolbar and sidebar; keep the task's owning project when it isn't selected.
struct PendingTunnelShare {
    let projectID: UUID
    let task: ProjectTask
}

struct ProjectLinkActions: View {
    let project: Project
    let store: WorkspaceStore
    @Binding var pendingShare: PendingTunnelShare?

    var body: some View {
        let tasks = project.linkedTasks
        if tasks.count == 1, let task = tasks.first {
            actions(for: task)
        } else {
            ForEach(tasks) { task in
                Menu(task.definition.name) { actions(for: task) }
            }
        }
    }

    @ViewBuilder private func actions(for task: ProjectTask) -> some View {
        let tunnel = store.tunnel(for: task.id, in: project)
        let session = tunnel.flatMap { store.session($0.id) }
        Section("Local") {
            Button("Open in browser") { if let url = URL(string: task.localURL ?? "") { NSWorkspace.shared.open(url) } }
            Button("Copy link") { copy(task.localURL ?? "") }
        }
        Section("Remote") {
            if session?.phase.isActive == true {
                Button("Open in browser") { if let url = session?.remoteURL { NSWorkspace.shared.open(url) } }
                    .disabled(session?.remoteURL == nil)
                Button("Copy link") { if let url = session?.remoteURL { copy(url.absoluteString) } }
                    .disabled(session?.remoteURL == nil)
                Button("Stop tunnel") { if let tunnel { store.stopTask(tunnel.id, projectID: project.id) } }
            } else {
                Button("Start tunnel…") { pendingShare = PendingTunnelShare(projectID: project.id, task: task) }
                    .disabled(store.isReadOnly)
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// Attach to the persistent menu owner so dismissing a context menu doesn't lose its confirmation.
struct TunnelSharingConfirmation: ViewModifier {
    let store: WorkspaceStore
    @Binding var pendingShare: PendingTunnelShare?

    func body(content: Content) -> some View {
        content.confirmationDialog("Share this local service publicly?", isPresented: Binding(
            get: { pendingShare != nil }, set: { if !$0 { pendingShare = nil } }
        ), titleVisibility: .visible) {
            Button("Start tunnel") {
                if let request = pendingShare {
                    store.perform {
                        try store.startTunnel(for: request.task.id, projectID: request.projectID,
                            confirmedURL: request.task.localURL ?? "")
                    }
                }
                pendingShare = nil
            }
        } message: {
            Text("Anyone with the temporary link can access \(pendingShare?.task.localURL ?? "this service"). Only share a service you intend to expose. Requires cloudflared on your shell's PATH; Taskport won't install it.")
        }
    }
}
