//
//  SnippetService.swift
//  Wave
//
//  Shared text replacement engine (TextReplacer) and snippet expansion service.
//

import Foundation
import SwiftData

// MARK: - TextReplacer

/// Shared whole-word case-insensitive text replacement engine.
/// Used by both SnippetService and DictionaryService so abbreviation
/// expansion and snippet expansion behave identically (D-10).
enum TextReplacer {

    /// Replaces all trigger occurrences in `text` with their paired expansions.
    ///
    /// Matching rules:
    /// - Whole-word only (D-01): trigger "addr" does NOT match inside "address"
    /// - Case-insensitive (D-02): Whisper may transcribe in any capitalisation
    /// - Punctuation-tolerant (D-03): "sig." and "sig," both match trigger "sig";
    ///   surrounding non-alphanumeric characters are preserved in the output
    /// - All matches expanded (D-04): replacements are applied sequentially on the
    ///   mutating result string, sorted by trigger length descending so longer
    ///   triggers are checked first (e.g. "address" before "addr").
    ///
    /// NOTE: Because replacements run sequentially on a mutating string, cascading
    /// is technically possible — if expansion A produces text that matches trigger B,
    /// trigger B will fire. This is documented as undefined behaviour; callers should
    /// avoid overlapping trigger/expansion pairs.
    ///
    /// - Parameters:
    ///   - text: The source string to expand.
    ///   - replacements: Pairs of (trigger, expansion). Sorted by trigger length
    ///     descending internally — callers do not need to pre-sort.
    /// - Returns: The expanded string.
    static func replaceAll(in text: String,
                           replacements: [(trigger: String, expansion: String)]) -> String {
        // Sort by trigger length descending so longer triggers take priority
        let sorted = replacements.sorted { $0.trigger.count > $1.trigger.count }

        var result = text
        for (trigger, expansion) in sorted {
            let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)

            // Pattern explanation:
            //   (?<=[^a-zA-Z0-9]|^)   — preceded by non-alphanumeric or start-of-string
            //   [^a-zA-Z0-9]*         — optional adjacent punctuation to the LEFT (stripped)
            //   \b{trigger}\b         — the trigger as a whole word
            //   [^a-zA-Z0-9]*         — optional adjacent punctuation to the RIGHT (stripped)
            //   (?=[^a-zA-Z0-9]|$)    — followed by non-alphanumeric or end-of-string
            //
            // Simpler approach that satisfies D-03 without double-consuming boundary chars:
            // Match the trigger using \b word boundaries (ICU \b handles letter↔punct).
            // Surrounding punctuation characters that are immediately adjacent to the trigger
            // (no space) are captured and re-emitted so they are preserved in the output.
            //
            // Pattern: ([^a-zA-Z0-9\s]?)(\b<trigger>\b)([^a-zA-Z0-9\s]?)
            // Replace with: $1<expansion>$3
            // This preserves surrounding punctuation while replacing the trigger word.
            let pattern = "([^a-zA-Z0-9\\s]?)(\\b\(escapedTrigger)\\b)([^a-zA-Z0-9\\s]?)"

            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(result.startIndex..., in: result)
            // $1 = leading punctuation (if any), expansion replaces the trigger, $3 = trailing punctuation
            result = regex.stringByReplacingMatches(in: result,
                                                    range: range,
                                                    withTemplate: "$1\(expansion)$3")
        }
        return result
    }
}

// MARK: - SnippetService

/// Service that expands snippet trigger phrases in transcribed text.
///
/// Delegates to `TextReplacer.replaceAll()` for the replacement engine.
/// No SwiftData coupling — accepts arrays of model objects at call time so
/// AppDelegate can fetch from a background ModelContext and pass data in.
final class SnippetService {

    static let shared = SnippetService()

    private init() {}

    /// Expands all snippet triggers found in `text` with their expansions.
    ///
    /// - Parameters:
    ///   - text: The transcribed (and optionally GPT-cleaned) string.
    ///   - snippets: All snippet records to consider for expansion.
    /// - Returns: The text with any matched triggers replaced.
    func expand(text: String, snippets: [Snippet]) -> String {
        let replacements = snippets.map { (trigger: $0.trigger, expansion: $0.expansion) }
        return TextReplacer.replaceAll(in: text, replacements: replacements)
    }
}
