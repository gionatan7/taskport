import SwiftUI
import UniformTypeIdentifiers

struct ProjectSidebar: View {
    let store: WorkspaceStore
    @Binding var sheet: WorkspaceSheet?
    @State private var removingProject: Project?
    @State private var removingGroup: ProjectGroup?
    @State private var groupEditor: GroupEditorRequest?

    var body: some View {
        List(selection: Binding(get: { store.document.selectedProjectID }, set: store.selectProject)) {
            ForEach(store.document.groups) { group in
                Group {
                    ProjectGroupHeading(group: group, store: store)
                        .contextMenu {
                            Button("Add project…", systemImage: "plus") { sheet = .addProject(group.id) }
                                .disabled(store.isReadOnly)
                            Button("Rename group…", systemImage: "pencil") {
                                groupEditor = GroupEditorRequest(group: group)
                            }
                                .disabled(store.isReadOnly)
                            Menu("Move before") {
                                ForEach(store.document.groups.filter { $0.id != group.id }) { target in
                                    Button(target.name) { store.perform { try store.moveGroup(group.id, relativeTo: target.id) } }
                                }
                                Divider()
                                Button("Projects") { store.perform { try store.moveGroup(group.id, relativeTo: nil) } }
                            }.disabled(store.isReadOnly)
                            Divider()
                            Button("Remove group…", role: .destructive) { removingGroup = group }
                                .disabled(store.isReadOnly)
                        }
                    if !group.isCollapsed { groupProjects(group.id) }
                }
            }
            Group {
                ProjectGroupHeading(group: nil, store: store)
                    .contextMenu {
                        Button("Add project…", systemImage: "plus") { sheet = .addProject(nil) }
                            .disabled(store.isReadOnly)
                    }
                if store.document.projectsGroupCollapsed != true { groupProjects(nil) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    Button("Add project…", systemImage: "folder.badge.plus") { sheet = .addProject(store.selectedProject?.groupID) }
                    Button("New group…", systemImage: "rectangle.3.group") { newGroup() }
                } label: { Label("Add", systemImage: "plus") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.isReadOnly)
                Spacer()
                Button("Stop all projects", systemImage: "stop.fill") { store.stopAll() }
                    .labelStyle(.iconOnly).frame(width: 28, height: 28)
                    .help("Stop all tasks in all projects")
                    .disabled(!store.hasRunningTasks)
            }
            .buttonStyle(.borderless)
            .padding()
        }
        .sheet(item: $groupEditor) { request in
            GroupEditor(store: store, group: request.group, projectID: request.projectID)
        }
        .confirmationDialog("Remove this project from Taskport?", isPresented: Binding(
            get: { removingProject != nil }, set: { if !$0 { removingProject = nil } }
        ), titleVisibility: .visible) {
            Button("Remove project", role: .destructive) {
                if let project = removingProject { store.perform { try store.removeProject(project.id) } }
                removingProject = nil
            }
        } message: { Text("Its files will not be deleted. Idle terminal sessions will close.") }
        .confirmationDialog("Remove this group?", isPresented: Binding(
            get: { removingGroup != nil }, set: { if !$0 { removingGroup = nil } }
        ), titleVisibility: .visible) {
            Button("Remove group", role: .destructive) {
                if let group = removingGroup { store.perform { try store.removeGroup(group.id) } }
                removingGroup = nil
            }
        } message: { Text("Its projects move to Projects. No projects, tasks, or files are removed.") }
    }

    private func newGroup(for projectID: UUID? = nil) {
        groupEditor = GroupEditorRequest(projectID: projectID)
    }

    @ViewBuilder private func groupProjects(_ groupID: UUID?) -> some View {
        projectRows(in: groupID)
        if !store.document.projects.contains(where: { $0.groupID == groupID }) {
            Button("Add project…", systemImage: "plus") { sheet = .addProject(groupID) }
                .disabled(store.isReadOnly)
        }
    }

    private func projectRows(in groupID: UUID?) -> some View {
        let projects = store.document.projects.filter { $0.groupID == groupID }
        return ForEach(projects) { project in
            ProjectRow(project: project, store: store)
                .tag(project.id)
                .contextMenu {
                    Button("Start all", systemImage: "play.fill") { store.runAll(in: project) }
                        .disabled(store.isReadOnly || !project.tasks.contains { $0.participatesInStatus && store.session($0.id)?.phase.isActive != true })
                    Button("Stop all", systemImage: "stop.fill") { store.stopAll(in: project) }
                        .disabled(!store.hasRunningTasks(in: project))
                    Divider()
                    Menu("Open in…") {
                        ForEach(ProjectOpener.Destination.allCases, id: \.self) { destination in
                            Button(destination.rawValue) {
                                Task {
                                    do { try await ProjectOpener.open(project.directory, in: destination) }
                                    catch { store.errorMessage = error.localizedDescription }
                                }
                            }
                        }
                    }
                    Menu("Move to group") {
                        ForEach(store.document.groups) { group in
                            Button(group.name) { store.perform { try store.moveProject(project.id, toGroup: group.id) } }
                                .disabled(project.groupID == group.id)
                        }
                        Button("Projects") { store.perform { try store.moveProject(project.id, toGroup: nil) } }
                            .disabled(project.groupID == nil)
                        Divider()
                        Button("New group…", systemImage: "plus") { newGroup(for: project.id) }
                    }.disabled(store.isReadOnly)
                    Button("Edit project…") { sheet = .project(project) }.disabled(store.isReadOnly)
                    Divider()
                    Button("Remove project…", role: .destructive) { removingProject = project }.disabled(store.isReadOnly)
                }
        }
        .onMove { store.moveProjects(inGroup: groupID, from: $0, to: $1) }
        .moveDisabled(store.isReadOnly)
    }
}

