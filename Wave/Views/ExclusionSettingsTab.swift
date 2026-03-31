//
//  ExclusionSettingsTab.swift
//  Wave
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
                // Inline search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search apps...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))

                // App list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredApps.isEmpty && !searchText.isEmpty {
                            Text("No apps matched your search.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(filteredApps) { app in
                                HStack(spacing: 8) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
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
                                .padding(.horizontal, 4)
                                .padding(.vertical, 5)
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } header: {
                Text("Excluded Apps")
            }
        }
        .formStyle(.grouped)
        .onAppear { exclusionService.startInstalledAppsQuery() }
    }
}
