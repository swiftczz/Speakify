import AppKit
import SwiftUI

/// The window's shared colours. Everything resolves from a system colour so the
/// app follows the user's appearance and accent choices, with one hand-made
/// surface tone for the raised cards.
enum AppPalette {
    static let ink = Color(NSColor.labelColor)
    static let muted = Color(NSColor.secondaryLabelColor)
    static let stroke = Color(NSColor.separatorColor)
    static let accent = Color(NSColor.controlAccentColor)
    static let selectedNav = Color(NSColor.selectedContentBackgroundColor).opacity(0.12)
    static let sidebarBackground = Color(NSColor.windowBackgroundColor)
    static let contentBackground = Color(NSColor.controlBackgroundColor)
    static let controlBackground = Color(NSColor.controlColor)
    /// A raised surface a hair off the window background: near-white in light mode,
    /// a soft charcoal in dark. Deliberately a flat tone rather than a translucent
    /// material, which read too gray for the cards.
    static let cardSurface = Color(NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    }))
}
