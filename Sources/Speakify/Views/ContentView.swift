import SwiftData
import SwiftUI

/// The main window: a system split view whose sidebar, detail and history
/// inspector each live in their own file. This type only composes them and owns
/// the state they share.
package struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionQuotaSnapshot.updatedAt, order: .reverse) private var subscriptionSnapshots: [SubscriptionQuotaSnapshot]
    private let settings: AppSettings
    @State private var viewModel: SpeechViewModel
    @AppStorage("ui.sidebarVisible") private var isSidebarVisible = true
    @AppStorage("ui.historyVisible") private var isHistoryVisible = true
    @State private var showsHistoryRecoveryNotice = AppDataLocation.quarantinedHistoryStoreURL != nil

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

    package var body: some View {
        // Deliberately not a `NavigationSplitView`.
        //
        // That container refuses to hold a column at a stated width once space gets
        // tight: `min:`, `ideal:`, `max:` pinned together, a `frame(minWidth:)` on the
        // content, a smaller detail minimum — none of it stopped it from crushing both
        // side panes and sliding their contents out past their own edges. Even with the
        // arithmetic comfortably satisfied (258 + 460 + 310 inside a 1040pt window) the
        // sidebar came out as a strip of bare "Soon" badges. Its only stable width was
        // the one it chose.
        //
        // Laying the three panes out by hand costs the system sidebar material and the
        // free toggle, and buys the behaviour this window actually wants: the side panes
        // never move, and every pixel of a resize goes to the editor in the middle.
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(
                    reportsQuota: viewModel.activeProviderReportsQuota,
                    displayedQuota: displayedQuota
                )
                    .frame(width: 258)
                    .transition(.move(edge: .leading))

                Divider()
            }

            MainWorkspace(settings: settings, viewModel: viewModel)
                .frame(minWidth: 460, maxWidth: .infinity)

            if isHistoryVisible {
                Divider()

                HistoryPanel(onApply: { draft in
                    Task { await viewModel.applyHistoryDraft(draft) }
                })
                    .frame(width: 310)
                    .transition(.move(edge: .trailing))
            }
        }
        // The toolbar paints an opaque strip the full width of the window, which cut
        // a white band across the top of the sidebar — the system split view never
        // showed one because its sidebar material runs behind the toolbar. Hiding the
        // toolbar's own background lets each pane's background reach the top instead.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { toolbarContent }
        .focusedSceneValue(\.speechActions, speechActions)
        .task {
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
            play: { Task { await viewModel.play(modelContext: modelContext) } },
            stop: { viewModel.stop() },
            cancel: { viewModel.cancelGeneration() },
            export: { Task { await viewModel.download(modelContext: modelContext) } },
            focusEditor: { viewModel.focusEditor() }
        )
    }

    // Both pane toggles are declared here now. `NavigationSplitView` used to supply
    // the leading one; laying the panes out by hand means owning it.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Label {
                    Text("Sidebar")
                } icon: {
                    Image(systemName: "sidebar.leading")
                }
            }
            .help(
                isSidebarVisible
                    ? L10n.string("Hide Sidebar", defaultValue: "Hide Sidebar")
                    : L10n.string("Show Sidebar", defaultValue: "Show Sidebar")
            )
        }

        // One item wrapping an HStack, not a `ToolbarItemGroup`. With a group, the
        // `if` around the voice-settings button shifted item identity and macOS
        // silently dropped the voice picker from the toolbar entirely.
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                ServiceModelToolbarPicker(settings: settings, viewModel: viewModel)
                VoiceToolbarPicker(viewModel: viewModel)
                if viewModel.voiceSettingsCapabilities != nil {
                    VoiceSettingsToolbarButton(viewModel: viewModel)
                }
            }
        }

        ToolbarSpacer(.flexible, placement: .automatic)

        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    isHistoryVisible.toggle()
                }
            } label: {
                Label {
                    Text("History")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .help(
                isHistoryVisible
                    ? L10n.string("Hide History", defaultValue: "Hide History")
                    : L10n.string("Show History", defaultValue: "Show History")
            )
        }
    }

    /// Mirrors the live quota into SwiftData so the sidebar can show the last known
    /// balance immediately on the next launch, before any network call returns.
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

        // Unscoped rows belong to the pre-account-isolation schema and must never
        // reappear for whichever account happens to be active.
        for legacySnapshot in subscriptionSnapshots
            where legacySnapshot.providerID.isEmpty || legacySnapshot.credentialFingerprint.isEmpty {
            modelContext.delete(legacySnapshot)
        }

        try? modelContext.save()
    }
}
