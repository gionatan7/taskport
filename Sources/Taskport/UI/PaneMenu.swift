import SwiftUI

struct PaneMenu: View {
    let project: Project
    let store: WorkspaceStore

    var body: some View {
        Menu {
            if project.split != nil {
                Button("Single pane", systemImage: "rectangle") { store.perform { try store.setSplit(projectID: project.id, taskID: nil) } }
                Divider()
            }
            ForEach(PaneAxis.allCases, id: \.self) { axis in
                Menu(axis == .sideBySide ? "Split side by side" : "Split top and bottom") {
                    ForEach(project.tasks.filter { $0.id != project.selectedTaskID }) { task in
                        Button(task.definition.name) {
                            store.perform { try store.setSplit(projectID: project.id, taskID: task.id, axis: axis) }
                        }
                    }
                }
            }
        } label: { Label("Terminal panes", systemImage: "rectangle.split.2x1") }
        .labelStyle(.iconOnly)
        .help("Show another task in a resizable pane; this does not start it")
        .disabled(project.tasks.count < 2 || project.selectedTaskID == nil)
    }
}
