import Foundation

/// zsh hooks wrap, but never modify/copy, the user's startup files.
enum ShellBootstrap {
    static func prepare(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let sources = [
            ".zshenv": """
            ZDOTDIR="$TASKPORT_USER_ZDOTDIR"
            [[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
            TASKPORT_USER_ZDOTDIR="${ZDOTDIR:-$HOME}"
            ZDOTDIR="$TASKPORT_BOOTSTRAP_DIR"
            """,
            ".zprofile": source(".zprofile"),
            ".zshrc": source(".zshrc") + "\n" + hooks,
            ".zlogin": source(".zlogin") + "\nZDOTDIR=\"$TASKPORT_USER_ZDOTDIR\"\n"
        ]
        for (name, script) in sources {
            try script.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Keeps commands out of the PTY's bounded input line and scopes cwd/env to a subshell.
    static func writeTask(_ definition: TaskDefinition, directory: String, to file: URL) throws -> String {
        let definition = try definition.validated()
        let exports = definition.environment.sorted(by: { $0.key < $1.key }).map {
            "export \(quote("\($0.key)=\($0.value)"))"
        }.joined(separator: "\n")
        let script = "builtin cd -- \(quote(directory)) || return $?\n\(exports)\neval \(quote(definition.command))\n"
        try Data(script.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return " (builtin source \(quote(file.path)))\r"
    }

    private static func source(_ name: String) -> String {
        """
        ZDOTDIR="$TASKPORT_USER_ZDOTDIR"
        [[ -r "$ZDOTDIR/\(name)" ]] && source "$ZDOTDIR/\(name)"
        TASKPORT_USER_ZDOTDIR="${ZDOTDIR:-$HOME}"
        ZDOTDIR="$TASKPORT_BOOTSTRAP_DIR"
        """
    }

    private static let hooks = #"""
    function _taskport_precmd() {
        local result=$?
        builtin printf '\033]777;taskport;%s;ready;%d\007' "$TASKPORT_SESSION_TOKEN" "$result"
        return 0
    }
    function _taskport_preexec() {
        builtin printf '\033]777;taskport;%s;busy\007' "$TASKPORT_SESSION_TOKEN"
        return 0
    }
    # First in the array captures the actual status before other prompt hooks.
    precmd_functions=(_taskport_precmd ${precmd_functions:#_taskport_precmd})
    preexec_functions=(_taskport_preexec ${preexec_functions:#_taskport_preexec})
    setopt HIST_IGNORE_SPACE
    """#
}
