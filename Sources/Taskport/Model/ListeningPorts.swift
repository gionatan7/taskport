import Foundation
import TaskportPTY

enum ListeningPorts {
    static func scan(shellPIDs: [Int32]) -> [Int32: [Int]] {
        guard !shellPIDs.isEmpty else { return [:] }
        var listeners = [tp_listener](repeating: tp_listener(), count: 65_536)
        let count = tp_listening_ports(shellPIDs, Int32(shellPIDs.count), &listeners, Int32(listeners.count))
        var ports: [Int32: Set<Int>] = [:]
        for listener in listeners.prefix(Int(count)) {
            ports[listener.session, default: []].insert(Int(listener.port))
        }
        return ports.mapValues { $0.sorted() }
    }

    static func label(_ ports: [Int]) -> String {
        ports.isEmpty ? "Stopped" : ports.map { ":\($0)" }.joined(separator: ", ")
    }
}

extension WorkspaceStore {
    /// Snapshot identities on the main actor, inspect descriptors off-thread, then discard
    /// observations from shells that exited or were replaced while scanning.
    func refreshListeningPorts() async {
        let owners = sessions.filter { $0.shellPID > 0 }.map { (id: $0.id, projectID: $0.projectID, pid: $0.shellPID) }
        let observations = await Task.detached(priority: .utility) {
            ListeningPorts.scan(shellPIDs: owners.map(\.pid))
        }.value
        var result: [UUID: Set<Int>] = [:]
        for owner in owners where session(owner.id)?.shellPID == owner.pid {
            result[owner.projectID, default: []].formUnion(observations[owner.pid] ?? [])
        }
        let sorted = result.mapValues { $0.sorted() }
        if listeningPorts != sorted { listeningPorts = sorted }
    }
}
