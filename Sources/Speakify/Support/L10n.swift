import Foundation

enum L10n {
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
        AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        ) ?? .system
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
