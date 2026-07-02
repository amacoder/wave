//
//  DictionaryWord.swift
//  Wave
//
//  SwiftData model for custom vocabulary and abbreviations
//

import SwiftData
import Foundation

@Model
final class DictionaryWord {
    var id: UUID
    var term: String
    var replacement: String?   // nil for vocabulary hints, populated for abbreviations
    var isAbbreviation: Bool
    var createdAt: Date

    init(term: String, replacement: String? = nil, isAbbreviation: Bool = false) {
        self.id = UUID()
        self.term = term
        self.replacement = replacement
        self.isAbbreviation = isAbbreviation
        self.createdAt = Date()
    }
}
