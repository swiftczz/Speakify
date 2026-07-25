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
        // `Window` rather than `WindowGroup`: this is a single-session tool, and the
        // group's free ⌘N used to open a second window with its own view model,
        // audio player and catalog load, both writing the same settings.
        Window("Speakify", id: "main") {
            ContentView(settings: settings)
                // Just the sum of the three panes: 258 sidebar + 460 editor + 310
                // history, plus the two dividers. Now that `ContentView` lays them out
                // by hand the number is arithmetic rather than a figure found by
                // shrinking the window and watching for damage — the side panes hold
                // their width at every size, so only the editor's own minimum matters.
                .frame(minWidth: 1040, minHeight: 640)
                .modelContainer(historyModelContainer)
                .environment(\.locale, settings.appLocale)
        }
        .defaultSize(width: 1440, height: 860)
        // Without this the scene is freely resizable and the content's minimum size
        // is advisory only: dragging the window narrow squeezed both side columns
        // below their stated minimums and clipped their contents.
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { SpeechCommands() }

        Settings {
            SettingsView(settings: settings)
                .environment(\.locale, settings.appLocale)
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentSize)
    }
}
