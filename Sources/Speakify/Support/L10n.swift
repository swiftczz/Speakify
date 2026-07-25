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

    /// The bundle SwiftUI views must pass to `Text(_:bundle:)`.
    ///
    /// The strings ship two ways: `build_and_run.sh` copies the `.lproj` folders into
    /// `Contents/Resources`, and SwiftPM also emits them into `Speakify_Speakify.bundle`.
    /// A packaged app finds them in the main bundle; `swift run` only has the SwiftPM
    /// one. Resolving both is what makes a development run honour the language picker
    /// instead of silently falling back to English.
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
        // SwiftPM lowercases localization directory names when it builds its resource
        // bundle, so `zh-Hans.lproj` is `zh-hans.lproj` there. Try both spellings.
        for candidate in [identifier, identifier.lowercased()] {
            if let path = base.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return base
    }
}
