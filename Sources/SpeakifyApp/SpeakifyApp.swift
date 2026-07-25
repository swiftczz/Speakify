import SwiftData
import SwiftUI
import Speakify

@main
struct SpeakifyApp: App {
    @State private var settings = AppSettings()

    private let historyModelContainer: ModelContainer = {
        let schema = Schema([SpeechHistoryRecord.self, SubscriptionQuotaSnapshot.self])
        AppDataLocation.prepare()
        let storeURL = AppDataLocation.historyStoreURL()

        let configuration = ModelConfiguration("History", schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A history store that will not open used to take the whole app down on
            // launch. Set it aside instead and start a fresh one; the old file stays
            // on disk, and the window tells the user where it went.
            AppDataLocation.quarantineHistoryStore()
            if let recovered = try? ModelContainer(for: schema, configurations: [configuration]) {
                return recovered
            }

            // Last resort: run without persistence rather than refuse to launch.
            let inMemory = ModelConfiguration("History", schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [inMemory])
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
                .frame(minWidth: 1180, minHeight: 720)
                .modelContainer(historyModelContainer)
                .environment(\.locale, settings.appLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SettingsView(settings: settings)
                .environment(\.locale, settings.appLocale)
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentSize)
    }
}
