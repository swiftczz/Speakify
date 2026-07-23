import SwiftData
import SwiftUI

/// The main window: three resizable panes plus the toolbar that drives them.
/// Each pane lives in its own file; this type only composes them and owns the
/// state they share.
package struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionQuotaSnapshot.updatedAt, order: .reverse) private var subscriptionSnapshots: [SubscriptionQuotaSnapshot]
    @StateObject private var settings: AppSettings
    @StateObject private var viewModel: SpeechViewModel
    @AppStorage("ui.leftSidebarWidth") private var leftWidth = 258.0
    @AppStorage("ui.rightSidebarWidth") private var rightWidth = 310.0
    @AppStorage("ui.leftSidebarCollapsed") private var leftCollapsed = false
    @AppStorage("ui.rightSidebarCollapsed") private var rightCollapsed = false
    @State private var showsHistoryRecoveryNotice = AppDataLocation.quarantinedHistoryStoreURL != nil

    package init(settings: AppSettings) {
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: SpeechViewModel(settings: settings))
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

    private var leftWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(leftWidth) },
            set: { leftWidth = Double($0) }
        )
    }

    private var rightWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(rightWidth) },
            set: { rightWidth = Double($0) }
        )
    }

    package var body: some View {
        HStack(spacing: 0) {
            if !leftCollapsed {
                SidebarView(
                    reportsQuota: viewModel.activeProviderReportsQuota,
                    displayedQuota: displayedQuota
                )
                    .frame(width: CGFloat(leftWidth))
                    .transition(.move(edge: .leading))

                DragHandle(direction: 1, width: leftWidthBinding, minWidth: 200, maxWidth: 400)
            }

            MainWorkspace(settings: settings, viewModel: viewModel)
                .frame(minWidth: 400, maxWidth: .infinity)

            if !rightCollapsed {
                DragHandle(direction: -1, width: rightWidthBinding, minWidth: 240, maxWidth: 420)

                HistoryPanel(onApply: { viewModel.text = $0 })
                    .frame(width: CGFloat(rightWidth))
                    .transition(.move(edge: .trailing))
            }
        }
        .background(AppPalette.contentBackground)
        .toolbar { toolbarContent }
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
            Text(
                """
                Speakify could not open your history database, so it started a new one. \
                The previous file was kept at \
                \(AppDataLocation.quarantinedHistoryStoreURL?.path(percentEncoded: false) ?? "").
                """
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    leftCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(leftCollapsed ? "Show Sidebar" : "Hide Sidebar")
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 12) {
                ServiceModelToolbarPicker(settings: settings, viewModel: viewModel)
                VoiceToolbarPicker(viewModel: viewModel)
            }
        }

        ToolbarSpacer(.flexible, placement: .automatic)

        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    rightCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(rightCollapsed ? "Show History" : "Hide History")
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
