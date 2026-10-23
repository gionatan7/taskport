import GhosttyTerminal
import SwiftUI

enum WorkspaceSheet: Identifiable {
    case addProject(UUID?), project(Project), task(UUID, ProjectTask, isNew: Bool = false), imports(UUID, TaskImport)
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
    @State private var sidebarWidth: CGFloat = 230

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(store: store, sheet: $sheet)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                // Keep the reopening target at the user's width, not the initial default.
                if (190...360).contains(width), abs(width - sidebarWidth) > 0.5 { sidebarWidth = width }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: sidebarWidth, max: 360)
            .navigationTitle("Taskport")
        } detail: {
            VStack(spacing: 0) {
                if let project = store.selectedProject, !store.visibleTasks(in: project).isEmpty {
                    TaskTabBar(project: project, store: store)
                    Divider()
                }
                TerminalDeck(store: store, addProject: { sheet = .addProject(nil) }, addTask: addTask)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(.bar, ignoresSafeAreaEdges: .top)
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
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task {
            while !Task.isCancelled {
                await store.refreshListeningPorts()
                do { try await Task.sleep(for: .seconds(2)) }
                catch { break }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .addProject(let groupID): ProjectEditor(store: store, groupID: groupID)
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
        .onReceive(NotificationCenter.default.publisher(for: .taskportAddProject)) { _ in sheet = .addProject(store.selectedProject?.groupID) }
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
