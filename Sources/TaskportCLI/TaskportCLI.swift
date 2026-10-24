import Foundation
import TaskportControl

@main enum TaskportCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["help"] || arguments == ["--help"] {
            print(CLIArguments.help); return
        }
        do {
            let request = try CLIArguments.parse(arguments)
            let response: ControlResponse
            if ["app.launch", "app.quit", "app.restart"].contains(request.operation) {
                response = try await CLILifecycle.perform(request)
            } else if request.operation == "ports.list" {
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
