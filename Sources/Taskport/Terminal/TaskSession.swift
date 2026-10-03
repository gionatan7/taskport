import AppKit
import GhosttyTerminal
import Observation

enum RunPhase: Equatable {
    case stopped, starting, running, stopping, exited(Int32), failed(String)
    var isActive: Bool {
        switch self { case .starting, .running, .stopping: true; default: false }
    }
    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .exited(let code): code == 0 ? "Completed" : "Exited \(code)"
        case .failed(let message): message
        }
    }
}

/// A persistent Ghostty surface backed by one owned PTY, with explicit shell events.
@MainActor @Observable
final class TaskSession: Identifiable {
    let id: UUID
    let projectID: UUID
    let terminal: TerminalViewState
    private(set) var phase: RunPhase = .stopped {
        didSet { if phase != oldValue { onPhaseChange?() } }
    }
    @ObservationIgnored var onPhaseChange: (() -> Void)?
    @ObservationIgnored var onRemoteURL: ((URL) -> Void)?
    private(set) var shellReady = false
    private(set) var manualCommandRunning = false
    private(set) var hasPendingInput = false
    private(set) var lastOutputAt = Date.distantPast
    private(set) var shellPID: Int32 = 0
    private(set) var remoteURL: URL?
    private(set) var stopWasRequested = false
    @ObservationIgnored private var process: PTYProcess?
    @ObservationIgnored private var bridge: InMemoryTerminalSession!
    @ObservationIgnored private var lastViewport: InMemoryTerminalViewport?
    @ObservationIgnored private var parser: ShellEvents
    @ObservationIgnored private var pendingTask: (ProjectTask, String)?
    @ObservationIgnored private var token = UUID().uuidString
    @ObservationIgnored private let bootstrapDirectory: URL
    @ObservationIgnored private var hasSeenPrompt = false
    @ObservationIgnored private var startingAt = Date.distantPast
    @ObservationIgnored private var tunnelReadiness = TunnelReadiness()
    @ObservationIgnored private let pasteConfirmation: TerminalPasteConfirmation
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored private var preservePhaseOnExit = false
    @ObservationIgnored private var isTunnel = false
    @ObservationIgnored var onShellExit: (() -> Void)?

    init(taskID: UUID, projectID: UUID, dataDirectory: URL,
         pasteConfirmation: TerminalPasteConfirmation = TerminalPasteConfirmation()) {
        id = taskID
        self.projectID = projectID
        self.pasteConfirmation = pasteConfirmation
        bootstrapDirectory = dataDirectory.appendingPathComponent("sessions/\(taskID.uuidString)")
        parser = ShellEvents(token: token)
        let appearance = LocalTerminalAppearance.load(home: FileManager.default.homeDirectoryForCurrentUser,
            environment: ProcessInfo.processInfo.environment,
            ghosttyApplication: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty"))
        terminal = TerminalViewState(configSource: .generated(appearance), theme: .init())
        terminal.makePlatformView = { [weak self] in
            let view = TaskTerminalView(frame: .zero)
            view.onDetach = { [weak self] in self?.pasteConfirmation.cancel() }
            return view
        }
        terminal.onClipboardConfirmationRequest = { [weak self] request in
            guard let self else { request.respond(allow: false); return }
            let view = self.terminal.attachedPlatformView
            let window = view?.window
            let surface = self.terminal.surface
            self.pasteConfirmation.request(kind: request.kind, window: window, isValid: { [weak self, weak view, weak window, weak surface] in
                guard let self, let view, let window, let surface else { return false }
                return self.process != nil && !self.isTerminating && self.terminal.attachedPlatformView === view
                    && self.terminal.surface === surface && view.window === window
                    && window.isVisible && self.terminal.isSurfaceVisible
            }, respond: { request.respond(allow: $0) })
        }
        bridge = InMemoryTerminalSession(write: { [weak self] data in
            Task { @MainActor in self?.userInput(data) }
        }, resize: { [weak self] viewport in
            Task { @MainActor in
                guard let self, viewport.columns > 0, viewport.rows > 0 else { return }
                self.lastViewport = viewport
                self.process?.resize(columns: Int(viewport.columns), rows: Int(viewport.rows))
            }
        })
        terminal.configuration = TerminalSurfaceOptions(backend: .inMemory(bridge))
    }

    var canStart: Bool { !isTerminating && !phase.isActive && !manualCommandRunning && !hasPendingInput }

    func start(task: ProjectTask, directory: String, focus: Bool = true) throws {
        guard !isTerminating else { throw WorkspaceError("This terminal's previous shell is still closing. Try again when it has stopped.") }
        guard !phase.isActive else { return }
        guard canStart else { throw WorkspaceError("This terminal is in use. Finish the command or press Ctrl-C to clear the prompt before starting the task.") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError("The task's working directory is unavailable. Edit the task or reconnect the folder.")
        }
        stopWasRequested = false
        isTerminating = false
        phase = .starting
        isTunnel = task.sourceKey == "builtin:cloudflare"
        remoteURL = nil
        tunnelReadiness = TunnelReadiness()
        startingAt = Date()
        pendingTask = (task, directory)
        if process == nil { try openShell(directory: directory) }
        else if shellReady { sendPendingTask() }
        if focus { terminal.requestFocus() }
        // A broken startup file must not leave a task indefinitely marked as starting.
        let requestTime = startingAt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.startingAt == requestTime, self.phase == .starting else { return }
            self.pendingTask = nil
            self.phase = .failed("Shell startup needs attention")
        }
    }

