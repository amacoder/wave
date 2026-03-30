//
//  SidebarView.swift
//  Wave
//
//  Sidebar with navigation items and pinned settings gear
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, dictionary, snippets, settings
    var id: Self { self }

    /// Items shown in the main list (not pinned)
    static var mainItems: [SidebarItem] { [.home, .dictionary, .snippets] }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "waveform"
        case .dictionary: return "text.book.closed"
        case .snippets: return "sparkles"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarItem.mainItems) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                List(selection: $selection) {
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
                .listStyle(.sidebar)
                .frame(height: 36)
                .scrollDisabled(true)
            }
        }
    }
}
