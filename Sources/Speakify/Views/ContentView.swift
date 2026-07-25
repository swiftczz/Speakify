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

    /// The split view drives column visibility, but the choice has to outlive the
    /// window, so the stored flag stays the source of truth and this projects it
    /// into the type the container wants.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            isSidebarVisible ? .all : .detailOnly
        } set: { newValue in
            isSidebarVisible = newValue != .detailOnly
        }
    }

    package var body: some View {
        // This was a hand-laid-out `HStack` for a while, on the finding that a split
        // view could not be held to a column width: the sidebar kept coming out as a
        // strip of bare "Soon" badges with its labels clipped off the leading edge.
        //
        // The symptom was real, but the cause was not this container. It was the
        // `frame(minWidth:)` the window put *around* it. A flex frame reports the width
        // it was given as the subtree's minimum even when the subtree needs more, so a
        // stated minimum below the split view's genuine one let the window shrink past
        // what the columns could satisfy — and the overflow went off the leading edge,
        // sidebar first. Widening the frame only moved the cliff; removing it fixed it.
        // See the note in `SpeakifyApp`.
        //
        // Column widths belong on each column's own root view, as below.
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            SidebarView(
                reportsQuota: viewModel.activeProviderReportsQuota,
                displayedQuota: displayedQuota
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 258, max: 360)
        } detail: {
            // A plain `frame`, not `navigationSplitViewColumnWidth`: the detail is the
            // column that absorbs whatever the other two do not take, so stating an
            // ideal for it only gives the split view a target to chase. It needs a
            // floor and nothing else.
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
        // Removes the hairline the toolbar draws along its bottom edge. It is not the
        // titlebar separator — that is already `.none`, verified — but the edge of the
        // toolbar's own shared backdrop, and this is the only thing that takes it off.
        //
        // It costs less than it sounds: each toolbar item keeps its own glass capsule,
        // so what goes away is the strip behind them, not the material. An earlier pass
        // removed this line on the theory that it was a workaround for the hand-laid-out
        // panes and was flattening the toolbar. It was doing neither.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.speechActions, speechActions)
        .task {
            // AppKit gives a new window's first responder to the first text field in
            // its key loop, and the inspector's search field is it — which put the
            // caret in the history filter rather than the editor the app exists to
            // type in. Claiming it back here goes through the same request the ⌘L
            // menu command uses.
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
            play: { Task { await viewModel.play(modelContext: modelContext) } },
            stop: { viewModel.stop() },
            cancel: { viewModel.cancelGeneration() },
            export: { Task { await viewModel.download(modelContext: modelContext) } },
            focusEditor: { viewModel.focusEditor() }
        )
    }

    // The sidebar toggle is not declared here: `NavigationSplitView` supplies it, and
    // declaring a second would put two of them side by side.
    //
    // Each control is its own `ToolbarItem`. They were once a single item wrapping an
    // `HStack`, which welded them into one view: no per-control background, and —
    // because the overflow menu moves whole items — nothing the system could relieve
    // individually when the window narrowed. Declared separately, macOS groups them
    // into shared backgrounds on its own; no `ToolbarSpacer` is involved, and adding
    // one at `.principal` changed nothing.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Centred, where they have always been. A pass over this moved them to the
        // leading edge on the theory that the principal slot drops whatever does not
        // fit. It does not — the voice picker was disappearing because of a `Spacer` in
        // its own label, which took it out at every placement equally.
        ToolbarItem(placement: .principal) {
            ServiceModelToolbarPicker(settings: settings, viewModel: viewModel)
        }

        ToolbarItem(placement: .principal) {
            VoiceToolbarPicker(viewModel: viewModel)
        }

        // The item is always declared and the condition lives inside it, which is what
        // keeps its identity stable. The `ToolbarItemGroup` attempt put the `if` around
        // the item itself, shifting every following item's position until macOS dropped
        // one. `ToolbarItem(id:)` is not the fix either: those are customizable-toolbar
        // items and need `.toolbar(id:)` to render at all, so in a plain toolbar they
        // simply go missing.
        ToolbarItem(placement: .principal) {
            if viewModel.voiceSettingsCapabilities != nil {
                VoiceSettingsToolbarButton(viewModel: viewModel)
            }
        }

        // Pushes the inspector toggle to the trailing edge, which works because the
        // group above sits in the centred principal slot rather than in this one.
        ToolbarSpacer(.flexible, placement: .automatic)

        ToolbarItem(placement: .automatic) {
            Button {
                // The pane still appears and disappears; it just does not slide there
                // when the user has asked for less motion.
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
