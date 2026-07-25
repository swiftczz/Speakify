import AppKit
import SwiftData
import SwiftUI

struct HistoryPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \SpeechHistoryRecord.createdAt, order: .reverse) private var historyRecords: [SpeechHistoryRecord]
    let onApply: (SpeechHistoryDraft) -> Void
    @State private var searchText = ""
    @State private var selectedHistoryIDs = Set<PersistentIdentifier>()
    @State private var showsDeleteConfirmation = false
    @State private var groupedHistory: [HistorySectionData] = []

    var body: some View {
        List(selection: $selectedHistoryIDs) {
            ForEach(groupedHistory) { section in
                Section {
                    ForEach(section.items) { item in
                        HistoryRow(item: item, onApply: { onApply(item.draft) })
                            .tag(item.persistentModelID)
                            .contextMenu {
                                Button("Restore to editor") { onApply(item.draft) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    delete(ids: selectionIncluding(item))
                                }
                            }
                    }
                } header: {
                    Text(verbatim: section.title)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .overlay {
            if groupedHistory.isEmpty {
                emptyState
            }
        }
        .onDeleteCommand {
            guard selectedHistoryIDs.isEmpty == false else { return }
            showsDeleteConfirmation = true
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HistorySearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                delete(ids: selectedHistoryIDs)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes selected local history records from this Mac.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No history")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
        } description: {
            if searchText.isEmpty {
                Text("Generated speech shows up here.")
            } else {
                Text("No history matches this search.")
            }
        }
    }

    private func selectionIncluding(_ item: SpeechHistoryRecord) -> Set<PersistentIdentifier> {
        selectedHistoryIDs.contains(item.persistentModelID)
            ? selectedHistoryIDs
            : [item.persistentModelID]
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

    private func delete(ids: Set<PersistentIdentifier>) {
        let recordsToDelete = historyRecords.filter { ids.contains($0.persistentModelID) }
        recordsToDelete.forEach { modelContext.delete($0) }
        selectedHistoryIDs.subtract(ids)
        try? modelContext.save()
    }
}

private struct HistorySectionData: Identifiable {
    let date: Date
    let title: String
    let items: [SpeechHistoryRecord]

    var id: Date { date }
}

private struct HistoryRow: View {
    let item: SpeechHistoryRecord
    let onApply: () -> Void
    @State private var applyFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.preview)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(verbatim: item.voiceName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text(verbatim: item.durationText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                applyFeedback += 1
                onApply()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.callout)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : applyFeedback)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(Text("Restore to editor"))
            .accessibilityLabel(Text("Restore to editor"))
        }
        .padding(.vertical, 4)
    }
}

private struct HistorySearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = L10n.string(
            "Search history",
            defaultValue: "Search history"
        )
        field.setAccessibilityLabel(
            L10n.string("Search history", defaultValue: "Search history")
        )
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
