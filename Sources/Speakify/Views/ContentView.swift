import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionQuotaSnapshot.updatedAt, order: .reverse) private var subscriptionSnapshots: [SubscriptionQuotaSnapshot]
    @StateObject private var settings: AppSettings
    @StateObject private var viewModel: SpeechViewModel
    @State private var showsSettings = false
    @State private var leftWidth: CGFloat = 258
    @State private var rightWidth: CGFloat = 310
    @State private var leftCollapsed = false
    @State private var rightCollapsed = false

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: SpeechViewModel(settings: settings))
    }

    private var displayedSubscription: ElevenLabsSubscription? {
        viewModel.subscription ?? subscriptionSnapshots.first?.subscription
    }

    var body: some View {
        HStack(spacing: 0) {
            if !leftCollapsed {
                SidebarView(
                    showsSettings: $showsSettings,
                    viewModel: viewModel,
                    displayedSubscription: displayedSubscription
                )
                    .frame(width: leftWidth)
                    .transition(.move(edge: .leading))

                DragHandle(direction: 1, width: $leftWidth, minWidth: 200, maxWidth: 400)
            }

            MainWorkspace(settings: settings, viewModel: viewModel)
                .frame(minWidth: 400, maxWidth: .infinity)

            if !rightCollapsed {
                DragHandle(direction: -1, width: $rightWidth, minWidth: 240, maxWidth: 420)

                HistoryPanel(viewModel: viewModel)
                    .frame(width: rightWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(AppPalette.contentBackground)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        leftCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        rightCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
            }
        }
        .task {
            if settings.apiKey.isEmpty == false, viewModel.voices.isEmpty {
                await viewModel.loadModelsAndVoices()
            }
        }
        .onChange(of: viewModel.subscription) { _, newValue in
            persistSubscriptionSnapshot(newValue)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(settings: settings)
                .frame(width: 560, height: 360)
        }
    }

    private func persistSubscriptionSnapshot(_ subscription: ElevenLabsSubscription?) {
        guard let subscription else { return }

        let snapshot = subscriptionSnapshots.first ?? SubscriptionQuotaSnapshot(
            characterCount: subscription.characterCount,
            characterLimit: subscription.characterLimit
        )

        if subscriptionSnapshots.isEmpty {
            modelContext.insert(snapshot)
        }

        snapshot.characterCount = subscription.characterCount
        snapshot.characterLimit = subscription.characterLimit
        snapshot.updatedAt = .now

        for staleSnapshot in subscriptionSnapshots.dropFirst() {
            modelContext.delete(staleSnapshot)
        }

        try? modelContext.save()
    }
}

private struct SidebarView: View {
    @Binding var showsSettings: Bool
    @ObservedObject var viewModel: SpeechViewModel
    let displayedSubscription: ElevenLabsSubscription?
    @State private var isHoveringSettings = false

    private let primaryItems = [
        NavItem(title: "Text to Speech", icon: "waveform", selected: true),
        NavItem(title: "Voices", icon: "person.wave.2"),
        NavItem(title: "Voice Cloning", icon: "person.crop.circle.badge.plus"),
        NavItem(title: "Voice Library", icon: "books.vertical"),
        NavItem(title: "Projects", icon: "folder")
    ]

    private let secondaryItems = [
        NavItem(title: "History", icon: "clock.arrow.circlepath"),
        NavItem(title: "Templates", icon: "square.grid.2x2")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 14)

            VStack(spacing: 5) {
                ForEach(primaryItems) { item in
                    SidebarRow(item: item)
                }
            }

            Divider()
                .padding(.trailing, 4)

            VStack(spacing: 5) {
                ForEach(secondaryItems) { item in
                    SidebarRow(item: item)
                }
            }

            Spacer(minLength: 20)

            QuotaWidget(subscription: displayedSubscription)
                .padding(.bottom, 8)

            Button {
                showsSettings = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .frame(width: 24)
                    Text("Settings")
                        .font(.system(size: 14, weight: .regular))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.controlBackground)
                    .opacity(isHoveringSettings ? 1 : 0)
            }
            .onHover { isHoveringSettings = $0 }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .background(AppPalette.sidebarBackground)
    }
}

