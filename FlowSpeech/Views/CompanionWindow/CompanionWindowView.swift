//
//  CompanionWindowView.swift
//  Wave
//
//  Root companion window with NavigationSplitView sidebar and content
//

import SwiftUI

struct CompanionWindowView: View {
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
                .navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selectedItem {
                case .home, nil:
                    HomeView()
                case .dictionary:
                    DictionaryView()
                case .snippets:
                    SnippetsView()
                }
            }
        }
        .background(
            WindowAccessor { window in
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.companionWindow = window
                    delegate.originalWindowDelegate = window.delegate
                    window.delegate = delegate
                }
            }
        )
    }
}
