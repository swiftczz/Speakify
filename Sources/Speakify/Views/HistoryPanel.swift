import SwiftData
import SwiftUI

/// The window's right pane: past generations, grouped by day, searchable and
/// deletable.
/// It takes only a callback rather than the view model, so playback progress
/// ticking ten times a second cannot drag it into a re-render.
struct HistoryPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \SpeechHistoryRecord.createdAt, order: .reverse) private var historyRecords: [SpeechHistoryRecord]
    let onApply: (SpeechHistoryDraft) -> Void
    @State private var searchText = ""
    @State private var selectedHistoryIDs = Set<PersistentIdentifier>()
    @State private var showsDeleteConfirmation = false
    /// Filtering, grouping and sorting run only when the records or the query
    /// change, not on every re-render the rest of the window triggers.
    @State private var groupedHistory: [HistorySectionData] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if groupedHistory.isEmpty {
                    Text("No history")
                        .font(.body)
                        .foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                }

                ForEach(groupedHistory) { section in
                    HistorySection(
                        section: section,
                        selectedHistoryIDs: $selectedHistoryIDs,
                        onApply: onApply
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
        // Width is set by the owning `HStack` in `ContentView`, not here. This panel
        // clips its trailing edge rather than reflowing when it is narrowed — the
        // delete button goes first, then each row's duration — so its width is fixed
        // and nothing is allowed to negotiate it away.
        //
        // `ignoresSafeArea` matches the sidebar: the background reaches up behind the
        // toolbar, so this pane's leading divider runs the window's full height rather
        // than starting halfway down.
        .background(AppPalette.contentBackground.ignoresSafeArea())
        // `.searchable` and `.toolbar` were tried here first: inside an inspector
        // both escape into the *window* toolbar, so the search field kept sitting
        // next to the service picker — and it stole enough width there to push the
        // voice picker out of the toolbar entirely. The panel owns its own header.
        .safeAreaInset(edge: .top, spacing: 0) {
            panelHeader
        }
        .onAppear(perform: rebuildGroupedHistory)
        .onChange(of: historyRecords) { _, _ in rebuildGroupedHistory() }
        .onChange(of: searchText) { _, _ in rebuildGroupedHistory() }
        .onChange(of: locale.identifier) { _, _ in rebuildGroupedHistory() }
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

    private var panelHeader: some View {
        HStack(spacing: 8) {
            TextField(text: $searchText) {
                Text("Search history")
            }
            .textFieldStyle(.roundedBorder)
            // A rounded-border field will not shrink below its natural width on its
            // own, and at the column's narrow end it pushed the delete button off
            // the trailing edge. This lets the field yield instead.
            .frame(minWidth: 40)
            .accessibilityLabel(Text("Search history"))

            if searchText.isEmpty == false {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }

            Button {
                showsDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(selectedHistoryIDs.isEmpty)
            .help(
                L10n.string(
                    "Delete selected history",
                    defaultValue: "Delete selected history"
                )
            )
            .accessibilityLabel(Text("Delete selected history"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func rebuildGroupedHistory() {
        let filtered: [SpeechHistoryRecord]
        if searchText.isEmpty {
            filtered = historyRecords
        } else {
            filtered = historyRecords.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.voiceName.localizedCaseInsensitiveContains(searchText)
            }
        }

        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        let grouped = Dictionary(grouping: filtered) { item in
            calendar.startOfDay(for: item.createdAt)
        }

        groupedHistory = grouped.keys
            .sorted(by: >)
            .map { day in
                HistorySectionData(
                    date: day,
                    title: Self.sectionTitle(for: day, calendar: calendar, locale: locale),
                    items: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
                )
            }
            .filter { $0.items.isEmpty == false }
    }

    private static func sectionTitle(for day: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDateInToday(day) {
            return L10n.string("history.today", defaultValue: "Today")
        }
        if calendar.isDateInYesterday(day) {
            return L10n.string("history.yesterday", defaultValue: "Yesterday")
        }
        return day.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(locale)
        )
    }

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
    let onApply: (SpeechHistoryDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: section.title)
                .font(.caption)
                .foregroundStyle(AppPalette.muted)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(section.items) { item in
                HistoryRow(
                    item: item,
                    isSelected: selectedHistoryIDs.contains(item.persistentModelID),
                    onApply: { onApply(item.draft) }
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
    /// Bumped on each press so the symbol replays its bounce. Replaces a pair of
    /// spring animations driven by an uncancellable `asyncAfter`.
    @State private var applyFeedback = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isSelected ? AppPalette.ink : AppPalette.muted.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: item.preview)
                    .font(.body)
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(verbatim: item.voiceName)
                    .font(.callout)
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(verbatim: item.durationText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(AppPalette.muted)

            Button {
                applyFeedback += 1
                onApply()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.ink)
                    .symbolEffect(.bounce, value: applyFeedback)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                L10n.string(
                    "Restore to editor",
                    defaultValue: "Restore to editor"
                )
            )
            .accessibilityLabel(Text("Restore to editor"))
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
