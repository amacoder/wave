//
//  HomeView.swift
//  Wave
//
//  Empty state placeholder for transcription history
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        EmptyStateView(
            symbol: "waveform.and.mic",
            title: "No transcriptions yet",
            message: "Start dictating with the Fn key. Your transcription history will appear here."
        )
    }
}
