import SwiftUI

struct TaskPicker: View {
    let project: Project
    let store: WorkspaceStore
    let select: (ProjectTask) -> Void
    let edit: (ProjectTask) -> Void
    let importTasks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasks").font(.headline).padding()
            Divider()
            if project.tasks.isEmpty {
                Text("No tasks yet. Import project commands or use + to create one.")
                    .foregroundStyle(.secondary).padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(project.tasks.filter { $0.sourceKey != "builtin:cloudflare" }) { task in
                            HStack(spacing: 10) {
                                Button { select(task) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.definition.name).foregroundStyle(.primary)
                                        Text("\(task.source ?? "Taskport") · \(task.definition.kind.label)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if task.isOverridden {
                                            Text("Local override").font(.caption).foregroundStyle(.secondary)
                                        }
                                        if task.temporary { Text("Temporary").font(.caption).foregroundStyle(.secondary) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button { edit(task) } label: { Image(systemName: "pencil").frame(width: 28, height: 28) }
                                    .help("Edit \(task.definition.name)")
                                    .accessibilityLabel("Edit \(task.definition.name)")
                                Button { store.perform { try store.togglePin(task, projectID: project.id) } } label: {
                                    Image(systemName: task.pinned ? "pin.fill" : "pin").frame(width: 28, height: 28)
                                }
                                .help(task.pinned ? "Unpin task" : "Pin as a long-running task for Run all and project status")
                                .accessibilityLabel("\(task.pinned ? "Unpin" : "Pin") \(task.definition.name)")
                                .disabled(task.temporary)
                            }
                            .buttonStyle(.borderless)
                            .padding(.horizontal).padding(.vertical, 10)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 360)
            }
            Divider()
            Button("Import project tasks…", systemImage: "square.and.arrow.down", action: importTasks)
                .buttonStyle(.borderless).padding()
        }.frame(width: 390)
    }
}
