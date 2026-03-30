//
//  DictionaryView.swift
//  Wave
//
//  Full CRUD list view for managing custom vocabulary and abbreviations.
//  Vocabulary hints improve Whisper transcription accuracy;
//  abbreviations expand post-transcription via DictionaryService.
//

import SwiftUI
import SwiftData

// MARK: - EditingDictionaryState

struct EditingDictionaryState: Identifiable {
    let id = UUID()
    var existingID: UUID? = nil   // nil = adding new, non-nil = editing
    var term: String = ""
    var replacement: String = ""
    var isAbbreviation: Bool = false

    init() {}

    init(from entry: DictionaryWord) {
        existingID = entry.id
        term = entry.term
        replacement = entry.replacement ?? ""
        isAbbreviation = entry.isAbbreviation
    }
}

// MARK: - DictionaryView

struct DictionaryView: View {
    @Query(sort: \DictionaryWord.createdAt, order: .reverse) private var entries: [DictionaryWord]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var editingEntry: EditingDictionaryState? = nil
    @State private var pendingUndo: DictionaryWord? = nil
    @State private var undoToastTask: Task<Void, Never>? = nil

    let promptCharLimit = 1_100

    // MARK: - Computed Properties

    private var filteredEntries: [DictionaryWord] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter {
            $0.term.localizedCaseInsensitiveContains(searchText) ||
            ($0.replacement?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var promptCharCount: Int {
        let terms = entries.filter { !$0.isAbbreviation }.map { $0.term }
        guard !terms.isEmpty else { return 0 }
        return "In this transcript: \(terms.joined(separator: ", ")).".count
    }

    private var countColor: Color {
        let ratio = Double(promptCharCount) / Double(promptCharLimit)
        if ratio < 0.70 {
            return .green
        } else if ratio < 0.90 {
            return .yellow
        } else {
            return .red
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Dictionary")
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                if entries.isEmpty && searchText.isEmpty {
                    EmptyStateView(
                        symbol: "character.book.closed",
                        title: "Your dictionary is empty",
                        message: "Add custom words to help Wave transcribe your vocabulary accurately."
                    )
                } else {
                    List(filteredEntries) { entry in
                        DictionaryEntryRow(
                            entry: entry,
                            onEdit: {
                                editingEntry = EditingDictionaryState(from: entry)
                            },
                            onDelete: {
                                deleteEntry(entry)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.visible)
                    }
                    .listStyle(.plain)
                }

                Divider()
                PromptCharCountBar(
                    promptCharCount: promptCharCount,
                    promptCharLimit: promptCharLimit,
                    countColor: countColor
                )
            }

            if pendingUndo != nil {
                UndoDictionaryToast(onUndo: undoDelete)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pendingUndo != nil)
        .searchable(text: $searchText, prompt: "Search dictionary")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingEntry = EditingDictionaryState()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add word")
            }
        }
        .sheet(item: $editingEntry) { state in
            DictionaryEditSheet(
                state: state,
                onSave: { saveEntry($0) },
                onDiscard: { editingEntry = nil }
            )
        }
    }

    // MARK: - Actions

    private func saveEntry(_ state: EditingDictionaryState) {
        if let existingID = state.existingID {
            if let entry = entries.first(where: { $0.id == existingID }) {
                entry.term = state.term
                entry.replacement = state.isAbbreviation ? state.replacement : nil
                entry.isAbbreviation = state.isAbbreviation
            }
        } else {
            let newEntry = DictionaryWord(
                term: state.term,
                replacement: state.isAbbreviation ? state.replacement : nil,
                isAbbreviation: state.isAbbreviation
            )
            modelContext.insert(newEntry)
        }
        editingEntry = nil
    }

    private func deleteEntry(_ entry: DictionaryWord) {
        undoToastTask?.cancel()
        pendingUndo = entry
        modelContext.delete(entry)
        undoToastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                pendingUndo = nil
            }
        }
    }

    private func undoDelete() {
        guard let entry = pendingUndo else { return }
        undoToastTask?.cancel()
        modelContext.insert(entry)
        pendingUndo = nil
    }
}

// MARK: - DictionaryEntryRow

private struct DictionaryEntryRow: View {
    let entry: DictionaryWord
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            if entry.isAbbreviation {
                Text(entry.term)
                    .font(.body)
                Text("\u{2192}")
                    .foregroundColor(.secondary)
                Text(entry.replacement ?? "")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Text(entry.term)
                    .font(.body)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            if isHovered {
                HStack(spacing: 8) {
                    Button { onEdit() } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Edit \(entry.term)")
                    Button { onDelete() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .accessibilityLabel("Delete \(entry.term)")
                }
                .transition(.opacity)
            }
        }
        .background(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - DictionaryEditSheet

private struct DictionaryEditSheet: View {
    let state: EditingDictionaryState
    let onSave: (EditingDictionaryState) -> Void
    let onDiscard: () -> Void

    @State private var term: String
    @State private var replacement: String
    @State private var isAbbreviation: Bool

    init(state: EditingDictionaryState, onSave: @escaping (EditingDictionaryState) -> Void, onDiscard: @escaping () -> Void) {
        self.state = state
        self.onSave = onSave
        self.onDiscard = onDiscard
        _term = State(initialValue: state.term)
        _replacement = State(initialValue: state.replacement)
        _isAbbreviation = State(initialValue: state.isAbbreviation)
    }

    private var title: String {
        state.existingID == nil ? "Add Word" : "Edit Word"
    }

    private var confirmLabel: String {
        state.existingID == nil ? "Save Word" : "Update Word"
    }

    private var isConfirmDisabled: Bool {
        term.isEmpty || (isAbbreviation && replacement.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("Term")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., Kubernetes", text: $term)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Abbreviation", isOn: $isAbbreviation)

            if isAbbreviation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expands to")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., by the way", text: $replacement)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer()

            HStack {
                Button("Discard") {
                    onDiscard()
                }

                Spacer()

                Button(confirmLabel) {
                    var updated = state
                    updated.term = term
                    updated.replacement = replacement
                    updated.isAbbreviation = isAbbreviation
                    onSave(updated)
                }
                .disabled(isConfirmDisabled)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(minWidth: 380)
        .animation(.easeInOut(duration: 0.2), value: isAbbreviation)
    }
}

// MARK: - PromptCharCountBar

private struct PromptCharCountBar: View {
    let promptCharCount: Int
    let promptCharLimit: Int
    let countColor: Color

    private var ratio: Double {
        min(Double(promptCharCount) / Double(promptCharLimit), 1.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(countColor.opacity(0.6))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(promptCharCount) / \(promptCharLimit) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if promptCharCount > promptCharLimit {
                    Text("Limit reached — oldest terms omitted")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.3), value: countColor)
        .animation(.easeInOut(duration: 0.3), value: ratio)
        .accessibilityLabel("Prompt usage: \(promptCharCount) of 1100 characters")
    }
}

// MARK: - UndoDictionaryToast

private struct UndoDictionaryToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Word deleted")
                .font(.body)
            Button("Undo") {
                onUndo()
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .accessibilityLabel("Undo delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
