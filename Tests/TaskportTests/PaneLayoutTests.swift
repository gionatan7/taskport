import AppKit
import Testing
@testable import Taskport

struct PaneLayoutTests {
    @Test @MainActor func nativeSplitPreservesRatioFromZeroBounds() {
        let split = TaskSplitView(frame: .zero)
        split.arrangesAllSubviews = false
        split.isVertical = false
        split.proportion = 0.36
        split.addArrangedSubview(NSView())
        split.addArrangedSubview(NSView())
        split.frame = NSRect(x: 0, y: 0, width: 900, height: 665)
        split.layoutSubtreeIfNeeded()
        split.applyProportion()
        #expect(abs(split.arrangedSubviews[0].frame.height / 665 - 0.36) < 0.002)
        split.frame.size.height = 800
        split.layoutSubtreeIfNeeded()
        #expect(abs(split.arrangedSubviews[0].frame.height / 800 - 0.36) < 0.002)
        var userRatio: Double?
        split.onPositionChanged = { userRatio = $0 }
        split.setPosition(400, ofDividerAt: 0)
        #expect(abs((userRatio ?? 0) - 0.5) < 0.002)
        split.layoutSubtreeIfNeeded()
        #expect(abs(split.arrangedSubviews[0].frame.height - 400) < 1)
    }
}
