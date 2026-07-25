import SwiftUI
import UniformTypeIdentifiers

package struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var isChoosingDownloadDirectory = false

    private var activeCapabilities: TTSProviderCapabilities {
        TTSProviderRegistry.provider(withID: settings.providerID).capabilities
    }

    private var activeProviderName: String {
        TTSProviderRegistry.provider(withID: settings.providerID).displayName
    }

    package init(settings: AppSettings) {
        self.settings = settings
    }

    package var body: some View {
        Form {
            Section {
                Picker("App Language", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.titleKey))
                            .tag(language)
                    }
                }

                Picker("Appearance", selection: $settings.appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(LocalizedStringKey(appearance.titleKey))
                            .tag(appearance)
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Language changes apply immediately.")
            }

            Section {
                Picker("Service", selection: $settings.providerID) {
                    ForEach(TTSProviderRegistry.options) { option in
                        Text(option.name).tag(option.id)
                    }
                }

                Picker("Output", selection: $settings.outputFormat) {
                    ForEach(activeCapabilities.outputFormats, id: \.self) { format in
                        Text(OutputFormat.displayName(for: format)).tag(format)
                    }
                }

                if activeCapabilities.acceptsLanguageHint {
                    Picker("Language", selection: $settings.languageCode) {
                        ForEach(SpeechLanguage.supportedCodes, id: \.self) { code in
                            Text(SpeechLanguage.displayName(for: code, locale: settings.appLocale))
                                .tag(code)
                        }
                    }
                }

                LabeledContent("API Key") {
                    APIKeyField(text: $settings.apiKey)
                        .id(settings.providerID)
                        .frame(minWidth: 290, idealWidth: 330, maxWidth: 420)
                }
            } header: {
                Text("Speech Service")
            } footer: {
                VStack(alignment: .leading, spacing: 5) {
                    if activeCapabilities.providesSubtitles == false {
                        Text("This service downloads audio only. Choose ElevenLabs when you also need SRT subtitles.")
                    } else if activeCapabilities.providesCharacterAlignment == false {
                        Text("This service includes an estimated SRT based on the measured audio duration.")
                    }
                    Text(LocalizedStringKey(activeCapabilities.apiKeyHint))
                    Text("Stored in Speakify’s local settings for \(activeProviderName).")
                }
            }

            Section("Download") {
                LabeledContent("Location") {
                    HStack(spacing: 10) {
                        Text(settings.downloadDirectoryPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .frame(
                                minWidth: 220,
                                idealWidth: 300,
                                maxWidth: 420,
                                alignment: .trailing
                            )

                        Button("Choose…") {
                            isChoosingDownloadDirectory = true
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // `.fileImporter`, not `NSOpenPanel().runModal()`. The panel version blocked the
        // run loop from inside a view's action and needed AppKit imported into a
        // SwiftUI file; this is declarative, and the sandbox grants the same access.
        .fileImporter(
            isPresented: $isChoosingDownloadDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                settings.downloadDirectoryPath = url.path()
            }
        }
        .fileDialogDefaultDirectory(settings.downloadDirectoryURL)
        .frame(
            minWidth: 560,
            idealWidth: 620,
            maxWidth: 760,
            minHeight: 560,
            idealHeight: 600,
            maxHeight: 760
        )
    }

}

/// A secure entry field with a reveal toggle, in the style of password fields
/// in System Settings: the eye button swaps masked and plain text in place.
private struct APIKeyField: View {
    @Binding var text: String
    @State private var isRevealed = false
    @ScaledMetric private var revealButtonSize: CGFloat = 18
    @FocusState private var focusedField: Field?

    private enum Field {
        case masked
        case plain
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField("API Key", text: $text)
                        .focused($focusedField, equals: .plain)
                } else {
                    SecureField("API Key", text: $text)
                        .focused($focusedField, equals: .masked)
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .autocorrectionDisabled()
            .privacySensitive()

            Button {
                let wasFocused = focusedField != nil
                isRevealed.toggle()
                if wasFocused {
                    focusedField = isRevealed ? .plain : .masked
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: revealButtonSize, height: revealButtonSize)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help(isRevealed ? Text("Hide API key") : Text("Show API key"))
            .accessibilityLabel(Text(isRevealed ? "Hide API key" : "Show API key"))
        }
    }
}
