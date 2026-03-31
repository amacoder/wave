//
//  DictionaryService.swift
//  Wave
//
//  Dictionary vocabulary hint prompt construction and abbreviation expansion service.
//

import Foundation
import SwiftData

// MARK: - DictionaryService

/// Service that constructs Whisper vocabulary-hint prompts from DictionaryWord entries
/// and expands abbreviations in transcribed text using the shared TextReplacer engine.
///
/// No SwiftData coupling — accepts arrays of model objects at call time.
/// AppDelegate fetches from a background ModelContext and passes data in (Phase 6 pattern).
final class DictionaryService {

    static let shared = DictionaryService()

    /// Maximum character count for the Whisper prompt parameter.
    /// ~1,100 chars is a conservative ceiling well under the 224-token Whisper limit.
    static let promptCharLimit = 1_100

    private init() {}

    // MARK: - Prompt Construction

    /// Builds a sentence-format Whisper vocabulary-hint prompt from non-abbreviation entries.
    ///
    /// Format: `"In this transcript: Term1, Term2, Term3."`
    ///
    /// Sorting: Most-recently-added first (D-06), so newer terms are not truncated.
    /// Truncation: Hard cap at `promptCharLimit` characters. Truncation may split a
    /// term mid-word; this is acceptable because partial terms still help Whisper.
    ///
    /// - Parameter words: All DictionaryWord entries fetched from SwiftData.
    /// - Returns: The prompt string, or `nil` if no vocabulary-hint entries exist.
    func buildPrompt(words: [DictionaryWord]) -> String? {
        let vocabTerms = words
            .filter { !$0.isAbbreviation }
            .sorted { $0.createdAt > $1.createdAt }  // newest first (D-06)
            .map { $0.term }

        guard !vocabTerms.isEmpty else { return nil }

        let joined = vocabTerms.joined(separator: ", ")
        let sentence = "In this transcript: \(joined)."
        // Truncate safely under 224-token Whisper limit (~1,100 chars)
        return String(sentence.prefix(1_100))
    }

    // MARK: - Abbreviation Expansion

    /// Expands abbreviation DictionaryWord entries found in `text` using TextReplacer.
    ///
    /// Only entries with `isAbbreviation == true` and a non-nil `replacement` are used.
    /// Delegates to `TextReplacer.replaceAll()` — same engine as SnippetService (D-10).
    ///
    /// - Parameters:
    ///   - text: The transcribed (and optionally GPT-cleaned) string.
    ///   - words: All DictionaryWord entries fetched from SwiftData.
    /// - Returns: The text with any matched abbreviation triggers replaced.
    func expand(text: String, words: [DictionaryWord]) -> String {
        let replacements = words
            .filter { $0.isAbbreviation }
            .compactMap { w -> (trigger: String, expansion: String)? in
                guard let replacement = w.replacement else { return nil }
                return (trigger: w.term, expansion: replacement)
            }
        return TextReplacer.replaceAll(in: text, replacements: replacements)
    }

    // MARK: - Character Count for UI

    /// Returns the full (untruncated) character count of the prompt that would be
    /// built from the given words. Used by DictionaryView's character count bar (D-14).
    ///
    /// Computes from the actual constructed prompt string — not a raw sum of term lengths —
    /// so overhead from "In this transcript: ", comma+space separators, and "." is included.
    ///
    /// - Parameter words: All DictionaryWord entries fetched from SwiftData.
    /// - Returns: Character count of the full untruncated prompt, or 0 if no vocab terms.
    func promptCharacterCount(words: [DictionaryWord]) -> Int {
        let vocabTerms = words
            .filter { !$0.isAbbreviation }
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.term }

        guard !vocabTerms.isEmpty else { return 0 }

        let joined = vocabTerms.joined(separator: ", ")
        let sentence = "In this transcript: \(joined)."
        return sentence.count
    }
}
