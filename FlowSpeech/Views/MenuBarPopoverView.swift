//
//  MenuBarPopoverView.swift
//  Wave
//
//  Quick access popover from menu bar
//

import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(DesignSystem.Colors.accentGradient)
                Text("Wave")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Status
            if appState.isRecording {
                RecordingStatusView()
            } else if appState.isTranscribing {
                TranscribingStatusView()
            } else {
                ReadyStatusView()
            }
            
            // Last transcription
            if let lastTranscription = appState.lastTranscription {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last transcription:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(lastTranscription)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lastTranscription, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            
            // Error
            if let error = appState.errorMessage {
                Divider()
                
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            Divider()
            
            // Quick actions
            HStack {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Status Views

struct ReadyStatusView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.green)
            
            Text("Ready")
                .font(.headline)
            
            Text("Hold \(appState.selectedHotkey.displayName) to record")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct RecordingStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .scaleEffect(pulse ? 1.2 : 1.0)

                Circle()
                    .fill(Color.red)
                    .frame(width: 20, height: 20)
            }

            Text("Recording...")
                .font(.headline)
                .foregroundColor(.red)

            // Mini waveform (Canvas single-pass)
            Canvas { context, size in
                let levels = appState.audioLevels
                let count = levels.count
                guard count > 0 else { return }
                let gap: CGFloat = 2
                let barWidth: CGFloat = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                for (i, level) in levels.enumerated() {
                    let barHeight = max(2, CGFloat(level) * size.height)
                    let x = CGFloat(i) * (barWidth + gap)
                    let y = (size.height - barHeight) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(DesignSystem.Colors.vibrantBlue)
                    )
                }
            }
            .frame(width: 120, height: 20)
        }
        .padding(.vertical, 8)
        .onChange(of: appState.phase) { _, newPhase in
            if newPhase == .recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.linear(duration: 0)) {
                    pulse = false
                }
            }
        }
        .onAppear {
            if appState.phase == .recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

struct TranscribingStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    DesignSystem.Colors.accentGradient,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))

            Text("Transcribing...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .onChange(of: appState.phase) { _, newPhase in
            if newPhase == .transcribing {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.linear(duration: 0)) {
                    rotation = 0
                }
            }
        }
        .onAppear {
            if appState.phase == .transcribing {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}

// MARK: - Compact Menu Bar View (Alternative)

struct CompactMenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(appState.selectedModel.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Menu items
            VStack(spacing: 0) {
                MenuBarButton(title: "Start Recording", shortcut: appState.selectedHotkey.displayName) {
                    // Toggle recording
                }
                
                MenuBarButton(title: "Settings...", shortcut: "⌘,") {
                    NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                MenuBarButton(title: "Quit Wave", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(width: 220)
    }
    
    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .orange }
        return .green
    }
    
    private var statusText: String {
        if appState.isRecording { return "Recording" }
        if appState.isTranscribing { return "Transcribing" }
        return "Ready"
    }
}

struct MenuBarButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovering ? Color.accentColor.opacity(0.2) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    MenuBarPopoverView()
        .environmentObject(AppState())
}
