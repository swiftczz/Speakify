import AppKit
import SwiftData
import SwiftUI
import Speakify

@main
struct SpeakifyApp: App {
    @State private var settings = AppSettings()

    /// Built by the module that declares the models. The schema and the recovery
    /// ladder live next to `SpeechHistoryRecord` rather than here.
    private let historyModelContainer = HistoryModelContainer.make()

    var body: some Scene {
        // `Window` rather than `WindowGroup`: this is a single-session tool, and the
        // group's free ⌘N used to open a second window with its own view model,
        // audio player and catalog load, both writing the same settings.
        Window("Speakify", id: "main") {
            ContentView(settings: settings)
                // No `minWidth`. A flex frame reports whatever minimum it is handed as
                // the subtree's own, so any figure below what the three columns actually
                // need lets the window shrink past them, and the shortfall is clipped off
                // the leading edge rather than shared out — which is what turned the
                // sidebar into a strip of bare "Soon" badges. Stating nothing lets
                // `.contentMinSize` read the split view's real minimum.
                //
                // `minHeight` is safe for the opposite reason: 640 is comfortably above
                // the content's own vertical minimum, so it only ever raises the floor.
                .frame(minHeight: 640)
                .modelContainer(historyModelContainer)
                .environment(\.locale, settings.appLocale)
                .onAppear { NSApp.appearance = settings.appAppearance.nsAppearance }
                .onChange(of: settings.appAppearance) { _, newValue in
                    NSApp.appearance = newValue.nsAppearance
                }
        }
        .defaultSize(width: 1440, height: 860)
        // Without this the scene is freely resizable and the content's minimum size
        // is advisory only: dragging the window narrow squeezed both side columns
        // below their stated minimums and clipped their contents.
        .windowResizability(.contentMinSize)
        // The title shows again: the heading it used to duplicate has been removed from
        // the content, and `navigationTitle` puts it here instead.
        .windowToolbarStyle(.unified)
        .commands { SpeechCommands() }

        Settings {
            SettingsView(settings: settings)
                .environment(\.locale, settings.appLocale)
                .onAppear { NSApp.appearance = settings.appAppearance.nsAppearance }
                .onChange(of: settings.appAppearance) { _, newValue in
                    NSApp.appearance = newValue.nsAppearance
                }
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentSize)
    }
}

/// Applied through AppKit rather than with `.preferredColorScheme`.
///
/// The SwiftUI modifier sets the scheme for the view tree, but the split view's
/// inspector column holds on to the appearance it was created with: switching at
/// runtime left the history panel dark while the rest of the window turned light, and
/// only relaunching put it right. `NSApp.appearance` drives every window and every
/// AppKit-backed container inside them, so one assignment covers the main window, the
/// inspector and the Settings scene together.
///
/// Kept here rather than on the enum: `AppSettings` is a service with no reason to
/// import AppKit, and this is the only place the appearance is ever applied.
private extension AppAppearance {
    /// `nil` hands the choice back to the system, which is what `.system` means.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
