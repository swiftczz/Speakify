import AppKit
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
        // A `List`, not a `ScrollView` of stacked rows. The rows looked the same either
        // way, but everything the system attaches to a list was missing: arrow keys,
        // shift-click ranges, ⌘-click, ⌘A, and the delete key. Selection was a
        // hand-drawn circle per row and a hand-painted highlight behind it, both of
        // which are the list's job and neither of which followed the window's focus.
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
        .listStyle(.inset)
        .overlay {
            if groupedHistory.isEmpty {
                emptyState
            }
        }
        // The delete key, which the old hand-rolled list had no way to receive. The
        // trailing trash button it replaces lived in a custom header bar; the same
        // action is on every row's context menu.
        .onDeleteCommand {
            guard selectedHistoryIDs.isEmpty == false else { return }
            showsDeleteConfirmation = true
        }
        // The search field lives in the panel, not in `.searchable`.
        //
        // `.searchable` is the usual answer and it does produce a real search control,
        // but from inside an inspector it escapes into the *window* toolbar — and there
        // it sat across the inspector's own leading divider, hiding it, while its width
        // pushed the history toggle in off the trailing edge. An `NSSearchField` keeps
        // the genuine control (magnifier, clear button, focus ring, Escape to clear)
        // and keeps it inside the column it belongs to.
        .safeAreaInset(edge: .top, spacing: 0) {
            HistorySearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        // No background of its own: this is the split view's inspector column, so the
        // material, the leading separator and the drag handle are the system's to draw.
        // Width bounds are set by the `inspectorColumnWidth` in `ContentView`.
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

    /// Right-clicking a row outside the selection acts on that row alone, which is
    /// what every macOS list does; inside it, on the whole selection.
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
    /// Bumped on each press so the symbol replays its bounce. Replaces a pair of
    /// spring animations driven by an uncancellable `asyncAfter`.
    @State private var applyFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // No selection circle and no selection background. Both are the list's now,
        // which is also what makes them follow the window's focus state.
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.preview)
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

/// The system search field, wrapped.
///
/// SwiftUI has no search-field *style* — `.searchable` is the only route to the real
/// control, and in an inspector that route ends in the window toolbar. Wrapping
/// `NSSearchField` gets the same control (magnifier, clear button, focus ring, Escape
/// to clear, and the field's own menu) in a view that stays in this column.
///
/// The alternative was a `TextField` dressed up with a magnifying-glass image and a
/// hand-drawn clear button, which is what this replaced in the first place.
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
        // Fire on every keystroke rather than only on Return: the list filters live.
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.text = $text
        // Only when they differ, or assigning mid-edit would reset the insertion point.
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
