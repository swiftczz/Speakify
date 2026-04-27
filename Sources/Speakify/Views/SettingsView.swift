import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let outputFormats = [
        "mp3_44100_128",
        "mp3_44100_192",
        "mp3_22050_32",
        "wav_44100"
    ]

    var body: some View {
        ZStack {
            Color.white
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 28, weight: .bold))
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Form {
                    Section("Provider") {
                        Picker("Service", selection: $settings.providerID) {
                            Text("ElevenLabs").tag("elevenlabs")
                        }
                        TextField("Model", text: $settings.modelID)
                        Picker("Output", selection: $settings.outputFormat) {
                            ForEach(outputFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }
                    }

                    Section("ElevenLabs") {
                        SecureField("API Key", text: $settings.apiKey)
                    }

                    Section("Download") {
                        HStack {
                            Text(settings.downloadDirectoryPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                chooseDownloadDirectory()
                            } label: {
                                Label("Choose", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(20)
        }
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
