import Foundation
import SwiftData

@Model
final class SubscriptionQuotaSnapshot {
    var characterCount: Int
    var characterLimit: Int
    var updatedAt: Date

    init(
        characterCount: Int,
        characterLimit: Int,
        updatedAt: Date = .now
    ) {
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        self.updatedAt = updatedAt
    }

    var subscription: ElevenLabsSubscription {
        ElevenLabsSubscription(characterCount: characterCount, characterLimit: characterLimit)
    }
}