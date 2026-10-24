import AppKit
import Observation
import Sparkle
import TaskportControl

struct UpdateRestartSummary {
    let version: String
    let taskIDs: Set<UUID>
    let oneOffCount: Int
    let tunnelCount: Int
}

struct UpdateRestartApproval {
    var includeOneOffs = false
    var includeTunnels = false
}

struct PendingAppUpdate: Equatable {
    let build: String
    let version: String
}

/// Sparkle owns verification/replacement; Taskport owns consent and the terminal handoff.
@MainActor @Observable
final class AppUpdates: NSObject, SPUUpdaterDelegate {
    private(set) var canCheck = false
    private(set) var installation: PendingAppUpdate?
    private(set) var isPreparingInstallation = false
    var checksAutomatically = false {
        didSet {
            if updaterInstance?.automaticallyChecksForUpdates != checksAutomatically {
                updaterInstance?.automaticallyChecksForUpdates = checksAutomatically
            }
        }
    }
    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private let approval: @MainActor (UpdateRestartSummary) -> UpdateRestartApproval?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updaterInstance: SPUUpdater?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var handoffID: UUID?

    init(store: WorkspaceStore, defaults: UserDefaults = .standard,
         approval: @escaping @MainActor (UpdateRestartSummary) -> UpdateRestartApproval? = AppUpdates.confirmRestart) {
        self.store = store
        self.defaults = defaults
        self.approval = approval
        super.init()
    }

    func start() {
        guard updaterInstance == nil, !store.isReadOnly else { return }
        let driver = TaskportUpdateDriver(hostBundle: .main, delegate: nil)
        driver.authorize = { [weak self] update in self?.authorizeInstallation(update) ?? false }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        updaterInstance = updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canCheck = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.checksAutomatically = value }
            }
        ]
        do { try updater.start() }
        catch { store.errorMessage = "Couldn't start the updater. \(error.localizedDescription)" }
    }

    func checkForUpdates() { updaterInstance?.checkForUpdates() }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !store.shutdownInProgress, !store.restoreInProgress else {
            throw WorkspaceError("Wait for Taskport's restart or restore to finish before checking for updates.")
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installation = nil
        if !isPreparingInstallation, let id = handoffID {
            try? SessionHandoff.discard(in: store.persistence.directory)
            UpdateWorkspace.discard(handoffID: id, defaults: defaults)
            handoffID = nil
            store.cancelQuit()
        }
    }

    /// Return false to cancel Sparkle's prepared installation, not merely veto the app's Quit event.
    func authorizeInstallation(_ update: PendingAppUpdate) -> Bool {
        guard installation == nil, !store.shutdownInProgress, !store.restoreInProgress else { return false }
        do {
            let active = store.sessions.filter { $0.phase == .running || $0.phase == .starting }
            let tasks = store.document.projects.flatMap(\.tasks).filter { task in active.contains { $0.id == task.id } }
            let summary = UpdateRestartSummary(version: update.version, taskIDs: Set(active.map(\.id)),
                oneOffCount: tasks.filter { $0.definition.kind == .oneOff }.count, tunnelCount: tasks.filter(\.isTunnel).count)
            guard let choice = approval(summary) else { return false }
            guard Set(store.sessions.filter { $0.phase == .running || $0.phase == .starting }.map(\.id)) == summary.taskIDs else {
                throw WorkspaceError("Running tasks changed while the update confirmation was open. Review the update again.")
            }
            let saved = try store.saveSessionHandoff(id: UUID(), includeOneOffs: choice.includeOneOffs,
                includeTunnels: choice.includeTunnels, updateBuild: update.build)
            handoffID = saved.id
            try UpdateWorkspace.save(directory: store.persistence.directory, handoffID: saved.id, defaults: defaults)
            installation = update
            return true
        } catch {
            if let id = handoffID {
                try? SessionHandoff.discard(in: store.persistence.directory)
                UpdateWorkspace.discard(handoffID: id, defaults: defaults)
                handoffID = nil
                store.cancelQuit()
            }
            store.errorMessage = error.localizedDescription
            return false
        }
    }

    /// Consent and the checkpoint are already secured before Sparkle requests termination.
    func prepareTermination(for update: PendingAppUpdate, timeout: Duration = .seconds(10),
                            reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        guard !isPreparingInstallation, installation == update, let id = handoffID else { return .terminateCancel }
        isPreparingInstallation = true
        store.terminateAll()
        Task { @MainActor in
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                if store.openShellCount == 0 {
                    if installation == update { reply(true) }
                    else {
                        // If installation aborts before termination, recover once in the old app.
                        handoffID = nil
                        isPreparingInstallation = false
                        store.cancelQuit()
                        store.restoreSession(id, updateDefaults: defaults)
                        reply(false)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            isPreparingInstallation = false
            if installation == update {
                // Sparkle can retry Quit. Keep the original approval and frozen snapshot,
                // including temporary tasks whose terminals have already stopped.
                store.errorMessage = "Some terminals haven't stopped. The update is still pending; inspect them, then try quitting again to finish the update."
            } else {
                try? SessionHandoff.discard(in: store.persistence.directory)
                UpdateWorkspace.discard(handoffID: id, defaults: defaults)
                handoffID = nil
                store.cancelQuit()
                store.errorMessage = "The update was cancelled while terminals were stopping. Inspect them before retrying."
            }
            reply(false)
        }
        return .terminateLater
    }

    private static func confirmRestart(_ summary: UpdateRestartSummary) -> UpdateRestartApproval? {
        let alert = NSAlert()
        alert.messageText = "Install Taskport \(summary.version) and restart?"
        alert.informativeText = "\(summary.taskIDs.count) running tasks will restart as new processes, including unpinned and temporary services. Terminal history and manual input are not restored."
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Install and restart")
        let oneOffs = NSButton(checkboxWithTitle: "Restart \(summary.oneOffCount) one-off tasks from the beginning", target: nil, action: nil)
        let tunnels = NSButton(checkboxWithTitle: "Restart \(summary.tunnelCount) public tunnels (links may change)", target: nil, action: nil)
        let options = NSStackView()
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 10
        if summary.oneOffCount > 0 { options.addArrangedSubview(oneOffs) }
        if summary.tunnelCount > 0 { options.addArrangedSubview(tunnels) }
        if !options.arrangedSubviews.isEmpty {
            options.frame.size = NSSize(width: 420, height: options.fittingSize.height)
            alert.accessoryView = options
        }
        guard alert.runModal() == .alertSecondButtonReturn else { return nil }
        return .init(includeOneOffs: oneOffs.state == .on, includeTunnels: tunnels.state == .on)
    }
}

/// Keep Sparkle's native UI, replacing only its final confirmation with Taskport's restart consent.
@MainActor
final class TaskportUpdateDriver: SPUStandardUserDriver {
    var authorize: ((PendingAppUpdate) -> Bool)?
    private var update: PendingAppUpdate?

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let update = PendingAppUpdate(build: appcastItem.versionString, version: appcastItem.displayVersionString)
        self.update = update
        super.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
            if choice == .install, state.stage == .installing {
                reply(self?.authorize?(update) == true ? .install : .skip)
            } else { reply(choice) }
        }
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // At this stage .dismiss may still install on quit. .skip cancels without skipping the version.
        reply(update.flatMap { authorize?($0) } == true ? .install : .skip)
    }
}
