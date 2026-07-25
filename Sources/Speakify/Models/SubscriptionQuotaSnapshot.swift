import Foundation
import SwiftData

@Model
package final class SubscriptionQuotaSnapshot {
    var providerID: String = ""
    var credentialFingerprint: String = ""
    var characterCount: Int
    var characterLimit: Int
    var updatedAt: Date

    init(
        providerID: String,
        credentialFingerprint: String,
        characterCount: Int,
        characterLimit: Int,
        updatedAt: Date = .now
    ) {
        self.providerID = providerID
        self.credentialFingerprint = credentialFingerprint
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        self.updatedAt = updatedAt
    }

    var quota: TTSQuota {
        TTSQuota(characterCount: characterCount, characterLimit: characterLimit)
    }
}
