import AppKit
import SwiftUI

struct AgentSkillSettings: View {
    @State private var selected: Set<AgentSkillDestination> = [.shared]
    @State private var statuses: [AgentSkillDestination: AgentSkillInstallation.Status] = [:]
    @State private var pending: Operation?
    @State private var confirming = false
    @State private var message: String?
    @State private var error: String?

    private struct Operation {
        let uninstall: Bool
        let targets: [AgentSkillDestination]
    }

    private func targets(with status: AgentSkillInstallation.Status) -> [AgentSkillDestination] {
        AgentSkillDestination.allCases.filter { selected.contains($0) && statuses[$0] == status }
    }

    var body: some View {
        Section {
            ForEach(AgentSkillDestination.allCases) { destination in
                Toggle(isOn: Binding(
                    get: { selected.contains(destination) },
                    set: { enabled in
                        if enabled { selected.insert(destination) } else { selected.remove(destination) }
                        message = nil
                        error = nil
                    }
                )) {
                    AgentSkillDestinationRow(destination: destination, status: statuses[destination] ?? .notInstalled)
                }
                .toggleStyle(.checkbox)
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent skill")
                Text("Choose where to install the Taskport skill.")
                    .font(.body).fontWeight(.regular).foregroundStyle(.secondary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Links to the skill bundled with this app, so updates stay in sync. Uses taskport from PATH; no checkout required.")
                if statuses.values.contains(.occupied) {
                    Text("Existing skills are kept. Move them aside to install this app’s version.")
                }
                HStack {
                    Button("Uninstall selected…") { confirm(uninstall: true) }
                        .disabled(targets(with: .installed).isEmpty)
                    Spacer()
                    Button("Install selected…") { confirm(uninstall: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(targets(with: .notInstalled).isEmpty)
                }
                .font(.body)
                if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(.primary) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .alert(pending?.uninstall == true ? "Uninstall the Taskport skill?" : "Install the Taskport skill?",
               isPresented: $confirming, presenting: pending) { operation in
            Button(operation.uninstall ? "Uninstall" : "Install", role: operation.uninstall ? .destructive : nil) {
                perform(operation)
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { operation in
            let paths = operation.targets.map { "~/\($0.relativePath)/taskport" }.joined(separator: "\n")
            Text(operation.uninstall
                 ? "Remove only this app’s skill links? The app, CLI, and your projects will stay.\n\n\(paths)"
                 : "Create links to this app’s bundled skill? Existing skills will not be replaced.\n\n\(paths)")
        }
    }

    private func refresh() {
        statuses = Dictionary(uniqueKeysWithValues: AgentSkillDestination.allCases.map {
            ($0, AgentSkillInstallation(directory: $0.directory()).status)
        })
    }

    private func confirm(uninstall: Bool) {
        refresh()
        let targets = targets(with: uninstall ? .installed : .notInstalled)
        guard !targets.isEmpty else { return }
        pending = Operation(uninstall: uninstall, targets: targets)
        confirming = true
    }

    private func perform(_ operation: Operation) {
        var completed: [String] = []
        var failures: [String] = []
        for target in operation.targets {
            let installation = AgentSkillInstallation(directory: target.directory())
            do {
                if operation.uninstall { try installation.uninstall() } else { try installation.install() }
                completed.append(target.name)
            } catch { failures.append("\(target.name): \(error.localizedDescription)") }
        }
        message = completed.isEmpty ? nil : "\(operation.uninstall ? "Uninstalled" : "Installed") for \(completed.joined(separator: ", "))."
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        pending = nil
        refresh()
    }
}

private struct AgentSkillDestinationRow: View {
    let destination: AgentSkillDestination
    let status: AgentSkillInstallation.Status

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(destination.name).fontWeight(.medium)
                    if destination == .shared { Text("Default").font(.caption).foregroundStyle(.secondary) }
                }
                Text("~/\(destination.relativePath)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if destination == .shared {
                    Text("Codex and compatible agents").font(.caption).foregroundStyle(.secondary)
                }
                if status == .inaccessible {
                    Text("Check this folder’s permissions, then reopen Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch status {
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .occupied:
                Label("Already present", systemImage: "link").font(.caption).foregroundStyle(.secondary)
            case .inaccessible:
                Label("Can’t inspect", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
            case .notInstalled:
                EmptyView()
            }
        }
        .font(.body)
        .padding(.vertical, 2)
    }
}
