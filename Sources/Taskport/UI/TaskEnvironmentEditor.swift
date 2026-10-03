import SwiftUI

struct TaskEnvironmentEditor: View {
    @Binding var entries: [TaskEnvironmentEntry]

    var body: some View {
        DisclosureGroup("Environment variables") {
            if !entries.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($entries) { $entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField("Name", text: $entry.name, prompt: Text("VARIABLE_NAME"))
                                        .autocorrectionDisabled()
                                    Button("Remove variable", systemImage: "minus.circle") {
                                        let id = entry.id
                                        entries.removeAll { $0.id == id }
                                    }
                                    .labelStyle(.iconOnly)
                                    .help("Remove this environment variable")
                                }
                                TextEditor(text: $entry.value)
                                    .font(.system(.caption, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .frame(height: 60)
                                    .border(.separator)
                                    .accessibilityLabel(entry.name.isEmpty ? "Variable value" : "Value for \(entry.name)")
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
                .frame(height: min(220, CGFloat(entries.count) * 100))
            }
            Button("Add variable", systemImage: "plus") { entries.append(TaskEnvironmentEntry()) }
            Text("Values are literal and may contain multiple lines. Saved privately on this Mac; never added to the project.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
