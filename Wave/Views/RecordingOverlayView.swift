//
//  RecordingOverlayView.swift
//  Wave
//
//  Compact pill overlay (Glaido-inspired) — icon + waveform/dots, no text
//

import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState
    @State private var dotPhase: Int = 0
    @State private var dotTimer: Timer?

    var body: some View {
        // Minimal pill: no icon, just the state indicator
        HStack(spacing: 5) {
            Group {
                switch appState.phase {
                case .idle:
                    EmptyView()
                case .recording:
                    recordingWaveform
                case .transcribing:
                    processingDots
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textOnDark)
                case .error(let message):
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textOnDark)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            // Crossfade between phase contents instead of hard-swapping;
            // the container spring below only animates the frame.
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .id(phaseContentID)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(minWidth: 56)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.surfaceDark.opacity(0.94))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        )
        .clipShape(Capsule())
        .animation(.spring(duration: 0.22, bounce: 0.05), value: appState.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatus)
        .onChange(of: appState.phase) { _, newPhase in
            if newPhase == .transcribing {
                startDotAnimation()
            } else {
                stopDotAnimation()
            }
        }
        .onAppear {
            if appState.phase == .transcribing {
                startDotAnimation()
            }
        }
        .onDisappear {
            stopDotAnimation()
        }
    }

    /// Stable identity per phase-content so SwiftUI runs insert/remove
    /// transitions when the content switches (error messages share one ID).
    private var phaseContentID: String {
        switch appState.phase {
        case .idle: return "idle"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .done: return "done"
        case .error: return "error"
        }
    }

    private var accessibilityStatus: String {
        switch appState.phase {
        case .idle: return "Wave idle"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .done: return "Transcription done"
        case .error(let message): return "Error: \(message)"
        }
    }

    // MARK: - Recording Waveform

    private var recordingWaveform: some View {
        WaveformView()
    }

    // MARK: - Processing Dots

    private var processingDots: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DesignSystem.Colors.textOnDark.opacity(dotPhase == i ? 1.0 : 0.3))
                    .frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.25), value: dotPhase)
            }
        }
    }

    private func startDotAnimation() {
        dotPhase = 0
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            dotPhase = (dotPhase + 1) % 3
        }
    }

    private func stopDotAnimation() {
        dotTimer?.invalidate()
        dotTimer = nil
        dotPhase = 0
    }
}

// MARK: - Waveform Subview

/// Observes AudioLevelModel in isolation so the 20Hz level stream only
/// redraws this Canvas, not the whole pill.
private struct WaveformView: View {
    @EnvironmentObject var audioLevels: AudioLevelModel

    var body: some View {
        Canvas { context, size in
            let levels = audioLevels.levels
            let barCount = min(levels.count, 12)
            guard barCount > 0 else { return }
            let gap: CGFloat = 2
            let barWidth: CGFloat = 2.5
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (size.width - totalWidth) / 2

            for i in 0..<barCount {
                let level = i < levels.count ? levels[i] : 0.1
                let barHeight = max(3, CGFloat(level) * size.height * 0.9)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = (size.height - barHeight) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.25),
                    with: .color(DesignSystem.Colors.accent)
                )
            }
        }
        .frame(width: 52, height: 16)
    }
}

#Preview("Recording Overlay") {
    RecordingOverlayView()
        .environmentObject(AppState())
        .environmentObject(AudioLevelModel())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
