import AppKit
import SwiftUI

struct CommandLineSettings: View {
    private let installation = CommandLineInstallation()
    @State private var installed = false
    @State private var error: String?
    @State private var confirming = false

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "terminal").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("taskport").fontWeight(.semibold)
                    Text((installation.destination.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Button(installed ? "Uninstall…" : "Install…") { confirming = true }
                    .accessibilityLabel(installed ? "Uninstall command-line tool" : "Install command-line tool")
            }
            if let error { Text(error).foregroundStyle(.red) }
        } header: {
            Text("Command-line tool")
        } footer: {
            Text("Creates a link to this app’s CLI. Add ~/.local/bin to PATH if needed; no shell files are changed.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { installed = installation.isInstalled }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            installed = installation.isInstalled
        }
        .alert(installed ? "Uninstall the taskport command?" : "Install the taskport command?", isPresented: $confirming) {
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
