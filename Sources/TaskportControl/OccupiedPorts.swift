import Foundation

/// TCP listeners visible to the current user, independent of Taskport's owned sessions.
public enum OccupiedPorts {
    public static func scan() throws -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // Machine-readable fields (lsof always includes PID/FD), numeric endpoints,
        // and TCP listeners only. No process names, arguments, or working directories.
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, value in value }
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        // Drain before waiting, and merge diagnostics so neither pipe can fill and block.
        // Any diagnostic or unrecognized row makes the snapshot fail, never look empty.
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationReason == .exit else {
            throw ControlError("Couldn't inspect system TCP ports. Check execution/sandbox permissions and retry; do not assume ports are free.")
        }
        return try parse(String(decoding: data, as: UTF8.self), exitStatus: process.terminationStatus)
    }

    static func parse(_ output: String, exitStatus: Int32) throws -> [Int] {
        // lsof uses exit 1 for no matches. Diagnostics must never become an empty success.
        if exitStatus == 1, output.isEmpty { return [] }
        guard exitStatus == 0, !output.isEmpty else {
            throw ControlError("Couldn't inspect system TCP ports. Check execution/sandbox permissions and retry; do not assume ports are free.")
        }
        var ports: Set<Int> = []
        var hasProcess = false
        for line in output.split(whereSeparator: \.isNewline) {
            if line.first == "p", let pid = Int32(line.dropFirst()), pid > 0 {
                hasProcess = true
                continue
            }
            if hasProcess, line.first == "f", let fd = Int32(line.dropFirst()), fd >= 0 { continue }
            guard hasProcess, line.first == "n", line.contains(":"), !line.contains("->"),
                  let suffix = line.split(separator: ":").last,
                  let port = UInt16(suffix), port > 0 else {
                throw ControlError("Couldn't read a complete TCP port snapshot. lsof returned a diagnostic or unexpected output; check execution/sandbox permissions before retrying.")
            }
            ports.insert(Int(port))
        }
        guard !ports.isEmpty else { throw ControlError("The TCP port inspection returned no usable data; do not assume ports are free.") }
        return ports.sorted()
    }
}
