import SwiftUI

struct ProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let project: Project?
    @State private var name: String
    @State private var directory: String
    @State private var iconName: String
    @State private var showIcons = false
    @State private var error: String?
    @FocusState private var focusName: Bool

    init(store: WorkspaceStore, project: Project? = nil) {
        self.store = store
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _directory = State(initialValue: project?.directory ?? "")
        _iconName = State(initialValue: project?.iconName ?? "folder")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(project == nil ? "Add project" : "Edit project").font(.title2).bold()
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.headline)
                    TextField("Project name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .accessibilityLabel("Name")
                        .focused($focusName)
                }
                LabeledContent("Icon") {
                    Button { showIcons.toggle() } label: {
                        Label("Choose icon…", systemImage: iconName)
                    }
                    .popover(isPresented: $showIcons) {
                        ProjectIconPicker(selection: $iconName) { showIcons = false }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Project folder").font(.headline)
                    Spacer()
                    Button(directory.isEmpty ? "Choose…" : "Change…", action: chooseDirectory)
                        .accessibilityLabel("Choose project folder")
                }
                Text(directory.isEmpty ? "Choose where this project's tasks run." : directory)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if project != nil {
                    Text("Relative task paths follow this folder. Absolute paths stay unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let project, directory != project.directory {
                    HStack {
                        Image(systemName: "info.circle").accessibilityHidden(true)
                        Text("Stop tasks and clear terminal input before saving. Idle shells close; tabs and output stay.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 12) {
                if project == nil {
                    Text("No commands run when you add a project.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(project == nil ? "Add project" : "Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || directory.isEmpty)
            }
            .controlSize(.large)
        }.padding(24).frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { focusName = true }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose project"
        if !directory.isEmpty { panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directory = url.path
        if name.isEmpty { name = url.lastPathComponent }
    }

    private func save() {
        do {
            if let project {
                var updated = project
                updated.name = name
                updated.directory = directory
                updated.iconName = iconName
                try store.updateProject(updated, replacing: project)
            } else { try store.addProject(name: name, directory: directory, iconName: iconName) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
