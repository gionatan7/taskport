import Darwin
import Foundation
import Testing
@testable import Taskport

struct ListeningPortsTests {
    @Test func labels() {
        #expect(ListeningPorts.label([]) == "Stopped")
        #expect(ListeningPorts.label([2442]) == ":2442")
        #expect(ListeningPorts.label([2442, 2443]) == ":2442, :2443")
        #expect(ListeningPorts.scan(shellPIDs: []).isEmpty)
        #expect(ListeningPorts.scan(shellPIDs: [0, 1, getpid()]).isEmpty)
    }

    @Test @MainActor func detectsOwnedChildListenerAndRemovesClosedPorts() async throws {
        let root = testDirectory("ports")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Reserve a kernel-assigned loopback port; release it just before the test child binds.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))
        close(fd)
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Listener", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Socket test", command: "/usr/bin/nc -l 127.0.0.1 \(port)"))
        try store.saveTask(task, projectID: projectID)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .running }
        for _ in 0..<100 {
            await store.refreshListeningPorts()
            if store.listeningPorts[projectID] == [port] { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.listeningPorts[projectID] == [port])
        // A different owned session must not claim this project's listener.
        let other = ProjectTask(definition: TaskDefinition(name: "No socket", command: "sleep 60"))
        try store.saveTask(other, projectID: projectID)
        try store.startTask(other.id, projectID: projectID, activate: false)
        let otherPID = try #require(store.session(other.id)).shellPID
        let listenerPID = try #require(store.session(task.id)).shellPID
        let ports = ListeningPorts.scan(shellPIDs: [otherPID, listenerPID])
        #expect(ports[otherPID] == nil)
        #expect(ports[listenerPID] == [port])
        store.stopTask(task.id, projectID: projectID)
        try await waitUntil { store.session(task.id)?.phase.isActive == false }
        await store.refreshListeningPorts()
        #expect(store.listeningPorts[projectID, default: []].isEmpty)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }
}
