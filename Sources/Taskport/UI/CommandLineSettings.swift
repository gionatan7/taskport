import SwiftUI

struct CommandLineSettings: View {
    let store: WorkspaceStore
    private let installation = CommandLineInstallation()
    @State private var installed = false
    @State private var error: String?
    @State private var confirming = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Resume running tasks on launch", isOn: Binding(
                    get: { store.resumeTasksOnLaunch },
                    set: { enabled in
                        do { try store.setResumeTasksOnLaunch(enabled); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                ))
                .toggleStyle(.switch)
                .disabled(store.isReadOnly)
                Text("Restart pinned tasks that were running when Taskport quit. One-offs, temporary tasks, and tunnels stay stopped. Does not affect tasks running now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Command-line tool") {
                LabeledContent("Command", value: "taskport")
                LabeledContent("Location") {
                    Text(installation.destination.path).textSelection(.enabled)
                }
                Text(installed ? "Installed for this app." : "Not installed for this app.")
                    .foregroundStyle(.secondary)
                Text("Creates a link to this app’s bundled CLI. Keep the app in a stable location. No shell files are changed; add ~/.local/bin to your PATH if it isn’t there already.")
                    .font(.caption)
                Button(installed ? "Uninstall command-line tool…" : "Install command-line tool…") { confirming = true }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 430)
        .onAppear { installed = installation.isInstalled }
        .confirmationDialog(installed ? "Uninstall the taskport command?" : "Install the taskport command?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(installed ? "Uninstall" : "Install") {
                do {
                    if installed { try installation.uninstall() } else { try installation.install() }
                    error = nil
                } catch { self.error = error.localizedDescription }
                installed = installation.isInstalled
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(installed ? "Only the link at \(installation.destination.path) will be removed. Your projects and app will remain."
                 : "Create \(installation.destination.path) pointing to this app? Existing files will not be replaced.")
        }
    }
}
