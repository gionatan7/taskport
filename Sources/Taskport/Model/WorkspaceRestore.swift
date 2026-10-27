import CryptoKit
import Foundation
import TaskportControl

extension Project {
    /// Detect definition/folder changes without putting commands or environment values in the handoff.
    func restoreFingerprint(for task: ProjectTask) throws -> String {
        struct Configuration: Encodable { let directory: String; let task: ProjectTask }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(Configuration(directory: directory, task: task)))
            .map { String(format: "%02x", $0) }.joined()
    }
}

extension WorkspaceStore {
    /// Validate the whole session before freezing cleanup or touching a running process.
    func saveSessionHandoff(id: UUID, includeOneOffs: Bool, includeTunnels: Bool, updateBuild: String? = nil) throws -> SessionHandoff {
        guard !isReadOnly, !restoreInProgress else { throw WorkspaceError("The workspace is read-only or a restore is still in progress.") }
        guard sessions.allSatisfy({ !$0.manualCommandRunning && !$0.hasPendingInput }) else {
            throw WorkspaceError("Finish manual terminal commands and clear unfinished input before restarting. They cannot be reconstructed.")
        }
        var entries: [SessionHandoff.Entry] = [], skipped: [ActionResult] = []
        for session in sessions where session.phase.isActive {
            if session.phase == .stopping {
                skipped.append(ActionResult(taskID: session.id, outcome: "skipped", error: "Already stopping; not restarted."))
                continue
            }
            guard let project = document.projects.first(where: { $0.id == session.projectID }),
                  let task = project.tasks.first(where: { $0.id == session.id }) else {
                throw WorkspaceError("An active terminal no longer has a saved definition. Finish it before restarting.")
            }
            guard task.definition.kind != .oneOff || includeOneOffs else {
                throw WorkspaceError("An active one-off would run again from the beginning. Wait for it to finish, or explicitly authorize --include-one-offs.")
            }
            guard !task.isTunnel || includeTunnels else {
                throw WorkspaceError("A tunnel is active. Authorize --include-tunnels to expose the same local URLs again; public URLs may change.")
            }
            var resolved = task.definition
            resolved.environment = resolved.environment.mapValues { $0.replacingOccurrences(of: "${workspaceFolder}", with: project.directory) }
            guard resolved == session.startedDefinition, project.workingDirectory(for: task).path == session.startedDirectory else {
                throw WorkspaceError("A running task's definition has changed. Stop or restart that task explicitly before saving the session.")
            }
            var confirmedURL: String?
            if task.isTunnel {
                guard let owner = project.tasks.first(where: { $0.id == task.tunnelForTaskID && !$0.isTunnel }),
                      let url = owner.localURL, !(try LocalAddress.validate(url)).isEmpty else {
                    throw WorkspaceError("An active tunnel has no valid server URL. Stop it before restarting.")
                }
                confirmedURL = url
            }
            entries.append(.init(projectID: project.id, taskID: task.id,
                fingerprint: try project.restoreFingerprint(for: task), confirmedTunnelURL: confirmedURL))
        }
        let stopping = Set(skipped.map(\.taskID))
        let handoff = SessionHandoff(id: id, sourceProcessID: ProcessInfo.processInfo.processIdentifier,
            entries: entries, openTaskIDs: Set(document.projects.flatMap { visibleTasks(in: $0).map(\.id) }).subtracting(stopping),
            skipped: skipped, updateBuild: updateBuild)
        try handoff.save(in: persistence.directory)
        prepareToQuit()
        return handoff
    }

