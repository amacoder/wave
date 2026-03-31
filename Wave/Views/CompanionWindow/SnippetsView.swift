//
//  SnippetsView.swift
//  Wave
//
//  Full CRUD list view for managing text expansion snippets.
//  Trigger phrases entered here are expanded during dictation post-processing.
//

import SwiftUI
import SwiftData

// MARK: - EditingSnippetState

struct EditingSnippetState: Identifiable {
    let id = UUID()
    var existingID: UUID? = nil
    var trigger: String = ""
    var expansion: String = ""

    init() {}

    init(from snippet: Snippet) {
        existingID = snippet.id
        trigger = snippet.trigger
        expansion = snippet.expansion
    }
}

// MARK: - SnippetsView

struct SnippetsView: View {
    @Query(sort: \Snippet.createdAt, order: .reverse) private var entries: [Snippet]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var editingSnippet: EditingSnippetState? = nil
    @State private var pendingUndo: Snippet? = nil
    @State private var undoToastTask: Task<Void, Never>? = nil

    private var filteredEntries: [Snippet] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter {
            $0.trigger.localizedCaseInsensitiveContains(searchText) ||
            $0.expansion.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Snippets")
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                if entries.isEmpty && searchText.isEmpty {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "No snippets yet",
                        message: "Create trigger phrases that automatically expand into longer text after each dictation."
                    )
                } else {
                    List(filteredEntries) { entry in
                        SnippetEntryRow(
                            entry: entry,
                            onEdit: {
                                editingSnippet = EditingSnippetState(from: entry)
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
            }

            if pendingUndo != nil {
                UndoSnippetToast(onUndo: undoDelete)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pendingUndo != nil)
        .searchable(text: $searchText, prompt: "Search snippets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingSnippet = EditingSnippetState()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add snippet")
            }
        }
        .sheet(item: $editingSnippet) { state in
            SnippetEditSheet(
                state: state,
                onSave: { saveSnippet($0) },
                onDiscard: { editingSnippet = nil }
            )
        }
    }

    // MARK: - Actions

    private func saveSnippet(_ state: EditingSnippetState) {
        if let existingID = state.existingID {
            if let existing = entries.first(where: { $0.id == existingID }) {
                existing.trigger = state.trigger
                existing.expansion = state.expansion
            }
        } else {
            let snippet = Snippet(trigger: state.trigger, expansion: state.expansion)
            modelContext.insert(snippet)
        }
        editingSnippet = nil
    }

    private func deleteEntry(_ entry: Snippet) {
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

// MARK: - SnippetEntryRow

private struct SnippetEntryRow: View {
    let entry: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var truncatedExpansion: String {
        entry.expansion.count > 60
            ? String(entry.expansion.prefix(60)) + "..."
            : entry.expansion
    }

    var body: some View {
        HStack {
            Text(entry.trigger)
                .font(.body)
            Text("\u{2192}")
                .foregroundColor(.secondary)
            Text(truncatedExpansion)
                .font(.body)
                .foregroundColor(.secondary)
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
                        .accessibilityLabel("Edit \(entry.trigger)")
                    Button { onDelete() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .accessibilityLabel("Delete \(entry.trigger)")
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

// MARK: - SnippetEditSheet

private struct SnippetEditSheet: View {
    let state: EditingSnippetState
    let onSave: (EditingSnippetState) -> Void
    let onDiscard: () -> Void

    @State private var trigger: String
    @State private var expansion: String

    init(state: EditingSnippetState, onSave: @escaping (EditingSnippetState) -> Void, onDiscard: @escaping () -> Void) {
        self.state = state
        self.onSave = onSave
        self.onDiscard = onDiscard
        _trigger = State(initialValue: state.trigger)
        _expansion = State(initialValue: state.expansion)
    }

    private var title: String {
        state.existingID == nil ? "Add Snippet" : "Edit Snippet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger phrase")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., sig", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                Text("Say this word during dictation to expand it")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Expands to")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $expansion)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                    if expansion.isEmpty {
                        Text("e.g., Amadeus Radunz")
                            .font(.body)
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }

            HStack {
                Button("Discard") {
                    onDiscard()
                }
                Spacer()
                Button(state.existingID == nil ? "Save Snippet" : "Update Snippet") {
                    var updated = state
                    updated.trigger = trigger
                    updated.expansion = expansion
                    onSave(updated)
                }
                .disabled(trigger.isEmpty || expansion.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(minWidth: 400)
    }
}

// MARK: - UndoSnippetToast

private struct UndoSnippetToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Snippet deleted")
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
