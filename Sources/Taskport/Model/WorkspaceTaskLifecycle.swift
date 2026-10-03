import AppKit

extension WorkspaceStore {
    func tunnel(for taskID: UUID, in project: Project) -> ProjectTask? {
        project.tasks.first { $0.isTunnel && $0.tunnelForTaskID == taskID }
    }

    /// A separate terminal per server, after explicit confirmation of the exposed URL.
    func startTunnel(for taskID: UUID, projectID: UUID, confirmedURL: String, activate: Bool = true) throws {
        guard let project = document.projects.first(where: { $0.id == projectID }),
              let owner = project.tasks.first(where: { $0.id == taskID && !$0.isTunnel }) else {
            throw WorkspaceError("The linked task no longer exists.")
        }
        let address = try LocalAddress.validate(owner.localURL ?? "")
        guard !address.isEmpty else { throw WorkspaceError("Set the task's local URL first.") }
        guard address == confirmedURL else { throw WorkspaceError("The confirmation must exactly match the task's current URL. Confirm public exposure of that URL before retrying.") }
        let existing = tunnel(for: taskID, in: project)
        if let existing, session(existing.id)?.phase.isActive == true {
            if activate { try openTask(existing.id, projectID: projectID) }
            return
        }
        var task = existing ?? ProjectTask(definition: TaskDefinition(name: "", command: ""),
            source: "Built-in", sourceKey: "builtin:cloudflare", temporary: true, tunnelForTaskID: taskID)
        task.definition.name = "Tunnel · \(owner.definition.name)"
        task.definition.command = "cloudflared tunnel --url \(ShellBootstrap.quote(address))"
        try saveTask(task, projectID: projectID)
        if activate { pendingTunnelCopies.insert(task.id) }
        do { try startTask(task.id, projectID: projectID, activate: activate) }
        catch { pendingTunnelCopies.remove(task.id); throw error }
    }

    /// Consume UI-only copy intent once; CLI starts never register it.
    func completeTunnelCopy(_ taskID: UUID, url: URL, pasteboard: NSPasteboard = .general) {
        guard pendingTunnelCopies.remove(taskID) != nil else { return }
        pasteboard.clearContents()
        guard pasteboard.setString(url.absoluteString, forType: .string) else {
            errorMessage = "Couldn't copy the tunnel link. Use Copy link in Task links."
            return
        }
        tunnelCopyNotice = UUID()
    }

    func stopTask(_ taskID: UUID, projectID: UUID) {
        stopAssociatedTunnels(taskID, projectID: projectID)
        if let terminal = session(taskID), terminal.phase.isActive { terminal.stop() }
        else if document.projects.first(where: { $0.id == projectID })?.tasks.first(where: { $0.id == taskID })?.temporary == true {
            perform { try closeTab(taskID, projectID: projectID) }
        }
    }

    func stopAssociatedTunnels(_ taskID: UUID, projectID: UUID) {
        guard let project = document.projects.first(where: { $0.id == projectID }) else { return }
        for task in project.tasks where task.tunnelForTaskID == taskID {
            session(task.id)?.stop(focus: false)
        }
    }

    func taskPhaseChanged(_ taskID: UUID, projectID: UUID) {
        guard !preservingResumeState, let terminal = session(taskID) else { return }
        switch terminal.phase {
        case .stopping, .stopped, .exited, .failed:
            if pendingTunnelCopies.remove(taskID) != nil, !terminal.stopWasRequested {
                errorMessage = "The tunnel stopped before connecting. Check its terminal for details."
            }
            stopAssociatedTunnels(taskID, projectID: projectID)
        default: return
        }
        // Qualify the completed run now; later shell maintenance must not turn
        // an originally ineligible failure into disposable work.
        guard case .exited(let code) = terminal.phase, code == 0 || terminal.stopWasRequested,
              document.projects.first(where: { $0.id == projectID })?.tasks.first(where: { $0.id == taskID })?.temporary == true else { return }
        // Defer removal until the shell-event callback finishes. Never discard failure output
        // or a manual command/pending input, and never mutate the array during Stop all.
        Task { @MainActor [weak self, weak terminal] in
            guard let self, !self.preservingResumeState, let terminal,
                  case .exited(let code) = terminal.phase,
                  code == 0 || terminal.stopWasRequested,
                  !terminal.manualCommandRunning, !terminal.hasPendingInput,
                  self.document.projects.first(where: { $0.id == projectID })?.tasks.first(where: { $0.id == taskID })?.temporary == true else { return }
            self.perform { try self.closeTab(taskID, projectID: projectID) }
        }
    }
}
