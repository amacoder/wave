//
//  HomeView.swift
//  Wave
//
//  Full transcription history UI with @Query, date grouping, stats, copy, delete, and undo toast
//

import SwiftUI
import SwiftData
import AppKit

struct HomeView: View {
    @Query(
        {
            var descriptor = FetchDescriptor<TranscriptionEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 200
            return descriptor
        }()
    ) private var entries: [TranscriptionEntry]

    @Environment(\.modelContext) private var modelContext
    @State private var pendingUndo: TranscriptionEntry? = nil
    @State private var undoToastTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if entries.isEmpty {
                EmptyStateView(
                    symbol: "waveform.and.mic",
                    title: "No transcriptions yet",
                    message: "Start dictating with the Fn key. Your transcription history will appear here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HistoryHeaderView(entries: entries)
                        Divider()
                        ForEach(groupedEntries, id: \.label) { group in
                            Text(group.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            ForEach(group.entries) { entry in
                                HistoryEntryRow(
                                    entry: entry,
                                    onCopy: { copyEntry(entry) },
                                    onDelete: { deleteEntry(entry) }
                                )
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            if pendingUndo != nil {
                UndoToastView(onUndo: undoDelete)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pendingUndo != nil)
    }

    // MARK: - Computed Properties

    private var groupedEntries: [(label: String, entries: [TranscriptionEntry])] {
        let calendar = Calendar.current
        let now = Date()
        let todayEntries = entries.filter { calendar.isDateInToday($0.timestamp) }
        let yesterdayEntries = entries.filter { calendar.isDateInYesterday($0.timestamp) }
        let thisWeekEntries = entries.filter {
            !calendar.isDateInToday($0.timestamp) &&
            !calendar.isDateInYesterday($0.timestamp) &&
            calendar.isDate($0.timestamp, equalTo: now, toGranularity: .weekOfYear)
        }
        let olderEntries = entries.filter {
            !calendar.isDateInToday($0.timestamp) &&
            !calendar.isDateInYesterday($0.timestamp) &&
            !calendar.isDate($0.timestamp, equalTo: now, toGranularity: .weekOfYear)
        }
        return [
            ("TODAY", todayEntries),
            ("YESTERDAY", yesterdayEntries),
            ("THIS WEEK", thisWeekEntries),
            ("OLDER", olderEntries),
        ].filter { !$0.entries.isEmpty }
    }

    // MARK: - Actions

    private func copyEntry(_ entry: TranscriptionEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.cleanedText, forType: .string)
    }

    private func deleteEntry(_ entry: TranscriptionEntry) {
        pendingUndo = entry
        modelContext.delete(entry)
        undoToastTask?.cancel()
        undoToastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                pendingUndo = nil
            }
        }
    }

    private func undoDelete() {
        guard let entry = pendingUndo else { return }
        modelContext.insert(entry)
        undoToastTask?.cancel()
        pendingUndo = nil
    }
}

// MARK: - HistoryHeaderView

private struct HistoryHeaderView: View {
    let entries: [TranscriptionEntry]

    private var streakDays: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        let days = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        while days.contains(calendar.startOfDay(for: checkDate)) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }

    private var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    private var averageWPM: Int {
        let totalMinutes = entries.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        guard totalMinutes > 0 else { return 0 }
        return Int(Double(totalWords) / totalMinutes)
    }

    private func formatNumber(_ n: Int) -> String {
        n.formatted()
    }

    var body: some View {
        HStack(alignment: .center) {
            let firstName = NSFullUserName().components(separatedBy: " ").first ?? NSUserName()
            Text("Welcome back, \(firstName)")
                .font(.title2)
                .bold()
            Spacer()
            HStack(spacing: 24) {
                StatBadge(emoji: "\u{1F4AA}", value: "\(streakDays)d", label: "streak")
                StatBadge(emoji: "\u{1F680}", value: formatNumber(totalWords), label: "words")
                StatBadge(emoji: "\u{1F3C6}", value: "\(averageWPM)", label: "avg wpm")
            }
        }
        .padding(16)
    }
}

// MARK: - StatBadge

private struct StatBadge: View {
    let emoji: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(emoji)
            Text(value)
                .font(.body.bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - HistoryEntryRow

private struct HistoryEntryRow: View {
    let entry: TranscriptionEntry
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(formatTimestamp(entry.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(entry.cleanedText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        copyAction()
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy transcription")
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .accessibilityLabel("Delete transcription")
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { copyAction() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .background(isHovered || isCopied ? Color.accentColor.opacity(0.08) : Color.clear)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func copyAction() {
        onCopy()
        isCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isCopied = false
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

// MARK: - UndoToastView

private struct UndoToastView: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Transcription deleted")
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
