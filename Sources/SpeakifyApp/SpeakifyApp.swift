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
                .preferredColorScheme(settings.appAppearance.colorScheme)
        }
        .defaultSize(width: 1440, height: 860)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView(settings: settings)
                .environment(\.locale, settings.appLocale)
                .preferredColorScheme(settings.appAppearance.colorScheme)
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentSize)
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
