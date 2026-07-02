//
//  TranscriptionEntry.swift
//  Wave
//
//  SwiftData model for transcription history
//

import SwiftData
import Foundation

@Model
final class TranscriptionEntry {
    var id: UUID
    var rawText: String
    var cleanedText: String
    var timestamp: Date
    var durationSeconds: Double
    var wordCount: Int
    var sourceAppName: String?
    // v1.3 future fields — optional to avoid VersionedSchema migration
    var audioFilePath: String?
    var sourceAppBundleID: String?

    init(rawText: String, cleanedText: String, durationSeconds: Double, wordCount: Int, sourceAppName: String? = nil) {
        self.id = UUID()
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.timestamp = Date()
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.sourceAppName = sourceAppName
    }
}