private struct MainWorkspace: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: SpeechViewModel

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Text to Speech")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.ink)

                Spacer()

                GenerationToolbar(settings: settings, viewModel: viewModel)
            }

            EditorCard(viewModel: viewModel)
                .frame(minHeight: 320, maxHeight: .infinity)

            PlayerBar(settings: settings, viewModel: viewModel)
                .frame(height: 80)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(AppPalette.contentBackground)
    }
}

private struct EditorCard: View {
    @ObservedObject var viewModel: SpeechViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $viewModel.text)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(8)
                .scrollContentBackground(.hidden)
                .foregroundStyle(AppPalette.ink)
                .padding(22)

            HStack {
                Text("\(viewModel.text.count) / 5000")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppPalette.muted)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)
    }

}

private struct GenerationToolbar: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: SpeechViewModel

    var body: some View {
        HStack(spacing: 10) {
            OptionRow(title: "Model") {
                Picker("Model", selection: $settings.modelID) {
                    ForEach(viewModel.models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 142)
            }

            OptionRow(title: "Voice") {
                Picker("Voice", selection: $viewModel.selectedVoice) {
                    Text("Select").tag(Optional<TTSVoice>.none)
                    ForEach(viewModel.voices) { voice in
                        Text(voice.displayName).tag(Optional(voice))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(AppPalette.controlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct OptionRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
                .frame(width: 38, alignment: .leading)

            content
        }
    }
}

private struct PlayerBar: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: SpeechViewModel
    @State private var isAnimatingPlayButton = false
    @State private var isAnimatingDownloadButton = false
    @State private var isHoveringDownloadButton = false
    @State private var downloadCompletionProgress: CGFloat = 0
    @State private var downloadCompletionOpacity = 0.0
    @State private var showsDownloadCompletionRing = false
    @State private var dismissDownloadCompletionTask: Task<Void, Never>?
    private let playbackTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 16) {
            AudioStatusView(
                isActive: viewModel.isPlaying || viewModel.isGenerating,
                progress: viewModel.playbackProgress
            )
                .frame(height: 38)

            Text(viewModel.isGenerating ? "Generating" : viewModel.playbackTimeText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)

            PlaybackRateControl(settings: settings)

            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                    isAnimatingPlayButton = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        isAnimatingPlayButton = false
                    }
                }

                if viewModel.isPlaying {
                    viewModel.stop()
                } else {
                    Task { await viewModel.play(modelContext: modelContext) }
                }
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isAnimatingPlayButton ? AppPalette.accent : AppPalette.ink)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0)
                    .scaleEffect(isAnimatingPlayButton ? 1.15 : 1)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.canGenerate == false && viewModel.isPlaying == false)

            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                    isAnimatingDownloadButton = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        isAnimatingDownloadButton = false
                    }
                }

                Task { await viewModel.download(modelContext: modelContext) }
            } label: {
                ZStack {
                    if showsDownloadCompletionRing {
                        Circle()
                            .trim(from: 0, to: downloadCompletionProgress)
                            .stroke(
                                AppPalette.accent,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                            )
                            .frame(width: 34, height: 34)
                            .rotationEffect(.degrees(-90))
                            .opacity(downloadCompletionOpacity)
                    }

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            viewModel.canGenerate
                                ? (isAnimatingDownloadButton ? AppPalette.accent : AppPalette.ink)
                                : AppPalette.ink.opacity(0.35)
                        )
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0)
                        .scaleEffect(isAnimatingDownloadButton ? 1.15 : 1)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.canGenerate == false)
            .zIndex(isHoveringDownloadButton ? 1 : 0)
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    isHoveringDownloadButton = isHovering
                }
            }
        }
        .padding(.horizontal, 14)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)
        .overlay(alignment: .topTrailing) {
            if isHoveringDownloadButton {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download directory")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)

                    Text(settings.downloadDirectoryPath)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .fixedSize(horizontal: true, vertical: false)
                .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .padding(.trailing, 10)
                .offset(y: -58)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                .allowsHitTesting(false)
            }
        }
        .onReceive(playbackTimer) { _ in
            viewModel.refreshPlaybackProgress()
        }
        .onChange(of: viewModel.downloadFeedback?.id) { _, newValue in
            guard newValue != nil else { return }
            playDownloadCompletionRing()
        }
    }

    private func playDownloadCompletionRing() {
        dismissDownloadCompletionTask?.cancel()
        downloadCompletionProgress = 0
        downloadCompletionOpacity = 1
        showsDownloadCompletionRing = true

        withAnimation(.easeOut(duration: 0.55)) {
            downloadCompletionProgress = 1
        }

        dismissDownloadCompletionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard Task.isCancelled == false else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                downloadCompletionOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard Task.isCancelled == false else { return }

            showsDownloadCompletionRing = false
            downloadCompletionProgress = 0
        }
    }
}

