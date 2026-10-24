import SwiftUI

struct TaskportSettings: View {
    let store: WorkspaceStore
    let updates: AppUpdates
    @State private var selectedPane = Pane.general

    private enum Pane { case general, integrations }

    var body: some View {
        TabView(selection: $selectedPane) {
            GeneralSettings(store: store, updates: updates)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)
            Form {
                CommandLineSettings()
                AgentSkillSettings()
            }
            .formStyle(.grouped)
            .tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }
            .tag(Pane.integrations)
        }
        .frame(width: 640, height: selectedPane == .general ? 360 : 660)
    }
}

private struct GeneralSettings: View {
    let store: WorkspaceStore
    @Bindable var updates: AppUpdates
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Resume running tasks on launch", isOn: Binding(
                    get: { store.resumeTasksOnLaunch },
                    set: { enabled in
                        do { try store.setResumeTasksOnLaunch(enabled); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                ))
                .toggleStyle(.switch)
                .disabled(store.isReadOnly)
            } header: {
                Text("Startup")
            } footer: {
                Text("Restart pinned tasks that were running when Taskport quit. One-offs, temporary tasks, and tunnels stay stopped. Does not affect tasks running now.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updates.checksAutomatically)
                    .toggleStyle(.switch)
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheck)
            }
        }
        .formStyle(.grouped)
    }
}
