import AppKit
import SwiftUI

package struct SettingsView: View {
    @ObservedObject var settings: AppSettings

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
            } header: {
                Text("Speech Service")
            } footer: {
                if activeCapabilities.providesSubtitles == false {
                    Text("This service downloads audio only. Choose ElevenLabs when you also need SRT subtitles.")
                } else if activeCapabilities.providesCharacterAlignment == false {
                    Text("This service includes an estimated SRT based on the measured audio duration.")
                }
            }

            Section {
                LabeledContent(activeProviderName) {
                    APIKeyField(text: $settings.apiKey)
                        .id(settings.providerID)
                        .frame(minWidth: 290, idealWidth: 330, maxWidth: 420)
                }
            } header: {
                Text("API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(activeCapabilities.apiKeyHint))
                    Text("Stored in Speakify’s local settings for \(activeProviderName).")
                }
                .foregroundStyle(.secondary)
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
                            chooseDownloadDirectory()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(
            minWidth: 560,
            idealWidth: 620,
            maxWidth: 760,
            minHeight: 560,
            idealHeight: 600,
            maxHeight: 760
        )
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadDirectoryURL

        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadDirectoryPath = url.path()
        }
    }
}

/// A secure entry field with a reveal toggle, in the style of password fields
/// in System Settings: the eye button swaps masked and plain text in place.
private struct APIKeyField: View {
    @Binding var text: String
    @State private var isRevealed = false
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
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help(
                isRevealed
                    ? L10n.string("Hide API key", defaultValue: "Hide API key")
                    : L10n.string("Show API key", defaultValue: "Show API key")
            )
            .accessibilityLabel(Text(isRevealed ? "Hide API key" : "Show API key"))
        }
    }
}