private struct PlaybackRateControl: View {
    @ObservedObject var settings: AppSettings
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .font(.system(size: 12, weight: .semibold))
                Text(Self.label(for: settings.playbackRate))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(AppPalette.ink)
            .padding(.horizontal, 10)
            .frame(width: 76, height: 30)
            .background(AppPalette.controlBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Playback speed")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(Self.label(for: settings.playbackRate))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }

                Slider(value: $settings.playbackRate, in: 0.25...2.0, step: 0.25)

                HStack {
                    Text("0.25x")
                    Spacer()
                    Text("2.0x")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            }
            .padding(16)
            .frame(width: 260)
        }
    }

    static func label(for rate: Double) -> String {
        let roundedRate = (rate * 100).rounded() / 100
        if roundedRate.rounded() == roundedRate {
            return String(format: "%.1fx", roundedRate)
        }
        if (roundedRate * 10).rounded() == roundedRate * 10 {
            return String(format: "%.1fx", roundedRate)
        }
        return String(format: "%.2fx", roundedRate)
    }
}

private struct HistoryPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpeechHistoryRecord.createdAt, order: .reverse) private var historyRecords: [SpeechHistoryRecord]
    @ObservedObject var viewModel: SpeechViewModel
    @State private var searchText = ""
    @State private var selectedHistoryIDs = Set<PersistentIdentifier>()
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("History")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppPalette.ink)

                Spacer()

                Button {
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedHistoryIDs.isEmpty ? AppPalette.muted.opacity(0.45) : .black)
                .disabled(selectedHistoryIDs.isEmpty)
                .help("Delete selected history")
            }
            .padding(.top, 34)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppPalette.muted)
                TextField("Search history", text: $searchText)
                    .font(.system(size: 13, weight: .regular))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(AppPalette.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if groupedHistory.isEmpty {
                        Text("No history")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppPalette.muted)
                            .padding(.top, 12)
                    }

                    ForEach(groupedHistory) { section in
                        HistorySection(
                            section: section,
                            selectedHistoryIDs: $selectedHistoryIDs,
                            onApply: { text in viewModel.text = text }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .background(AppPalette.contentBackground)
        .confirmationDialog(
            "Delete selected history?",
            isPresented: $showsDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes selected local history records from this Mac.")
        }
    }

    private var filteredHistory: [SpeechHistoryRecord] {
        guard searchText.isEmpty == false else { return historyRecords }
        return historyRecords.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.voiceName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedHistory: [HistorySectionData] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredHistory) { item in
            calendar.startOfDay(for: item.createdAt)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                HistorySectionData(
                    date: day,
                    title: historySectionTitle(for: day, calendar: calendar),
                    items: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
                )
            }
            .filter { $0.items.isEmpty == false }
    }

    private func historySectionTitle(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        return Self.historyDateFormatter.string(from: day)
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func deleteSelectedHistory() {
        let recordsToDelete = historyRecords.filter {
            selectedHistoryIDs.contains($0.persistentModelID)
        }
        recordsToDelete.forEach { modelContext.delete($0) }
        selectedHistoryIDs.removeAll()
        try? modelContext.save()
    }
}

private struct HistorySectionData: Identifiable {
    let date: Date
    let title: String
    let items: [SpeechHistoryRecord]

    var id: Date { date }
}

