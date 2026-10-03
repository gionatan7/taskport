import GhosttyTerminal
import SwiftUI

enum WorkspaceSheet: Identifiable {
    case addProject, project(Project), task(UUID, ProjectTask, isNew: Bool = false), imports(UUID, TaskImport)
    var id: String {
        switch self {
        case .addProject: "add-project"
        case .project(let project): "project-\(project.id)"
        case .task(_, let task, _): "task-\(task.id)"
        case .imports(_, let result): "import-\(result.id)"
        }
    }
}

struct WorkspaceView: View {
    @Bindable var store: WorkspaceStore
    @State private var sheet: WorkspaceSheet?
    @State private var showTasks = false
    @State private var pendingEdit: ProjectTask?
    @State private var showOverrideNotice = false
    @State private var removingProject: Project?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { store.document.selectedProjectID }, set: store.selectProject)) {
                Section("Projects") {
                    ForEach(store.document.projects) { project in
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
                                Button("Edit project…") { sheet = .project(project) }
                                Divider()
                                Button("Remove project…", role: .destructive) { removingProject = project }
                            }
                    }
                    .onMove(perform: store.moveProjects)
                    .moveDisabled(store.isReadOnly)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Add project", systemImage: "plus") { sheet = .addProject }
                        .disabled(store.isReadOnly)
                    Spacer()
                    Button("Stop all projects", systemImage: "stop.fill") { store.stopAll() }
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                        .help("Stop all tasks in all projects")
                        .disabled(!store.hasRunningTasks)
                }
                .buttonStyle(.borderless)
                .padding()
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 360)
            .navigationTitle("Taskport")
        } detail: {
            VStack(spacing: 0) {
                if let project = store.selectedProject, !store.visibleTasks(in: project).isEmpty {
                    TaskTabBar(project: project, store: store)
                    Divider()
                }
                TerminalDeck(store: store, addProject: { sheet = .addProject }, addTask: addTask)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .top) { TunnelCopyToast(store: store) }
            .navigationTitle(store.selectedProject?.name ?? "Taskport")
            .toolbar {
                if let project = store.selectedProject {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Run all", systemImage: "play.fill") { store.runAll(in: project) }
                            .labelStyle(.titleAndIcon)
                            .help("Start pinned long-running tasks")
                            .disabled(!project.tasks.contains { $0.participatesInStatus && store.session($0.id)?.phase.isActive != true })
                        Button("Tasks", systemImage: "list.bullet") { showTasks.toggle() }
                            .labelStyle(.titleAndIcon)
                            .popover(isPresented: $showTasks, arrowEdge: .bottom) {
                                TaskPicker(project: project, store: store, select: { task in
                                    showTasks = false
                                    store.perform { try store.openTask(task.id, projectID: project.id) }
                                }, edit: editTask, importTasks: importTasks)
                            }
                        Button("Stop all", systemImage: "stop.fill") { store.stopAll(in: project) }
                            .labelStyle(.titleAndIcon)
                            .help("Interrupt all running tasks and terminal commands in this project")
                            .disabled(!store.hasRunningTasks(in: project))
                        Button("New task", systemImage: "plus", action: addTask)
                            .labelStyle(.iconOnly)
                            .help("New task")
                        ProjectLinks(project: project, store: store)
                        PaneMenu(project: project, store: store)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            while !Task.isCancelled {
                await store.refreshListeningPorts()
                do { try await Task.sleep(for: .seconds(2)) }
                catch { break }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .addProject: ProjectEditor(store: store)
            case .project(let project): ProjectEditor(store: store, project: project)
            case .task(let projectID, let task, let isNew): TaskEditor(store: store, projectID: projectID, task: task, isNew: isNew)
            case .imports(let projectID, let result): ImportReview(store: store, projectID: projectID, result: result)
            }
        }
        .alert("Edit a local copy?", isPresented: $showOverrideNotice) {
            Button("Cancel", role: .cancel) { pendingEdit = nil }
            Button("Continue editing") {
                if let project = store.selectedProject, let task = pendingEdit { sheet = .task(project.id, task) }
                pendingEdit = nil
            }
        } message: {
            Text("Only Taskport's copy will change. The project's original task file stays untouched. Modified tasks show “Local override”.")
        }
        .alert("Taskport", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Dismiss", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("Remove this project from Taskport?", isPresented: Binding(
            get: { removingProject != nil }, set: { if !$0 { removingProject = nil } }
        ), titleVisibility: .visible) {
            Button("Remove project", role: .destructive) {
                if let project = removingProject { store.perform { try store.removeProject(project.id) } }
                removingProject = nil
            }
        } message: { Text("Its files will not be deleted. Idle terminal sessions will close.") }
        .onReceive(NotificationCenter.default.publisher(for: .taskportAddProject)) { _ in sheet = .addProject }
        .onReceive(NotificationCenter.default.publisher(for: .taskportAddTask)) { _ in addTask() }
    }

    private func addTask() {
        guard let project = store.selectedProject else { return }
        sheet = .task(project.id, ProjectTask(definition: TaskDefinition(), pinned: true), isNew: true)
    }
    private func editTask(_ task: ProjectTask) {
        showTasks = false
        guard let project = store.selectedProject else { return }
        if task.importedDefinition != nil, !task.isOverridden {
            pendingEdit = task
            showOverrideNotice = true
        } else { sheet = .task(project.id, task) }
    }
    private func importTasks() {
        showTasks = false
        guard let project = store.selectedProject else { return }
        store.perform {
            sheet = .imports(project.id, try TaskImporter.discover(in: URL(fileURLWithPath: project.directory)))
        }
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Tunnel running")
                    .accessibilityLabel("Tunnel running")
            }
            Button {
                if store.status(of: project) == .running { store.stopAll(in: project) }
                else { store.runAll(in: project) }
            } label: {
                Image(systemName: store.status(of: project) == .running ? "stop.fill" : "play.fill")
                    .foregroundStyle(statusColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
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

private struct TerminalDeck: View {
    let store: WorkspaceStore
    let addProject: () -> Void
    let addTask: () -> Void
    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let project = store.selectedProject {
                if project.selectedTaskID == nil {
                    ContentUnavailableView {
                        Label("Choose a task", systemImage: "terminal")
                    } description: {
                        Text("Open Tasks to import or select a command, or add your own.")
                    } actions: { Button("New task", systemImage: "plus", action: addTask) }
                }
            } else {
                ContentUnavailableView {
                    Label("A home for your project tasks", systemImage: "terminal")
                } description: {
                    Text("Add a project folder, define its tasks, and keep your terminals together.")
                } actions: {
                    Button("Add project", systemImage: "plus", action: addProject).buttonStyle(.borderedProminent)
                }
            }
            NativeTerminalDeck(store: store)
                .allowsHitTesting(store.selectedTaskID != nil)
        }
    }
}
