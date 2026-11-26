import SwiftUI
import AppKit

/// Schedule's signature color: Warm Coral — distinct from Keynote/Logic/Freeform's blues,
/// Pages' orange, and Pixelmator's deep crimson.
enum ScheduleTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 1.00, green: 0.44, blue: 0.40, alpha: 1.0) // #FF7066
            : NSColor(calibratedRed: 0.91, green: 0.33, blue: 0.31, alpha: 1.0) // #E8554E
    })
}