private struct HistorySection: View {
    let section: HistorySectionData
    @Binding var selectedHistoryIDs: Set<PersistentIdentifier>
    let onApply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.caption)
                .foregroundStyle(AppPalette.muted)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(section.items) { item in
                HistoryRow(
                    item: item,
                    isSelected: selectedHistoryIDs.contains(item.persistentModelID),
                    onApply: { onApply(item.title) }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(for: item)
                }
                Divider()
            }
        }
    }

    private func toggleSelection(for item: SpeechHistoryRecord) {
        let id = item.persistentModelID
        if selectedHistoryIDs.contains(id) {
            selectedHistoryIDs.remove(id)
        } else {
            selectedHistoryIDs.insert(id)
        }
    }
}

private struct HistoryRow: View {
    let item: SpeechHistoryRecord
    let isSelected: Bool
    let onApply: () -> Void
    @State private var isApplying = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? .black : AppPalette.muted.opacity(0.55))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.preview)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.voiceName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(item.durationText)
                .font(.system(size: 12, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(AppPalette.muted)

            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isApplying = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        isApplying = false
                    }
                }
                onApply()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isApplying ? AppPalette.accent : AppPalette.ink)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isApplying ? 1.4 : 1.0)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Apply text to editor")
        }
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppPalette.selectedNav)
            }
        }
    }
}

private struct AudioStatusView: View {
    let isActive: Bool
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "waveform.circle.fill" : "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .symbolEffect(.pulse, isActive: isActive)

            ProgressView(value: progress)
                .tint(AppPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarRow: View {
    let item: NavItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 17))
                .frame(width: 24)

            Text(item.title)
                .font(.system(size: 14, weight: .regular))

            Spacer()

            if let badge = item.badge {
                Text(badge)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.80), in: Capsule())
                    .overlay {
                        Capsule().stroke(AppPalette.stroke, lineWidth: 1)
                    }
            }
        }
        .foregroundStyle(item.selected ? AppPalette.accent : AppPalette.ink)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background {
            if item.selected {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppPalette.selectedNav)
            }
        }
    }
}

private struct Chip: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppPalette.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppPalette.stroke, lineWidth: 1)
            }
    }
}

private struct DragHandle: View {
    /// +1 = leading handle (drag right → wider), -1 = trailing handle (drag right → narrower)
    let direction: Int
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .fill(isHovering ? AppPalette.accent.opacity(0.6) : AppPalette.stroke)
                    .frame(width: 1)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startWidth = width
                        }
                        let delta = CGFloat(direction) * value.translation.width
                        width = max(minWidth, min(maxWidth, startWidth + delta))
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovering {
                            NSCursor.pop()
                        }
                    }
            )
    }
}

private struct QuotaWidget: View {
    let subscription: ElevenLabsSubscription?

    private var remainingCredits: Int {
        subscription?.remaining ?? 0
    }

    private var formattedRemaining: String {
        let n = remainingCredits
        return "\(n)"
    }

    private var formattedTotal: String {
        let n = subscription?.characterLimit ?? 0
        return "\(n)"
    }

    private var progressValue: Double {
        subscription?.usedFraction ?? 0
    }

    private var progressColor: Color {
        if remainingCredits < 1000 {
            return .red
        }
        if remainingCredits < 3000 {
            return .yellow
        }
        return .green
    }

    private var ratioText: String {
        "\(formattedRemaining) / \(formattedTotal)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credits (Remaining/Total)")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(ratioText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(AppPalette.stroke.opacity(0.24))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(AppPalette.stroke.opacity(0.45), lineWidth: 0.5)
                        }

                    Capsule(style: .continuous)
                        .fill(progressColor)
                        .frame(width: geo.size.width * progressValue)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct NavItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var selected = false
    var badge: String?
}

private enum AppPalette {
    static let ink = Color(NSColor.labelColor)
    static let muted = Color(NSColor.secondaryLabelColor)
    static let stroke = Color(NSColor.separatorColor)
    static let accent = Color(NSColor.controlAccentColor)
    static let selectedNav = Color(NSColor.selectedContentBackgroundColor).opacity(0.12)
    static let sidebarBackground = Color(NSColor.windowBackgroundColor)
    static let contentBackground = Color(NSColor.controlBackgroundColor)
    static let cardBackground = Color(NSColor.controlBackgroundColor)
    static let controlBackground = Color(NSColor.controlColor)
    static let cardSurface = Color(NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    }))
}
