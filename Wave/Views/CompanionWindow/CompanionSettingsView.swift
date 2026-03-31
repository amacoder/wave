//
//  CompanionSettingsView.swift
//  Wave
//
//  Settings embedded in companion window — reuses existing settings tab views
//

import SwiftUI

struct CompanionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var exclusionService: AppExclusionService

    @State private var selectedTab: SettingsView.SettingsTab = .general
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isAPIKeySaved: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsView.SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab()
                case .hotkey:
                    HotkeySettingsTab()
                case .transcription:
                    TranscriptionSettingsTab()
                case .api:
                    APISettingsTab(apiKey: $apiKey, showAPIKey: $showAPIKey, isAPIKeySaved: $isAPIKeySaved)
                case .exclusion:
                    ExclusionSettingsTab()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(appState)
        .environmentObject(exclusionService)
        .onAppear {
            isAPIKeySaved = KeychainManager.shared.hasAPIKey()
        }
    }
}
