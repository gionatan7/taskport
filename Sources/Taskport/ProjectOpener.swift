import AppKit
import UniformTypeIdentifiers

enum ProjectOpener {
    enum Destination: String, CaseIterable {
        case finder = "Finder"
        case ghostty = "Ghostty"
        case code = "Visual Studio Code"

        var bundleID: String {
            switch self {
            case .finder: "com.apple.finder"
            case .ghostty: "com.mitchellh.ghostty"
            case .code: "com.microsoft.VSCode"
            }
        }
    }

    /// Only root-level workspace files qualify; nested projects are independent.
    static func workspaces(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter {
                guard $0.pathExtension == "code-workspace" else { return false }
                return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @MainActor
    static func open(_ directory: String, in destination: Destination) async throws {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        guard (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw failure("The project directory is no longer available.")
        }
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: destination.bundleID) else {
            throw failure("\(destination.rawValue) is not installed.")
        }
        if destination == .ghostty {
            _ = try await NSWorkspace.shared.openApplication(at: application, configuration: .init())
            try openGhostty(directory)
            return
        }
        var target = root
        if destination == .code {
            let candidates = try workspaces(in: root)
            if candidates.count == 1 { target = candidates[0] }
            else if candidates.count > 1 {
                let panel = NSOpenPanel()
                panel.title = "Choose a Visual Studio Code workspace"
                panel.directoryURL = root
                panel.allowedContentTypes = [UTType(filenameExtension: "code-workspace") ?? .data]
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let selected = panel.url else { return }
                target = selected
            }
        }
        _ = try await NSWorkspace.shared.open([target], withApplicationAt: application, configuration: .init())
    }

    /// Pass the directory as AppleEvent data, never as executable script text.
    @MainActor
    private static func openGhostty(_ directory: String) throws {
        guard let script = NSAppleScript(source: """
        on openProject(projectDirectory)
            tell application id "com.mitchellh.ghostty"
                set cfg to new surface configuration
                set initial working directory of cfg to projectDirectory
                if (count of windows) is 0 then
                    new window with configuration cfg
                else
                    new tab in front window with configuration cfg
                end if
                activate
            end tell
        end openProject
        """) else { throw failure("Could not prepare the Ghostty tab request.") }
        let event = NSAppleEventDescriptor(eventClass: 0x61736372, eventID: 0x70736272,
                                          targetDescriptor: nil, returnID: -1, transactionID: 0)
        event.setParam(NSAppleEventDescriptor(string: "openProject"), forKeyword: 0x736e616d)
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: directory), at: 1)
        event.setParam(arguments, forKeyword: 0x2d2d2d2d)
        var error: NSDictionary?
        script.executeAppleEvent(event, error: &error)
        if let error {
            let detail = error[NSAppleScript.errorMessage] as? String ?? "The AppleScript request failed."
            throw failure("Could not open a Ghostty tab. \(detail) Ghostty must support AppleScript, and Taskport needs permission in System Settings → Privacy & Security → Automation.")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Taskport.ProjectOpener", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
