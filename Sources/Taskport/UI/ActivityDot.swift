import SwiftUI

/// Color represents process state; a quiet halo represents recent PTY output only.
struct ActivityDot: View {
    let color: Color
    var lastOutputAt = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRecentOutput = false

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .overlay {
                Circle().stroke(color.opacity(0.3), lineWidth: 3)
                    .frame(width: 12, height: 12)
                    .opacity(hasRecentOutput && !reduceMotion ? 1 : 0)
            }
            .accessibilityHidden(true)
            .task(id: lastOutputAt) {
                guard !reduceMotion, Date().timeIntervalSince(lastOutputAt) < 1 else {
                    hasRecentOutput = false
                    return
                }
                hasRecentOutput = true
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                withAnimation(.easeOut(duration: 0.2)) { hasRecentOutput = false }
            }
    }
}
