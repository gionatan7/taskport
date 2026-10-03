import SwiftUI

/// A small native SF Symbols palette; no external icon dependency.
struct ProjectIconPicker: View {
    @Binding var selection: String
    let choose: () -> Void
    @State private var search = ""
    private static let symbols = [
        "folder", "terminal", "globe", "network", "server.rack", "externaldrive",
        "desktopcomputer", "laptopcomputer", "iphone", "appwindow", "curlybraces", "chevron.left.forwardslash.chevron.right",
        "cloud", "cloud.fill", "bolt", "gearshape", "wrench.and.screwdriver", "hammer",
        "shippingbox", "cube", "square.stack.3d.up", "cylinder.split.1x2", "cpu", "memorychip",
        "gamecontroller", "paintpalette", "photo", "camera", "music.note", "film",
        "doc", "book", "newspaper", "pencil", "chart.bar", "chart.pie",
        "cart", "bag", "creditcard", "house", "building.2", "map",
        "location", "paperplane", "envelope", "bubble.left.and.bubble.right", "person.2", "person.crop.circle",
        "lock", "key", "shield", "heart", "star", "sparkles",
        "leaf", "flame", "sun.max", "moon", "lightbulb", "antenna.radiowaves.left.and.right"
    ]
    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return Self.symbols }
        let filtered = Self.symbols.filter { $0.localizedCaseInsensitiveContains(query) }
        // Accept any valid symbol name, including symbols outside the curated palette.
        if !filtered.contains(query), NSImage(systemSymbolName: query, accessibilityDescription: nil) != nil {
            return [query] + filtered
        }
        return filtered
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project icon").font(.headline)
            TextField("Search SF Symbols or enter a symbol name", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(matches, id: \.self) { symbol in
                        Button { selection = symbol; choose() } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(selection == symbol ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(.borderless)
                        .help(symbol)
                        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                        .accessibilityAddTraits(selection == symbol ? .isSelected : [])
                    }
                }
                if matches.isEmpty { Text("No matching symbols").foregroundStyle(.secondary) }
            }
            .frame(height: 270)
        }
        .padding(16)
        .frame(width: 310)
    }
}
