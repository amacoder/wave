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
        VStack(spacing: 0) {
            // Branded header
            HStack(spacing: 7) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("Wave")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)

            // Nav items
            List(selection: $selection) {
                ForEach(SidebarItem.mainItems) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)

            // Pinned settings
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
        .navigationSplitViewColumnWidth(190)
    }
}
