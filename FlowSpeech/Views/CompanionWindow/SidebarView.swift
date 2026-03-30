//
//  SidebarView.swift
//  Wave
//
//  Sidebar with navigation items and pinned settings gear
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, dictionary, snippets
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        }
    }

    var icon: String {
        switch self {
        case .home: return "waveform"
        case .dictionary: return "text.book.closed"
        case .snippets: return "sparkles.text.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
            }
            .listStyle(.sidebar)

            Divider()
                .padding(.horizontal, 12)

            Button(action: {
                (NSApp.delegate as? AppDelegate)?.openSettings()
            }) {
                Label("Settings", systemImage: "gearshape")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }
}
