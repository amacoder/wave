//
//  Snippet.swift
//  Wave
//
//  SwiftData model for text expansion snippets
//

import SwiftData
import Foundation

@Model
final class Snippet {
    var id: UUID
    var trigger: String
    var expansion: String
    var createdAt: Date

    init(trigger: String, expansion: String) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.createdAt = Date()
    }
}
