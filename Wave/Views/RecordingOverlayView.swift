//
//  RecordingOverlayView.swift
//  Wave
//
//  Compact pill overlay (Glaido-inspired) — icon + waveform/dots, no text
//

import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseScale: CGFloat = 1.0
    @State private var dotPhase: Int = 0
    @State private var dotTimer: Timer?

    var body: some View {
        HStack(spacing: 6) {
            // App icon (left side)
            Image("WaveOverlayIcon")
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // State indicator (right side)
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.softBlueWhite)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, appState.phase == .idle ? 6 : 10)
        .frame(height: 36)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.deepNavy.opacity(0.94))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .clipShape(Capsule())
        .animation(.spring(duration: 0.3, bounce: 0.1), value: appState.phase)
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

    // MARK: - Recording Waveform

    private var recordingWaveform: some View {
        Canvas { context, size in
            let levels = appState.audioLevels
            let barCount = min(levels.count, 12)
            guard barCount > 0 else { return }
            let gap: CGFloat = 2
            let barWidth: CGFloat = 3
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (size.width - totalWidth) / 2

            for i in 0..<barCount {
                let level = i < levels.count ? levels[i] : 0.1
                let barHeight = max(4, CGFloat(level) * size.height * 0.9)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = (size.height - barHeight) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(DesignSystem.Colors.vibrantBlue)
                )
            }
        }
        .frame(width: 60, height: 20)
    }

    // MARK: - Processing Dots

    private var processingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DesignSystem.Colors.softBlueWhite.opacity(dotPhase == i ? 1.0 : 0.3))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.3), value: dotPhase)
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

#Preview("Recording Overlay") {
    RecordingOverlayView()
        .environmentObject(AppState())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
