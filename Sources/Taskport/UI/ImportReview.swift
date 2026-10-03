import SwiftUI

struct ImportReview: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let projectID: UUID
    let result: TaskImport
    @State private var selected: Set<UUID> = []
    @State private var error: String?

    private var available: [ProjectTask] {
        let existing = Set(store.document.projects.first { $0.id == projectID }?.tasks.compactMap(\.sourceKey) ?? [])
        return result.tasks.filter { $0.sourceKey.map { !existing.contains($0) } ?? true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import project tasks").font(.title2).bold()
            Text("Review these commands before adding them. Nothing runs during import, and project files stay unchanged.")
                .foregroundStyle(.secondary)
            List {
                ForEach(available) { task in
                    Toggle(isOn: Binding(get: { selected.contains(task.id) }, set: {
                        if $0 { selected.insert(task.id) } else { selected.remove(task.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.definition.name)
                            Text(task.definition.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("\(task.source ?? "Project") · \(task.definition.kind.label)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if available.isEmpty { Text("No new supported tasks found in .vscode/tasks.json or package.json.").foregroundStyle(.secondary) }
                if !result.warnings.isEmpty {
                    Section("Needs attention") {
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                        }
                    }
                }
            }.frame(height: 320)
            Text("Imported tasks start unpinned. Pin a service from Tasks to include it in Run all and project status. Pinning doesn't override its command.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Select all") { selected = Set(available.map(\.id)) }.disabled(available.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import \(selected.count) tasks", action: save).keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
            }
        }.padding(24).frame(width: 610)
    }

    private func save() {
        do { try store.importTasks(available.filter { selected.contains($0.id) }, projectID: projectID); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
