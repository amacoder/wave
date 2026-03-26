//
//  ExclusionSettingsTab.swift
//  FlowSpeech
//
//  Settings tab for managing app exclusions and auto-suppress fullscreen toggle.
//

import SwiftUI

struct ExclusionSettingsTab: View {
    @EnvironmentObject var exclusionService: AppExclusionService
    @State private var searchText = ""

    var filteredApps: [AppExclusionService.InstalledApp] {
        if searchText.isEmpty { return exclusionService.installedApps }
        return exclusionService.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Auto-suppress in fullscreen apps", isOn: $exclusionService.autoSuppressFullscreen)
                Text("Prevents hotkey activation in games and full-screen video players. Disable if you use fullscreen Xcode or Terminal.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Automatic Suppression")
            }

            Section {
                if filteredApps.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 8) {
                        Text("No Apps Found")
                            .font(.headline)
                        Text("No installed apps matched your search. Try a different name.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    List(filteredApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            Text(app.name)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { exclusionService.excludedBundleIDs.contains(app.id) },
                                set: { isOn in
                                    if isOn { exclusionService.excludedBundleIDs.insert(app.id) }
                                    else { exclusionService.excludedBundleIDs.remove(app.id) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search apps...")
                    .frame(minHeight: 200)
                }
            } header: {
                Text("Excluded Apps")
            }
        }
        .formStyle(.grouped)
        .onAppear { exclusionService.startInstalledAppsQuery() }
    }
}
