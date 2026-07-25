import Foundation
import Synchronization

enum L10n {
    private static let language = Mutex(AppLanguage.system)

    static func configure(language newLanguage: AppLanguage) {
        language.withLock { $0 = newLanguage }
    }

    static func string(_ key: String, defaultValue: String) -> String {
        localizedBundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    static func format(
        _ key: String,
        defaultValue: String,
        _ arguments: any CVarArg...
    ) -> String {
        String(
            format: string(key, defaultValue: defaultValue),
            locale: locale,
            arguments: arguments
        )
    }

    static var locale: Locale {
        selectedLanguage.locale
    }

    static var resourceBundle: Bundle {
        Bundle.main.path(forResource: "en", ofType: "lproj") == nil ? .module : .main
    }

    private static var selectedLanguage: AppLanguage {
        language.withLock { $0 }
    }

    private static var localizedBundle: Bundle {
        let base = resourceBundle
        guard let identifier = selectedLanguage.localizationIdentifier else {
            return base
        }
        for candidate in [identifier, identifier.lowercased()] {
            if let path = base.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return base
    }
}
