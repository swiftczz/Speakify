import Foundation
import SwiftData

/// Builds the SwiftData container the history and quota records live in.
///
/// This used to sit in `SpeakifyApp`, which meant the app target named every model
/// type and converted their metatypes to `any PersistentModel.Type` across a module
/// boundary. The models are declared here, so the schema belongs here too: the entry
/// point should not have to know what the store contains in order to open it.
package enum HistoryModelContainer {
    /// Every model kept in the history store.
    private static var schema: Schema {
        Schema([SpeechHistoryRecord.self, SubscriptionQuotaSnapshot.self])
    }

    /// Opens the store, falling back rather than failing.
    ///
    /// A history file that will not open used to take the whole app down on launch.
    /// Each rung down keeps the app running with less: the real store, a fresh store
    /// with the old file set aside, memory-only, and finally an empty container that
    /// has nothing left to fail on: no schema to validate and no file to open. That
    /// last rung is the one `try!` here, and it is the only one that cannot be given
    /// a fallback — the caller is a stored property on the `App`, which has nowhere
    /// to put a failure.
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

        // The old file stays on disk, and the window tells the user where it went.
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
