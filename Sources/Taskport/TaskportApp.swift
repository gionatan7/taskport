import AppKit
import SwiftUI
import TaskportControl

extension Notification.Name {
    static let taskportAddProject = Notification.Name("taskport.addProject")
    static let taskportAddTask = Notification.Name("taskport.addTask")
}

@main
struct TaskportApp: App {
    @NSApplicationDelegateAdaptor(TaskportAppDelegate.self) private var appDelegate
    var body: some Scene {
        Window("Taskport", id: "workspace") {
            WorkspaceView(store: appDelegate.store).frame(minWidth: 850, minHeight: 540)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add project…") { NotificationCenter.default.post(name: .taskportAddProject, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New task…") { NotificationCenter.default.post(name: .taskportAddTask, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(appDelegate.store.selectedProject == nil)
            }
            CommandMenu("Tasks") {
                Button("Run all pinned tasks") {
                    if let project = appDelegate.store.selectedProject { appDelegate.store.runAll(in: project) }
                }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(appDelegate.store.selectedProject == nil)
                Button("Stop all running tasks") { appDelegate.store.stopAll() }
                    .disabled(!appDelegate.store.hasRunningTasks)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Show Taskport") { appDelegate.showWindow() }.keyboardShortcut("0", modifiers: .command)
            }
        }
        Settings { CommandLineSettings(store: appDelegate.store) }
    }
}

@MainActor
final class TaskportAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = WorkspaceStore()
    private weak var window: NSWindow?
    private var quitting = false
    private var controlServer: ControlServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSApp.windows.first { $0.canBecomeMain }
        window?.delegate = self
        window?.autorecalculatesKeyViewLoop = true
        showWindow()
        do {
            let server = ControlServer(directory: store.persistence.directory)
            try server.start { [weak self] request in
                guard let self, !self.quitting else { return .failure("Taskport is shutting down.") }
                return WorkspaceControl(store: self.store).handle(request)
            }
            controlServer = server
            store.resumePinnedTasks()
        } catch { store.blockWrites("Workspace control unavailable: \(error.localizedDescription)") }
    }
    func applicationWillTerminate(_ notification: Notification) { controlServer?.stop() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateCancel }
        guard store.openShellCount > 0 else { return .terminateNow }
        showWindow()
        let alert = NSAlert()
        alert.messageText = "Quit and close all terminals?"
        let resumeNotice = store.resumeTasksOnLaunch
            ? "Pinned tasks that are running will resume next time you open Taskport. One-offs, temporary tasks, and tunnels will not resume."
            : "Automatic task resume is off. No tasks will start next time you open Taskport."
        alert.informativeText = "\(store.activeCount) tasks are active. All terminals will stop. \(resumeNotice)"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit and stop")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        quitting = true
        store.prepareToQuit()
        store.terminateAll()
        Task { @MainActor in
            for _ in 0..<80 {
                if store.openShellCount == 0 { sender.reply(toApplicationShouldTerminate: true); return }
                try? await Task.sleep(for: .milliseconds(25))
            }
            quitting = false
            store.cancelQuit()
            store.errorMessage = "Some terminal sessions haven't stopped. Check them before quitting again."
            sender.reply(toApplicationShouldTerminate: false)
        }
        return .terminateLater
    }
}
