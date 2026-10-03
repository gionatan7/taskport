import Foundation

/// Installs only a symlink; never overwrites another command or edits shell configuration.
struct CommandLineInstallation {
    let executable: URL
    let destination: URL

    init(bundle: URL = Bundle.main.bundleURL,
         directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")) {
        executable = bundle.appendingPathComponent("Contents/MacOS/taskport-cli")
        destination = directory.appendingPathComponent("taskport")
    }

    var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == executable.path
    }

    func install() throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw WorkspaceError("The bundled command-line tool is missing. Rebuild or reinstall Taskport.")
        }
        if isInstalled { return }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // createSymbolicLink fails if any file (including a dangling link) already occupies the name.
        do { try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: executable.path) }
        catch { throw WorkspaceError("Couldn't install at \(destination.path). Check folder permissions and whether another taskport command already exists. Nothing has been replaced.") }
    }

    func uninstall() throws {
        guard isInstalled else { throw WorkspaceError("This path isn't a link to this Taskport app. Nothing has been removed.") }
        try FileManager.default.removeItem(at: destination)
    }
}
