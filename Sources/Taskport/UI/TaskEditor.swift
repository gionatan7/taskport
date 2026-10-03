import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let projectID: UUID
    @State private var task: ProjectTask
    @State private var original: ProjectTask?
    @State private var environmentEntries: [TaskEnvironmentEntry]
    @State private var error: String?
    @FocusState private var focusName: Bool

    init(store: WorkspaceStore, projectID: UUID, task: ProjectTask, isNew: Bool = false) {
        self.store = store
        self.projectID = projectID
        _task = State(initialValue: task)
        _original = State(initialValue: isNew ? nil : task)
        _environmentEntries = State(initialValue: TaskEnvironmentEntry.rows(from: task.definition.environment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "New task" : "Edit task").font(.title2).bold()
            Form {
                TextField("Name", text: $task.definition.name).focused($focusName)
                LabeledContent("Command") {
                    TextEditor(text: $task.definition.command).font(.system(.body, design: .monospaced))
                        .frame(height: 80).border(.separator).accessibilityLabel("Command")
                }
                TextField("Working directory", text: $task.definition.directory, prompt: Text("Relative to the project folder"))
                TextField("Local URL", text: Binding(get: { task.localURL ?? "" }, set: { task.localURL = $0 }), prompt: Text("http://localhost:3000"))
                Text("Optional. Browser links and tunnels belong to this task.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Type", selection: $task.definition.kind) {
                    ForEach(TaskKind.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Temporary task", isOn: $task.temporary)
                Text("Removed when stopped or completed. Failures stay until dismissed. Never resumes after quitting Taskport.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pin this task", isOn: $task.pinned).disabled(task.definition.kind == .oneOff || task.temporary)
                Text("Pinned long-running tasks appear in tabs and participate in Run all and project status.")
                    .font(.caption).foregroundStyle(.secondary)
                TaskEnvironmentEditor(entries: $environmentEntries)
            }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Text(task.importedDefinition != nil ? "Changes apply to Taskport's copy only, on the next run." : "Runs in your login zsh session. Saving doesn't execute the command.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save task", action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
            .onAppear { focusName = true }
            .onChange(of: task.definition.kind) { if task.definition.kind == .oneOff { task.pinned = false } }
            .onChange(of: task.temporary) { if task.temporary { task.pinned = false } }
    }

    private func save() {
        do {
            task.definition.environment = try TaskEnvironmentEntry.environment(from: environmentEntries)
            try store.saveTask(task, projectID: projectID, replacing: original)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
