import SwiftData
import SwiftUI

package struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionQuotaSnapshot.updatedAt, order: .reverse) private var subscriptionSnapshots: [SubscriptionQuotaSnapshot]
    private let settings: AppSettings
    @State private var viewModel: SpeechViewModel
    @AppStorage("ui.sidebarVisible") private var isSidebarVisible = true
    @AppStorage("ui.historyVisible") private var isHistoryVisible = true
    @State private var showsHistoryRecoveryNotice = AppDataLocation.quarantinedHistoryStoreURL != nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(settings: AppSettings) {
        self.settings = settings
        _viewModel = State(initialValue: SpeechViewModel(settings: settings))
    }

    private var displayedQuota: TTSQuota? {
        if viewModel.quotaScopeIdentifier == activeScopeIdentifier {
            return viewModel.quota ?? activeQuotaSnapshot?.quota
        }
        return activeQuotaSnapshot?.quota
    }

    private var activeCredentialFingerprint: String {
        CredentialScope.fingerprint(apiKey: settings.apiKey)
    }

    private var activeScopeIdentifier: String {
        CredentialScope.identifier(
            providerID: settings.providerID,
            apiKey: settings.apiKey
        )
    }

    private var activeQuotaSnapshot: SubscriptionQuotaSnapshot? {
        subscriptionSnapshots.first {
            $0.providerID == settings.providerID
                && $0.credentialFingerprint == activeCredentialFingerprint
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            isSidebarVisible ? .all : .detailOnly
        } set: { newValue in
            isSidebarVisible = newValue != .detailOnly
        }
    }

    package var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            SidebarView(
                reportsQuota: viewModel.activeProviderReportsQuota,
                displayedQuota: displayedQuota
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 258, max: 360)
        } detail: {
            MainWorkspace(settings: settings, viewModel: viewModel)
                .frame(minWidth: 460)
                .inspector(isPresented: $isHistoryVisible) {
                    HistoryPanel(onApply: { draft in
                        Task { await viewModel.applyHistoryDraft(draft) }
                    })
                        .inspectorColumnWidth(min: 280, ideal: 310, max: 420)
                }
        }
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onKeyPress(.space) {
            Task { await viewModel.togglePlayPause(modelContext: modelContext) }
            return .handled
        }
        .focusedSceneValue(\.speechActions, speechActions)
        .task {
            viewModel.focusEditor()

            if viewModel.voices.isEmpty {
                await viewModel.loadModelsAndVoices()
            }
        }
        .onChange(of: viewModel.quota) { _, newValue in
            persistQuotaSnapshot(newValue)
        }
        .onDisappear {
            viewModel.flushPendingDraft()
        }
        .alert("History was reset", isPresented: $showsHistoryRecoveryNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: L10n.format(
                "history.recovery-message",
                defaultValue: "Speakify could not open your history database, so it started a new one. The previous file was kept at %@.",
                AppDataLocation.quarantinedHistoryStoreURL?.path(percentEncoded: false) ?? ""
            ))
        }
    }

    private var speechActions: SpeechCommandActions {
        SpeechCommandActions(
            canGenerate: viewModel.canGenerate,
            isGenerating: viewModel.isGenerating,
            isPlaying: viewModel.playback.isPlaying,
            isPaused: viewModel.playback.isPaused,
            togglePlayPause: { Task { await viewModel.togglePlayPause(modelContext: modelContext) } },
            export: { Task { await viewModel.download(modelContext: modelContext) } },
            focusEditor: { viewModel.focusEditor() }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ServiceModelToolbarPicker(settings: settings, viewModel: viewModel)
        }

        ToolbarItem(placement: .principal) {
            VoiceToolbarPicker(viewModel: viewModel)
        }

        ToolbarItem(placement: .principal) {
            if viewModel.voiceSettingsCapabilities != nil {
                VoiceSettingsToolbarButton(viewModel: viewModel)
            }
        }

        ToolbarSpacer(.flexible, placement: .automatic)

        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                    isHistoryVisible.toggle()
                }
            } label: {
                Label {
                    Text("History")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .help(isHistoryVisible ? Text("Hide History") : Text("Show History"))
        }
    }

    private func persistQuotaSnapshot(_ quota: TTSQuota?) {
        guard let quota else { return }

        let matchingSnapshots = subscriptionSnapshots.filter {
            $0.providerID == settings.providerID
                && $0.credentialFingerprint == activeCredentialFingerprint
        }
        let snapshot = matchingSnapshots.first ?? SubscriptionQuotaSnapshot(
            providerID: settings.providerID,
            credentialFingerprint: activeCredentialFingerprint,
            characterCount: quota.characterCount,
            characterLimit: quota.characterLimit
        )

        if matchingSnapshots.isEmpty {
            modelContext.insert(snapshot)
        }

        snapshot.characterCount = quota.characterCount
        snapshot.characterLimit = quota.characterLimit
        snapshot.updatedAt = .now

        for staleSnapshot in matchingSnapshots.dropFirst() {
            modelContext.delete(staleSnapshot)
        }

        for legacySnapshot in subscriptionSnapshots
            where legacySnapshot.providerID.isEmpty || legacySnapshot.credentialFingerprint.isEmpty {
            modelContext.delete(legacySnapshot)
        }

        try? modelContext.save()
    }
}
