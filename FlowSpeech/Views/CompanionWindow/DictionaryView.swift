//
//  DictionaryView.swift
//  Wave
//
//  Empty state placeholder for custom dictionary
//

import SwiftUI

struct DictionaryView: View {
    var body: some View {
        EmptyStateView(
            symbol: "character.book.closed",
            title: "Your dictionary is empty",
            message: "Add custom words to help Wave transcribe your vocabulary accurately."
        )
    }
}
