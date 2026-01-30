//
//  RecordingOverlayView.swift
//  FlowSpeech
//
//  Floating recording indicator with waveform
//

import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 12) {
            if appState.isTranscribing {
                // Transcribing state
                TranscribingView()
            } else {
                // Recording state
                RecordingView(audioLevels: appState.audioLevels, isAnimating: $pulseAnimation)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    appState.isRecording ? Color.red.opacity(0.5) : Color.blue.opacity(0.3),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

// MARK: - Recording View

struct RecordingView: View {
    let audioLevels: [Float]
    @Binding var isAnimating: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                
                Circle()
                    .fill(Color.red)
                    .frame(width: 16, height: 16)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Waveform
                WaveformView(levels: audioLevels)
                    .frame(width: 100, height: 24)
            }
            
            Text("ESC to cancel")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                )
        }
    }
}

// MARK: - Transcribing View

struct TranscribingView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 16) {
            // Loading spinner
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "2563EB"), Color(hex: "0D9488")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            
            Text("Transcribing...")
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let levels: [Float]
    let barCount = 15
    let minHeight: CGFloat = 2
    let maxHeight: CGFloat = 20
    
    private func levelFor(index: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        let levelIndex = min(index * levels.count / barCount, levels.count - 1)
        return levels[levelIndex]
    }
    
    private func heightFor(level: Float) -> CGFloat {
        return max(minHeight, CGFloat(level) * maxHeight)
    }
    
    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "2563EB"), Color(hex: "0D9488")],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: heightFor(level: levelFor(index: index)),
                    gradient: barGradient
                )
            }
        }
    }
}

struct WaveformBar: View {
    let height: CGFloat
    let gradient: LinearGradient
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(gradient)
            .frame(width: 3, height: height)
            .animation(.easeOut(duration: 0.05), value: height)
    }
}

// MARK: - Alternative Waveform (Circular)

struct CircularWaveformView: View {
    let levels: [Float]
    @State private var phase: Double = 0
    
    private let gradient = Gradient(colors: [Color(hex: "2563EB"), Color(hex: "0D9488")])
    private let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round)
    
    var body: some View {
        Canvas { context, size in
            drawWaveform(context: context, size: size)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
    
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 4
        
        for i in 0..<levels.count {
            drawBar(context: context, index: i, center: center, radius: radius)
        }
    }
    
    private func drawBar(context: GraphicsContext, index: Int, center: CGPoint, radius: CGFloat) {
        let angleValue: CGFloat = (CGFloat(index) / CGFloat(levels.count)) * 2 * .pi - .pi / 2 + CGFloat(phase)
        let level = CGFloat(levels[index])
        let barLength = radius * 0.3 * level + 4
        
        let startRadius = radius - barLength / 2
        let endRadius = radius + barLength / 2
        
        let cosAngle = CoreGraphics.cos(angleValue)
        let sinAngle = CoreGraphics.sin(angleValue)
        
        let start = CGPoint(
            x: center.x + startRadius * cosAngle,
            y: center.y + startRadius * sinAngle
        )
        let end = CGPoint(
            x: center.x + endRadius * cosAngle,
            y: center.y + endRadius * sinAngle
        )
        
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        
        context.stroke(
            path,
            with: .linearGradient(gradient, startPoint: start, endPoint: end),
            style: strokeStyle
        )
    }
}

// MARK: - Full Screen Recording Overlay (Alternative)

struct FullScreenRecordingOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var showControls = true
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showControls.toggle()
                }
            
            // Center content
            VStack(spacing: 30) {
                // Large waveform
                CircularWaveformView(levels: appState.audioLevels)
                    .frame(width: 200, height: 200)
                
                if appState.isTranscribing {
                    Text("Transcribing...")
                        .font(.title2)
                        .fontWeight(.medium)
                } else {
                    Text("Listening...")
                        .font(.title2)
                        .fontWeight(.medium)
                }
                
                if showControls {
                    HStack(spacing: 20) {
                        Button(action: {
                            // Cancel action would be triggered by AppDelegate
                        }) {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.red.opacity(0.8)))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            }
            .foregroundColor(.white)
        }
    }
}

#Preview("Recording Overlay") {
    RecordingOverlayView()
        .environmentObject(AppState())
        .frame(width: 300, height: 100)
        .background(Color.gray.opacity(0.3))
}

#Preview("Waveform") {
    WaveformView(levels: (0..<30).map { _ in Float.random(in: 0.1...1.0) })
        .frame(width: 150, height: 30)
        .padding()
        .background(Color.black.opacity(0.8))
}
