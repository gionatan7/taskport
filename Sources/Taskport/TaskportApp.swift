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
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { appDelegate.updates.checkForUpdates() }
                    .disabled(!appDelegate.updates.canCheck)
            }
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
        Settings { TaskportSettings(store: appDelegate.store, updates: appDelegate.updates) }
    }
}

@MainActor
final class TaskportAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store: WorkspaceStore
    lazy var updates = AppUpdates(store: store)
    private var startupError: String?
    private var updateHandoffID: UUID?
    private weak var window: NSWindow?
    private var quitting = false
    private var controlServer: ControlServer?
    private var cliHandoffID: UUID?
    private var cliQuitReady = false
    private var shutdownError: String?

    override init() {
        do {
            if CommandLine.arguments.contains("--restore-session") { store = WorkspaceStore(directory: ControlPaths.directory) }
            else {
                let launch = try UpdateWorkspace.resolveLaunch(fallback: ControlPaths.directory,
                    explicitDirectory: ProcessInfo.processInfo.environment["TASKPORT_DATA_DIR"],
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                    processID: ProcessInfo.processInfo.processIdentifier)
                store = WorkspaceStore(directory: launch.directory)
                updateHandoffID = launch.handoffID
            }
        } catch {
            store = WorkspaceStore()
            startupError = error.localizedDescription
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSApp.windows.first { $0.canBecomeMain }
        window?.delegate = self
        window?.autorecalculatesKeyViewLoop = true
        window?.isMovableByWindowBackground = true
        showWindow()
        if let startupError { store.blockWrites("Update restore unavailable: \(startupError)"); return }
        do {
            let server = ControlServer(directory: store.persistence.directory)
            try server.start(afterResponse: { [weak self] request, response, sent in
                self?.controlResponseSent(request, response: response, sent: sent)
            }) { [weak self] request in
                guard let self else { return .failure("Taskport is unavailable.") }
                if request.operation.hasPrefix("app.") { return self.handleLifecycle(request) }
                guard !self.quitting else { return .failure("Taskport is shutting down.") }
                guard !self.store.restoreInProgress || ["status", "tasks.list", "sessions.list", "tasks.logs"].contains(request.operation) else {
                    return .failure("Session restore is in progress. Inspect restore status before changing tasks.")
                }
                return WorkspaceControl(store: self.store).handle(request)
            }
            controlServer = server
            let arguments = CommandLine.arguments
            if let index = arguments.firstIndex(of: "--restore-session") {
                guard index + 1 < arguments.count, let id = UUID(uuidString: arguments[index + 1]) else {
                    store.errorMessage = "Invalid restore session ID. No tasks were started."
                    return
                }
                store.resumePinnedTasks(restoring: id)
            } else {
                let id = try updateHandoffID ?? SessionHandoff.restoreAfterUpdate(in: store.persistence.directory,
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                    processID: ProcessInfo.processInfo.processIdentifier)
                store.resumePinnedTasks(restoring: id)
            }
            updates.start()
        } catch { store.blockWrites("Workspace control unavailable: \(error.localizedDescription)") }
    }
    func applicationWillTerminate(_ notification: Notification) { controlServer?.stop() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if cliQuitReady { return .terminateNow }
        guard !quitting else { return .terminateCancel }
        guard !store.restoreInProgress else { store.errorMessage = "Wait for session restore to finish before quitting."; return .terminateCancel }
        if let update = updates.installation {
            return updates.prepareTermination(for: update) { sender.reply(toApplicationShouldTerminate: $0) }
        }
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

    private func handleLifecycle(_ request: ControlRequest) -> ControlResponse {
        do {
            guard request.projectID == nil, request.groupID == nil, request.taskIDs.isEmpty else { throw ControlError("Unexpected lifecycle selection.") }
            if request.operation == "app.restore-status" {
                guard request.values.isEmpty, request.flags.isEmpty else { throw ControlError("Unexpected restore-status option.") }
                var response = ControlResponse()
                response.handoffID = store.restoreID
                response.state = store.restoreInProgress ? "restoring" : store.restoreError != nil ? "failed" : store.restoreID == nil ? "not_restored" : "restored"
                response.results = store.restoreResults
                response.error = store.restoreError
                response.ok = store.restoreError == nil && store.restoreResults.allSatisfy { $0.outcome != "failed" }
                return response
            }
            if request.operation == "app.quit-status" {
                guard request.values.isEmpty, request.flags.isEmpty else { throw ControlError("Unexpected quit-status option.") }
                var response = ControlResponse()
                response.handoffID = cliHandoffID
                response.state = quitting ? "quitting" : "running"
                response.error = shutdownError
                response.ok = shutdownError == nil
                return response
            }
            guard request.operation == "app.quit", !quitting, !store.restoreInProgress, updates.installation == nil,
                  Set(request.values.keys) == ["handoff-id"], let value = request.values["handoff-id"], let id = UUID(uuidString: value),
                  request.flags.isSubset(of: ["include-one-offs", "include-tunnels"]) else {
                throw ControlError("Unsupported lifecycle request, or a restart/restore is already in progress.")
            }
            let handoff = try store.saveSessionHandoff(id: id,
                includeOneOffs: request.flags.contains("include-one-offs"), includeTunnels: request.flags.contains("include-tunnels"))
            cliHandoffID = id
            shutdownError = nil
            quitting = true
            var response = ControlResponse()
            response.handoffID = id
            response.processID = handoff.sourceProcessID
            response.state = "quit_requested"
            response.results = handoff.skipped
            return response
        } catch { return .failure(error.localizedDescription) }
    }

    /// Never terminate before the socket worker has sent the saved-session acknowledgement.
    private func controlResponseSent(_ request: ControlRequest, response: ControlResponse, sent: Bool) {
        guard request.operation == "app.quit", response.ok, response.handoffID == cliHandoffID else { return }
        guard sent else {
            try? SessionHandoff.discard(in: store.persistence.directory)
            quitting = false; cliHandoffID = nil; store.cancelQuit()
            return
        }
        store.terminateAll()
        Task { @MainActor in
            for _ in 0..<400 {
                if store.openShellCount == 0 { cliQuitReady = true; NSApp.terminate(nil); return }
                try? await Task.sleep(for: .milliseconds(25))
            }
            quitting = false
            shutdownError = "Some terminal sessions haven't stopped. The app was not quit or relaunched. Inspect them before retrying."
            try? SessionHandoff.discard(in: store.persistence.directory)
            store.cancelQuit()
            store.errorMessage = shutdownError
        }
    }
}
