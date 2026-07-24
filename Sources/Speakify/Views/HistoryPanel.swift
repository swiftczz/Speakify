import SwiftData
import SwiftUI

/// The right pane: past generations, grouped by day, searchable and deletable.
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
                .foregroundStyle(selectedHistoryIDs.isEmpty ? AppPalette.muted.opacity(0.45) : AppPalette.ink)
                .disabled(selectedHistoryIDs.isEmpty)
                .help(
                    L10n.string(
                        "Delete selected history",
                        defaultValue: "Delete selected history"
                    )
                )
            }
            .padding(.top, 34)

            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
                            onApply: onApply
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

    private var searchField: some View {
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
            Text(section.title)
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
    @State private var isApplying = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? AppPalette.ink : AppPalette.muted.opacity(0.55))
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
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isApplying ? AppPalette.accent : AppPalette.ink)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isApplying ? 1.4 : 1.0)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                L10n.string(
                    "Restore to editor",
                    defaultValue: "Restore to editor"
                )
            )
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
