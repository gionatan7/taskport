import SwiftUI

struct TunnelCopyToast: View {
    let store: WorkspaceStore

    var body: some View {
        if let notice = store.tunnelCopyNotice {
            Label("Tunnel link copied", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .padding(12)
                .allowsHitTesting(false)
                .task(id: notice) {
                    AccessibilityNotification.Announcement("Tunnel link copied").post()
                    do { try await Task.sleep(for: .seconds(3)) }
                    catch { return }
                    if store.tunnelCopyNotice == notice { store.tunnelCopyNotice = nil }
                }
        }
    }
}
