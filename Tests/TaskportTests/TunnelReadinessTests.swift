import Foundation
import Testing
@testable import Taskport

struct TunnelReadinessTests {
    @Test func waitsForConnectionAcrossEveryFragmentSize() {
        let url = "https://example.trycloudflare.com"
        let output = Data("Your quick Tunnel: \(url)\r\nINF Registered tunnel connection connIndex=0\r\n".utf8)
        for size in 1...output.count {
            var parser = TunnelReadiness()
            var links: [URL] = []
            for start in stride(from: 0, to: output.count, by: size) {
                if let link = parser.consume(output.subdata(in: start..<min(start + size, output.count))) { links.append(link) }
            }
            #expect(links.map(\.absoluteString) == [url])
            #expect(parser.consume(output) == nil)
        }
    }

    @Test func advertisedURLAloneNeverPublishesAndSurvivesLongStartupOutput() {
        var parser = TunnelReadiness()
        #expect(parser.consume(Data("https://example.trycloudflare.com\n".utf8)) == nil)
        #expect(parser.consume(Data(String(repeating: "Waiting for connection\n", count: 1_000).utf8)) == nil)
        #expect(parser.consume(Data("Registered tunnel connection connIndex=0\n".utf8))?.absoluteString == "https://example.trycloudflare.com")
        var reversed = TunnelReadiness()
        #expect(reversed.consume(Data("Registered tunnel connection connIndex=0\n".utf8)) == nil)
        #expect(reversed.consume(Data("https://example.trycloudflare.com\n".utf8)) != nil)
    }

    @Test @MainActor func advertisedURLThenFailureRetainsUIErrorWithoutCopying() async throws {
        let root = testDirectory("tunnel-not-ready")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Simulated tunnel", command:
            "printf '%s\\n' 'https://example.trycloudflare.com'; exit 9"), sourceKey: "builtin:cloudflare", temporary: true)
        try store.saveTask(task, projectID: projectID)
        store.pendingTunnelCopies.insert(task.id)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(task.id)?.phase == .exited(9) }
        #expect(store.session(task.id)?.remoteURL == nil)
        #expect(store.pendingTunnelCopies.isEmpty)
        #expect(store.tunnelCopyNotice == nil)
        #expect(store.errorMessage == "The tunnel stopped before connecting. Check its terminal for details.")
        #expect(store.selectedProject?.tasks.contains { $0.id == task.id } == true)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test @MainActor func readyCLITunnelPublishesWithoutClipboardIntent() async throws {
        let root = testDirectory("tunnel-cli-ready")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let projectID = try store.addProject(name: "Example", directory: root.path)
        let task = ProjectTask(definition: TaskDefinition(name: "Simulated tunnel", command:
            "printf '%s\\n' 'https://example.trycloudflare.com' 'Registered tunnel connection connIndex=0'; sleep 60"),
            sourceKey: "builtin:cloudflare", temporary: true)
        try store.saveTask(task, projectID: projectID)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: projectID, activate: false)
        try await waitUntil { store.session(task.id)?.remoteURL != nil }
        #expect(store.session(task.id)?.remoteURL?.absoluteString == "https://example.trycloudflare.com")
        #expect(store.pendingTunnelCopies.isEmpty)
        #expect(store.tunnelCopyNotice == nil)
        #expect(store.errorMessage == nil)
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }
}
