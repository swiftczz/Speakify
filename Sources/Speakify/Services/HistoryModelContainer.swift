import Foundation
import SwiftData

package enum HistoryModelContainer {
    private static var schema: Schema {
        Schema([SpeechHistoryRecord.self, SubscriptionQuotaSnapshot.self])
    }

    package static func make() -> ModelContainer {
        AppDataLocation.prepare()
        let schema = schema
        let configuration = ModelConfiguration(
            "History",
            schema: schema,
            url: AppDataLocation.historyStoreURL()
        )

        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        AppDataLocation.quarantineHistoryStore()
        if let recovered = try? ModelContainer(for: schema, configurations: [configuration]) {
            return recovered
        }

        let inMemory = ModelConfiguration("History", schema: schema, isStoredInMemoryOnly: true)
        if let memoryContainer = try? ModelContainer(for: schema, configurations: [inMemory]) {
            return memoryContainer
        }

        return try! ModelContainer(
            for: Schema([]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
