//
//  SnippetsView.swift
//  Wave
//
//  Empty state placeholder for text expansion snippets
//

import SwiftUI

struct SnippetsView: View {
    var body: some View {
        EmptyStateView(
            symbol: "text.insert",
            title: "No snippets yet",
            message: "Create trigger phrases that automatically expand into longer text after each dictation."
        )
    }
}