    /// Runs only after the app owns the workspace lock. Explicit restore replaces normal auto-resume.
    func restoreSession(_ id: UUID, updateDefaults: UserDefaults = .standard) {
        restoreID = id
        defer { UpdateWorkspace.discardConsumed(handoffID: id, in: persistence.directory, defaults: updateDefaults) }
        do {
            let handoff = try SessionHandoff.consume(id, in: persistence.directory)
            prepareToQuit(forRestore: true)
            restoreInProgress = true
            restoreResults = handoff.skipped
            let kept = handoff.openTaskIDs.union(handoff.entries.map(\.taskID))
            try commit(forceSave: true) {
                $0.runningPinnedTaskIDs = []
                for index in $0.projects.indices {
                    $0.projects[index].tasks.removeAll { $0.temporary && !kept.contains($0.id) }
                    let ids = Set($0.projects[index].tasks.map(\.id))
                    if let selected = $0.projects[index].selectedTaskID, !ids.contains(selected) {
                        $0.projects[index].selectedTaskID = $0.projects[index].tasks.first?.id
                    }
                }
            }
            restoreOpenTabs(handoff.openTaskIDs)
            var waiting: [UUID] = [], tunnels: [SessionHandoff.Entry] = []
            for entry in handoff.entries {
                do {
                    guard let project = document.projects.first(where: { $0.id == entry.projectID }),
                          let task = project.tasks.first(where: { $0.id == entry.taskID }),
                          try project.restoreFingerprint(for: task) == entry.fingerprint else {
                        throw WorkspaceError("Definition or project folder changed; not restarted.")
                    }
                    if task.isTunnel { tunnels.append(entry); continue }
                    try startTask(task.id, projectID: project.id, activate: false)
                    waiting.append(task.id)
                } catch { restoreResults.append(.init(taskID: entry.taskID, outcome: "failed", error: error.localizedDescription)) }
            }
            Task { @MainActor in
                await self.finishRestore(waiting: waiting, tunnels: tunnels)
            }
        } catch {
            restoreInProgress = false
            cancelQuit()
            restoreError = error.localizedDescription
            errorMessage = "Session restore failed. No automatic pinned-task fallback was run. \(error.localizedDescription)"
        }
    }

    private func finishRestore(waiting: [UUID], tunnels: [SessionHandoff.Entry]) async {
        defer {
            restoreInProgress = false
            cancelQuit()
            // Completions while cleanup was frozen must still retire successful temporary tasks.
            for terminal in sessions { taskPhaseChanged(terminal.id, projectID: terminal.projectID) }
        }
        await collectRestoreResults(waiting, timeout: 20, needsTunnelURL: false)
        var waitingTunnels: [UUID] = []
        for entry in tunnels {
            do {
                guard let project = document.projects.first(where: { $0.id == entry.projectID }),
                      let task = project.tasks.first(where: { $0.id == entry.taskID }),
                      let ownerID = task.tunnelForTaskID, let url = entry.confirmedTunnelURL,
                      try project.restoreFingerprint(for: task) == entry.fingerprint else {
                    throw WorkspaceError("The tunnel definition changed; not restarted.")
                }
                if let owner = restoreResults.first(where: { $0.taskID == ownerID })?.outcome, owner != "restarted" {
                    throw WorkspaceError("Its server did not restart; tunnel not opened.")
                }
                try startTunnel(for: ownerID, projectID: project.id, confirmedURL: url, activate: false)
                waitingTunnels.append(task.id)
            } catch { restoreResults.append(.init(taskID: entry.taskID, outcome: "failed", error: error.localizedDescription)) }
        }
        await collectRestoreResults(waitingTunnels, timeout: 35, needsTunnelURL: true)
    }

    private func collectRestoreResults(_ taskIDs: [UUID], timeout: TimeInterval, needsTunnelURL: Bool) async {
        var pending = Set(taskIDs)
        let deadline = Date().addingTimeInterval(timeout)
        while !pending.isEmpty {
            for id in pending {
                let terminal = session(id)
                let result: ActionResult?
                switch terminal?.phase {
                case .running where !needsTunnelURL || terminal?.remoteURL != nil:
                    result = .init(taskID: id, outcome: "restarted")
                case .exited(let code):
                    result = .init(taskID: id, outcome: code == 0 && !needsTunnelURL ? "completed" : "failed",
                        error: code == 0 && !needsTunnelURL ? nil : "Exited with code \(code). Inspect task state and logs before retrying.")
                case .failed(let message): result = .init(taskID: id, outcome: "failed", error: message)
                case .stopped, .stopping, .none: result = .init(taskID: id, outcome: "failed", error: "Stopped during restore.")
                default: result = Date() >= deadline ? .init(taskID: id, outcome: "failed",
                    error: "Startup not confirmed before timeout; it may still be running. Inspect status and logs before retrying.") : nil
                }
                if let result { restoreResults.append(result); pending.remove(id) }
            }
            if !pending.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        }
    }
}
