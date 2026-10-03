import Foundation
import TaskportControl
import MachO

@main enum TaskportCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["help"] || arguments == ["--help"] {
            print(CLIArguments.help); return
        }
        do {
            if arguments == ["launch"] {
                var size: UInt32 = 0
                _ = _NSGetExecutablePath(nil, &size)
                var path = [CChar](repeating: 0, count: Int(size))
                guard _NSGetExecutablePath(&path, &size) == 0 else { throw ControlError("Couldn't locate the bundled CLI executable.") }
                let executable = URL(fileURLWithPath: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).resolvingSymlinksInPath()
                let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                guard bundle.pathExtension == "app" else { throw ControlError("Launch the CLI bundled in Taskport.app, or use scripts/taskport.") }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [bundle.path]
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw ControlError("Couldn't launch Taskport. If the app exists, check sandbox permissions before rebuilding; macOS can report a missing executable when launch access is denied.") }
                print(#"{"ok":true,"message":"Launch requested; query status before changing tasks."}"#)
                return
            }
            let request = try CLIArguments.parse(arguments)
            let response: ControlResponse
            if request.operation == "ports.list" {
                var snapshot = ControlResponse()
                snapshot.ports = try OccupiedPorts.scan()
                response = snapshot
            } else {
                response = try LocalSocket.request(request)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(response) + Data([10]))
            if !response.ok { exit(1) }
        } catch {
            let response = ControlResponse.failure(error.localizedDescription)
            if let data = try? JSONEncoder().encode(response) { FileHandle.standardError.write(data + Data([10])) }
            exit(2)
        }
    }
}
