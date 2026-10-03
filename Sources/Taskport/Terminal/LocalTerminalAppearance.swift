import Foundation

/// Reads local appearance only. Never imports commands, environment, shortcuts,
/// clipboard permissions, or window chrome into Taskport's terminal configuration.
enum LocalTerminalAppearance {
    private static let keys: Set<String> = [
        "font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic",
        "font-size", "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic",
        "font-feature", "font-thicken", "font-thicken-strength", "font-synthetic-style",
        "background", "foreground", "palette", "bold-color", "minimum-contrast",
        "selection-background", "selection-foreground", "cursor-color", "cursor-text",
        "cursor-style", "cursor-style-blink", "cursor-opacity"
    ]

    /// Resolve paths at runtime. The generated configuration contains no source paths.
    static func load(home: URL, environment: [String: String], ghosttyApplication: URL?) -> String {
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { value in
            value.hasPrefix("/") ? URL(fileURLWithPath: value) : nil
        } ?? home.appendingPathComponent(".config")
        let directories = [
            xdg.appendingPathComponent("ghostty"),
            home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")
        ]
        var themeDirectories = directories.map { $0.appendingPathComponent("themes") }
        if let ghosttyApplication {
            themeDirectories.append(ghosttyApplication.appendingPathComponent("Contents/Resources/ghostty/themes"))
        }
        var visited: Set<URL> = []
        let entries = directories.flatMap { directory in
            ["config.ghostty", "config"].flatMap { name in
                read(directory.appendingPathComponent(name), home: home, visited: &visited)
            }
        }

        // Theme values precede explicit settings, as in Ghostty. Only simple theme
        // names/files are supported here; light:/dark: pairs need a runtime observer.
        var theme: [(String, String)] = []
        if let name = entries.last(where: { $0.0 == "theme" })?.1, !name.isEmpty,
           !name.contains("light:"), !name.contains("dark:") {
            let candidates = name.hasPrefix("/") || name.hasPrefix("~/")
                ? [resolve(name, relativeTo: home, home: home)]
                : themeDirectories.map { $0.appendingPathComponent(name) }
            if let file = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) {
                var themeVisited: Set<URL> = []
                theme = read(file, home: home, visited: &themeVisited)
            }
        }
        return render(theme + entries)
    }

    /// Exact keys and single-line values prevent configuration directive injection.
    static func render(_ entries: [(String, String)]) -> String {
        let appearance = entries.compactMap { key, value -> String? in
            guard keys.contains(key), !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            }) else { return nil }
            return "\(key) = \(value)"
        }
        return (appearance + [
            "background-opacity = 1", "window-padding-x = 12", "window-padding-y = 8"
        ]).joined(separator: "\n")
    }

    private static func read(_ file: URL, home: URL, visited: inout Set<URL>) -> [(String, String)] {
        let file = file.resolvingSymlinksInPath().standardizedFileURL
        guard visited.count < 32, visited.insert(file).inserted,
              let contents = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var result: [(String, String)] = []
        var includes: [String] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if key == "config-file" {
                includes.append(value.hasPrefix("?") ? String(value.dropFirst()) : value)
            } else if keys.contains(key) || key == "theme" {
                result.append((key, value))
            }
        }
        // Ghostty processes includes after the containing file, not inline.
        for include in includes where !include.isEmpty {
            result += read(resolve(include, relativeTo: file.deletingLastPathComponent(), home: home),
                           home: home, visited: &visited)
        }
        return result
    }

    private static func resolve(_ path: String, relativeTo directory: URL, home: URL) -> URL {
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return directory.appendingPathComponent(path)
    }
}
