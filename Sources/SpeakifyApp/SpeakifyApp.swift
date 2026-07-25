import AppKit
import SwiftData
import SwiftUI
import Speakify

@main
struct SpeakifyApp: App {
    @State private var settings = AppSettings()

    private let historyModelContainer = HistoryModelContainer.make()

    var body: some Scene {
        Window("Speakify", id: "main") {
            ContentView(settings: settings)
                .frame(minHeight: 640)
                .modelContainer(historyModelContainer)
                .environment(\.locale, settings.appLocale)
                .onAppear { NSApp.appearance = settings.appAppearance.nsAppearance }
                .onChange(of: settings.appAppearance) { _, newValue in
                    NSApp.appearance = newValue.nsAppearance
                }
        }
        .defaultSize(width: 1440, height: 860)
        .windowResizability(.contentMinSize)
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

private extension AppAppearance {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
