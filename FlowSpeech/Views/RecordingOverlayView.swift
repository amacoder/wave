//
//  RecordingOverlayView.swift
//  FlowSpeech
//
//  Pill overlay with 4-state ZStack, Canvas waveform, and spring transitions
//

import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseScale: CGFloat = 1.0
    @State private var spinnerRotation: Double = 0

    var body: some View {
        ZStack {
            if appState.phase == .idle {
                idleState
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(appState.phase == .idle ? 1 : 0)
            } else if appState.phase == .recording {
                recordingState
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(appState.phase == .recording ? 1 : 0)
            } else if appState.phase == .transcribing {
                transcribingState
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(appState.phase == .transcribing ? 1 : 0)
            } else if appState.phase == .done {
                doneState
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(appState.phase == .done ? 1 : 0)
            }
        }
        .frame(width: 280, height: 52)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.deepNavy.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        )
        .clipShape(Capsule())
        .animation(.spring(duration: 0.35, bounce: 0.1), value: appState.phase)
        .onChange(of: appState.phase) { _, newPhase in
            // Phase-gated animations (FNDTN-04 pattern)
            if newPhase == .recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            } else {
                withAnimation(.linear(duration: 0)) {
                    pulseScale = 1.0
                }
            }

            if newPhase == .transcribing {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    spinnerRotation = 360
                }
            } else {
                withAnimation(.linear(duration: 0)) {
                    spinnerRotation = 0
                }
            }
        }
        .onAppear {
            if appState.phase == .recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            }
            if appState.phase == .transcribing {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    spinnerRotation = 360
                }
            }
        }
    }

    // MARK: - Idle State

    private var idleState: some View {
        HStack {
            Image(systemName: "mic")
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.softBlueWhite.opacity(0.5))
        }
    }

    // MARK: - Recording State

    private var recordingState: some View {
        HStack(spacing: 8) {
            // Pulsing recording indicator
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .scaleEffect(pulseScale)
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
            }

            Text("Recording...")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.softBlueWhite)

            // Canvas waveform
            Canvas { context, size in
                let levels = appState.audioLevels
                let count = levels.count
                guard count > 0 else { return }
                let gap: CGFloat = 2
                let barWidth: CGFloat = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)

                for (i, level) in levels.enumerated() {
                    let barHeight = max(3, CGFloat(level) * size.height)
                    let x = CGFloat(i) * (barWidth + gap)
                    let y = (size.height - barHeight) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2),
                        with: .color(DesignSystem.Colors.vibrantBlue)
                    )
                }
            }
            .frame(width: 80, height: 24)

            Text("ESC to cancel")
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.softBlueWhite.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.softBlueWhite.opacity(0.1))
                )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Transcribing State

    private var transcribingState: some View {
        HStack(spacing: 8) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    DesignSystem.Colors.accentGradient,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(spinnerRotation))

            Text("Transcribing...")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.softBlueWhite)
        }
    }

    // MARK: - Done State

    private var doneState: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(DesignSystem.Colors.softBlueWhite)
        }
    }
}

#Preview("Recording Overlay") {
    RecordingOverlayView()
        .environmentObject(AppState())
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