    func stop(includeManual: Bool = false, focus: Bool = true) {
        guard phase != .stopping else { return }
        pendingTask = nil
        guard phase.isActive || (includeManual && manualCommandRunning) else { return }
        pasteConfirmation.cancel()
        stopWasRequested = true
        if phase.isActive { phase = .stopping }
        process?.interrupt()
        if focus { terminal.requestFocus() }
    }

    func terminate() {
        isTerminating = true
        pasteConfirmation.cancel()
        pendingTask = nil
        // Closing an idle shell to change cwd is maintenance, not task dismissal.
        if !preservePhaseOnExit { stopWasRequested = true }
        if phase.isActive { phase = .stopping }
        process?.terminate()
    }

    /// Drop the old cwd/environment without discarding output or a failed task's state.
    func resetIdleShell() {
        guard canStart, shellReady, shellPID > 0 else { return }
        preservePhaseOnExit = true
        terminate()
    }

    private func openShell(directory: String) throws {
        do {
            try ShellBootstrap.prepare(in: bootstrapDirectory)
            token = UUID().uuidString
            parser = ShellEvents(token: token)
            var environment = ProcessInfo.processInfo.environment
            environment["TASKPORT_USER_ZDOTDIR"] = environment["ZDOTDIR"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            environment["TASKPORT_BOOTSTRAP_DIR"] = bootstrapDirectory.path
            environment["ZDOTDIR"] = bootstrapDirectory.path
            environment["TASKPORT_SESSION_TOKEN"] = token
            environment["TERM"] = "xterm-256color"
            environment["COLORTERM"] = "truecolor"
            environment["TERM_PROGRAM"] = "ghostty"
            let shell = PTYProcess()
            shell.onOutput = { [weak self] in self?.receive($0) }
            shell.onExit = { [weak self] in self?.didExit($0) }
            try shell.start(directory: directory, arguments: ["/bin/zsh", "-il"], environment: environment)
            // The retained Ghostty bridge won't repeat an unchanged resize for a new PTY.
            if let viewport = lastViewport {
                shell.resize(columns: Int(viewport.columns), rows: Int(viewport.rows))
            }
            process = shell
            shellPID = shell.pid
            hasSeenPrompt = false
        } catch {
            phase = .failed("Couldn't start the shell")
            pendingTask = nil
            throw error
        }
    }

    private func sendPendingTask() {
        guard let (task, directory) = pendingTask, shellReady else { return }
        pendingTask = nil
        do {
            let command = try ShellBootstrap.writeTask(task.definition, directory: directory,
                to: bootstrapDirectory.appendingPathComponent("task.zsh"))
            shellReady = false
            process?.write(Data(command.utf8))
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func userInput(_ data: Data) {
        guard let process else { return }
        if phase.isActive, data.contains(3) { stopWasRequested = true }
        // Never paste a managed command over a user's unfinished input.
        if shellReady, !phase.isActive {
            hasPendingInput = !data.contains(3)
        }
        process.write(data)
    }

    private func receive(_ data: Data) {
        let parsed = parser.consume(data)
        if !parsed.output.isEmpty {
            bridge.receive(parsed.output)
            if Date().timeIntervalSince(lastOutputAt) > 0.25 { lastOutputAt = Date() }
            if isTunnel, remoteURL == nil {
                if let url = tunnelReadiness.consume(parsed.output) {
                    remoteURL = url
                    onRemoteURL?(url)
                }
            }
        }
        for event in parsed.events {
            switch event {
            case .busy:
                shellReady = false
                hasPendingInput = false
                if phase == .starting { phase = .running }
                else if !phase.isActive { manualCommandRunning = true }
            case .ready(let code):
                // Approval aimed at a finished program must not reach the returned shell.
                if phase.isActive || manualCommandRunning { pasteConfirmation.cancel() }
                let initial = !hasSeenPrompt
                hasSeenPrompt = true
                shellReady = true
                manualCommandRunning = false
                hasPendingInput = false
                if initial, pendingTask != nil { sendPendingTask() }
                else if phase.isActive {
                    phase = .exited(code)
                    try? FileManager.default.removeItem(at: bootstrapDirectory.appendingPathComponent("task.zsh"))
                }
            }
        }
    }

    private func didExit(_ code: Int32) {
        pasteConfirmation.cancel()
        process = nil
        shellPID = 0
        isTerminating = false
        shellReady = false
        manualCommandRunning = false
        hasPendingInput = false
        pendingTask = nil
        if !preservePhaseOnExit { phase = .exited(code) }
        preservePhaseOnExit = false
        bridge.receive("\r\n[Shell closed · exit \(code)]\r\n")
        try? FileManager.default.removeItem(at: bootstrapDirectory)
        onShellExit?()
        onShellExit = nil
    }
}
