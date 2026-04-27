import SwiftData
import SwiftUI

@main
struct SpeakifyApp: App {
    private let historyModelContainer: ModelContainer = {
        let schema = Schema([SpeechHistoryRecord.self, SubscriptionQuotaSnapshot.self])
        AppDataLocation.prepare()
        let storeURL = AppDataLocation.historyStoreURL()

        let configuration = ModelConfiguration("History", schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData history store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 720)
                .modelContainer(historyModelContainer)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
