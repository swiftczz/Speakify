import CryptoKit
import Foundation

enum CredentialScope {
    static func fingerprint(apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else { return "anonymous" }

        let digest = SHA256.hash(data: Data(trimmedKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func identifier(providerID: String, apiKey: String) -> String {
        "\(providerID)\u{1F}\(fingerprint(apiKey: apiKey))"
    }
}
