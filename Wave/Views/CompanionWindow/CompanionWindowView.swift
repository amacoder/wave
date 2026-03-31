//
//  CompanionWindowView.swift
//  Wave
//
//  Root companion window with NavigationSplitView sidebar and content
//

import SwiftUI

extension Notification.Name {
    static let navigateToSettings = Notification.Name("navigateToSettings")
}

struct CompanionWindowView: View {
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
        } detail: {
            NavigationStack {
                Group {
                    switch selectedItem {
                    case .home, nil:
                        HomeView()
                    case .dictionary:
                        DictionaryView()
                    case .snippets:
                        SnippetsView()
                    case .settings:
                        CompanionSettingsView()
                    }
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
                window.title = ""
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
            selectedItem = .settings
        }
    }
}

// MARK: - Capture openWindow for AppDelegate

struct CaptureOpenWindowModifier: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                appDelegate.openCompanionWindow = {
                    openWindow(id: "companion")
                }
            }
    }
}

extension View {
    func captureOpenWindow(appDelegate: AppDelegate) -> some View {
        modifier(CaptureOpenWindowModifier(appDelegate: appDelegate))
    }
}