private struct ProjectGroupTransfer: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "app.taskport.project-group", conformingTo: .data))
    }
}

private struct ProjectGroupHeading: View {
    let group: ProjectGroup?
    let store: WorkspaceStore
    @State private var isDropTargeted = false

    private var collapsed: Bool { group?.isCollapsed ?? (store.document.projectsGroupCollapsed == true) }

    var body: some View {
        if #available(macOS 26, *) {
            heading
                .dropDestination(for: ProjectGroupTransfer.self, isEnabled: !store.isReadOnly) { items, session in
                    _ = move(items, at: session.location)
                }
                .onDropSessionUpdated { session in
                    isDropTargeted = session.phase == .active
                }
        } else {
            heading.dropDestination(for: ProjectGroupTransfer.self, action: move, isTargeted: { isDropTargeted = $0 })
        }
    }

    private var heading: some View {
        let name = group?.name ?? "Projects"
        let count = store.document.projects.filter { $0.groupID == group?.id }.count
        return HStack(spacing: 8) {
            Button {
                store.perform { try store.setGroupCollapsed(group?.id, !collapsed) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).frame(width: 10).accessibilityHidden(true)
                    Text(name).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(count, format: .number).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(collapsed ? "Expand" : "Collapse") \(name)")
            .accessibilityLabel("\(name), \(count) projects")
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            if let group {
                Image(systemName: "line.3.horizontal")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 18, height: 32).contentShape(Rectangle())
                    .draggable(ProjectGroupTransfer(id: group.id))
                    .help("Drag to reorder \(name)")
                    .accessibilityLabel("Reorder \(name)")
            }
        }
        .font(.callout.weight(.semibold)).textCase(nil)
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 0.5) }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .disabled(store.isReadOnly)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private func move(_ items: [ProjectGroupTransfer], at location: CGPoint) -> Bool {
        guard items.count == 1, let item = items.first, !store.isReadOnly else { return false }
        do {
            try store.moveGroup(item.id, relativeTo: group?.id, after: group != nil && location.y > 20)
            return true
        } catch { store.errorMessage = error.localizedDescription; return false }
    }
}

private struct GroupEditorRequest: Identifiable {
    let id = UUID()
    var group: ProjectGroup?
    var projectID: UUID?
}

private struct GroupEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let group: ProjectGroup?
    let projectID: UUID?
    @State private var name: String
    @State private var error: String?
    @FocusState private var focusName: Bool

    init(store: WorkspaceStore, group: ProjectGroup?, projectID: UUID?) {
        self.store = store
        self.group = group
        self.projectID = projectID
        _name = State(initialValue: group?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(group == nil ? "New group" : "Rename group").font(.title2).bold()
            if let project = store.document.projects.first(where: { $0.id == projectID }) {
                Text("Moves “\(project.name)” into the new group.").font(.callout).foregroundStyle(.secondary)
            }
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .accessibilityLabel("Group name").focused($focusName)
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(group == nil ? "Create group" : "Save") {
                    do { try store.saveGroup(name: name, replacing: group, assigning: projectID); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isReadOnly || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 380)
        .onAppear { focusName = true }
    }
}

private struct ProjectRow: View {
    let project: Project
    let store: WorkspaceStore
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: project.iconName ?? "folder").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).lineLimit(1)
                let ports = store.listeningPorts[project.id] ?? []
                Text(ListeningPorts.label(ports))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(ports.isEmpty ? "No listening TCP ports detected" : ListeningPorts.label(ports))
                    .accessibilityLabel(ports.isEmpty ? "No listening TCP ports" : "Listening ports: \(ports.map(String.init).joined(separator: ", "))")
            }
            Spacer(minLength: 4)
            if project.tasks.contains(where: { $0.sourceKey == "builtin:cloudflare" && store.session($0.id)?.phase == .running }) {
                Image(systemName: "network")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Tunnel running").accessibilityLabel("Tunnel running")
            }
            Button {
                if store.status(of: project) == .running { store.stopAll(in: project) }
                else { store.runAll(in: project) }
            } label: {
                Image(systemName: store.status(of: project) == .running ? "stop.fill" : "play.fill")
                    .foregroundStyle(statusColor)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(store.status(of: project) == .running ? "Stop all" : "Start all pinned tasks")
            .accessibilityLabel("\(store.status(of: project) == .running ? "Stop all tasks in" : "Start all pinned tasks in") \(project.name)")
            .disabled(store.isReadOnly || !project.tasks.contains(where: \.participatesInStatus))
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }
    private var statusColor: Color {
        switch store.status(of: project) { case .stopped: .gray; case .partial: .yellow; case .running: .green }
    }
}
