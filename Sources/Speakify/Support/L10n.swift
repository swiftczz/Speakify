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
        _ arguments: CVarArg...
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

    private static var selectedLanguage: AppLanguage {
        language.withLock { $0 }
    }

    private static var localizedBundle: Bundle {
        guard let identifier = selectedLanguage.localizationIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
