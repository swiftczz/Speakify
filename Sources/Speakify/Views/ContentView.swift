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
    @State private var leftWidth: CGFloat = 258
    @State private var rightWidth: CGFloat = 310
    @State private var leftCollapsed = false
    @State private var rightCollapsed = false
    @State private var showsHistoryRecoveryNotice = AppDataLocation.quarantinedHistoryStoreURL != nil

    package init(settings: AppSettings) {
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: SpeechViewModel(settings: settings))
    }

    private var displayedQuota: TTSQuota? {
        viewModel.quota ?? subscriptionSnapshots.first?.quota
    }

    package var body: some View {
        HStack(spacing: 0) {
            if !leftCollapsed {
                SidebarView(
                    viewModel: viewModel,
                    displayedQuota: displayedQuota
                )
                    .frame(width: leftWidth)
                    .transition(.move(edge: .leading))

                DragHandle(direction: 1, width: $leftWidth, minWidth: 200, maxWidth: 400)
            }

            MainWorkspace(settings: settings, viewModel: viewModel)
                .frame(minWidth: 400, maxWidth: .infinity)

            if !rightCollapsed {
                DragHandle(direction: -1, width: $rightWidth, minWidth: 240, maxWidth: 420)

                HistoryPanel(onApply: { viewModel.text = $0 })
                    .frame(width: rightWidth)
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

        let snapshot = subscriptionSnapshots.first ?? SubscriptionQuotaSnapshot(
            characterCount: quota.characterCount,
            characterLimit: quota.characterLimit
        )

        if subscriptionSnapshots.isEmpty {
            modelContext.insert(snapshot)
        }

        snapshot.characterCount = quota.characterCount
        snapshot.characterLimit = quota.characterLimit
        snapshot.updatedAt = .now

        for staleSnapshot in subscriptionSnapshots.dropFirst() {
            modelContext.delete(staleSnapshot)
        }

        try? modelContext.save()
    }
}
