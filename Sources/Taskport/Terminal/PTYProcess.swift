import Foundation
import TaskportPTY

/// One owned shell and PTY. All descriptor access is serialized on the main actor.
@MainActor
final class PTYProcess {
    private(set) var pid: Int32 = 0
    private var master: Int32 = -1
    private var reader: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var exitSource: DispatchSourceProcess?
    private var pendingInput = Data()
    var onOutput: (Data) -> Void = { _ in }
    var onExit: (Int32) -> Void = { _ in }
    var foregroundPID: Int32 { master >= 0 ? tp_foreground(master) : 0 }

    func start(directory: String, arguments: [String], environment: [String: String]) throws {
        precondition(pid == 0)
        let argv = arguments.map { strdup($0) } + [nil]
        let env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            env.forEach { free($0) }
        }
        pid = directory.withCString { directory in
            argv.withUnsafeBufferPointer { args in
                env.withUnsafeBufferPointer { vars in tp_spawn(directory, args.baseAddress, vars.baseAddress, &master) }
            }
        }
        guard pid > 0 else {
            pid = 0
            throw CocoaError(.executableNotLoadable)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
        source.resume()
        reader = source
        let exits = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exits.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.didExit() } }
        exits.resume()
        exitSource = exits
    }

    func write(_ data: Data) {
        guard master >= 0, !data.isEmpty else { return }
        // A bounded queue prevents an accidental huge paste from exhausting memory.
        guard pendingInput.count + data.count <= 2_097_152 else { return }
        pendingInput.append(data)
        flushInput()
    }

    func resize(columns: Int, rows: Int) {
        guard master >= 0 else { return }
        _ = tp_resize(master, UInt16(clamping: max(1, columns)), UInt16(clamping: max(1, rows)))
    }

    func interrupt() {
        guard master >= 0 else { return }
        // PTY-generated Ctrl-C observes terminal ISIG and the real foreground group.
        write(Data([3]))
    }

    func terminate() {
        guard pid > 0 else { return }
        let ownedPID = pid
        _ = tp_signal_session(ownedPID, SIGTERM)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, self.pid == ownedPID else { return }
            _ = tp_signal_session(ownedPID, SIGKILL)
        }
    }

    private func flushInput() {
        while !pendingInput.isEmpty, master >= 0 {
            let count = pendingInput.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
            if count > 0 { pendingInput.removeFirst(count); continue }
            if errno == EINTR { continue }
            if errno == EAGAIN, writer == nil {
                let source = DispatchSource.makeWriteSource(fileDescriptor: master, queue: .main)
                source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.flushInput() } }
                source.resume()
                writer = source
            }
            break
        }
        if pendingInput.isEmpty { writer?.cancel(); writer = nil }
    }

    private func readAvailable() {
        guard master >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 32_768)
        // Bound each turn so a noisy task cannot starve native controls.
        for _ in 0..<8 {
            let count = Darwin.read(master, &bytes, bytes.count)
            if count > 0 { onOutput(Data(bytes.prefix(count))); continue }
            if count < 0, errno == EINTR { continue }
            break
        }
    }

    private func didExit() {
        guard pid > 0 else { return }
        readAvailable()
        // Catch remaining same-session children before reaping releases the PID.
        _ = tp_signal_session(pid, SIGKILL)
        var code: Int32 = 0
        guard tp_reap(pid, &code) == 1 else { return }
        reader?.cancel(); reader = nil
        writer?.cancel(); writer = nil
        exitSource?.cancel(); exitSource = nil
        Darwin.close(master)
        master = -1
        pid = 0
        pendingInput.removeAll()
        onExit(code)
    }
}
