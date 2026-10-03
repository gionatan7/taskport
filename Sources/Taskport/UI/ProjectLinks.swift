import SwiftUI

struct ProjectLinks: View {
    let project: Project
    let store: WorkspaceStore
    @State private var sharingTask: ProjectTask?

    var body: some View {
        let tasks = project.linkedTasks
        if !tasks.isEmpty {
            Menu {
                if tasks.count == 1, let task = tasks.first {
                    actions(for: task)
                } else {
                    ForEach(tasks) { task in
                        Menu(task.definition.name) { actions(for: task) }
                    }
                }
            } label: { Label("Task links", systemImage: "link") }
            .labelStyle(.iconOnly)
            .help("Local and remote task links")
            .confirmationDialog("Share this local service publicly?", isPresented: Binding(
                get: { sharingTask != nil }, set: { if !$0 { sharingTask = nil } }
            ), titleVisibility: .visible) {
                Button("Start tunnel") {
                    if let task = sharingTask {
                        store.perform { try store.startTunnel(for: task.id, projectID: project.id, confirmedURL: task.localURL ?? "") }
                    }
                    sharingTask = nil
                }
            } message: {
                Text("Anyone with the temporary link can access \(sharingTask?.localURL ?? "this service"). Only share a service you intend to expose. Requires cloudflared on your shell's PATH; Taskport won't install it.")
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
                Button("Start tunnel…") { sharingTask = task }.disabled(store.isReadOnly)
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
