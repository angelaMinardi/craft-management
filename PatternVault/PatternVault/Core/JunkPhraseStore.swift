//
//  JunkPhraseStore.swift
//  PatternVault
//
//  Persists user-identified junk phrases in App Group UserDefaults so they
//  can be used by both the main app (PatternStepParser) and the Share Extension
//  (WebContentExtractor) to filter out boilerplate from future pattern imports.
//

import Foundation

/// A single junk phrase learned from user content cleanup.
struct LearnedJunkPhrase: Codable, Equatable {
    /// Lowercased, trimmed text of the removed block (or its first line if multi-line).
    let phrase: String
    /// The pattern this phrase was removed from.
    let removedFromPatternId: UUID
    /// When the phrase was learned.
    let removedAt: Date
    /// The full original text of the removed block (for review/undo).
    let fullText: String
}

/// Manages learned junk phrases in App Group UserDefaults.
/// Accessible from both the main app and Share Extension via the shared app group.
@MainActor
final class JunkPhraseStore: ObservableObject {
    static let shared = JunkPhraseStore()

    private static let storageKey = "learned_junk_phrases"
    private static let maxPhrases = 200

    private let defaults: UserDefaults

    @Published private(set) var phrases: [LearnedJunkPhrase] = []

    private init() {
        defaults = UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
        phrases = Self.loadPhrases(from: defaults)
    }

    // MARK: - Public API

    /// Adds a phrase learned from a user's content removal.
    /// Returns false if rejected (craft instructions, already hardcoded, or already learned); true if added.
    /// Deduplicates by normalized phrase text and enforces the max cap.
    @discardableResult
    func addPhrase(text: String, patternId: UUID, fullText: String) -> Bool {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return false }

        if Self.looksLikePatternInstruction(normalized) { return false }
        if Self.isAlreadyHardcoded(normalized) { return false }
        if phrases.contains(where: { $0.phrase == normalized }) { return true }

        let entry = LearnedJunkPhrase(
            phrase: normalized,
            removedFromPatternId: patternId,
            removedAt: Date(),
            fullText: fullText
        )

        var next = phrases + [entry]
        if next.count > Self.maxPhrases {
            next = Array(next.suffix(Self.maxPhrases))
        }
        phrases = next
        save()
        return true
    }

    /// All learned phrases as simple strings for junk matching.
    func phraseStrings() -> [String] {
        phrases.map(\.phrase)
    }

    /// Removes a learned phrase matching the given text.
    func removePhraseMatching(_ text: String) {
        let normalized = Self.normalize(text)
        phrases = phrases.filter { $0.phrase != normalized }
        save()
    }

    /// Removes a learned phrase by exact phrase string (from list).
    func removePhrase(_ phrase: String) {
        phrases = phrases.filter { $0.phrase != phrase }
        save()
    }

    /// Removes all learned phrases (for settings/reset).
    func clearAll() {
        phrases = []
        save()
    }

    // MARK: - Private

    private func save() {
        guard let data = try? JSONEncoder().encode(phrases) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadPhrases(from defaults: UserDefaults) -> [LearnedJunkPhrase] {
        guard let data = defaults.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([LearnedJunkPhrase].self, from: data) else {
            return []
        }
        return loaded
    }

    private static func normalize(_ text: String) -> String {
        let firstLine = text.components(separatedBy: "\n").first ?? text
        return firstLine.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rejects phrases that look like actual pattern instructions (row, round, cast on, etc.).
    private static func looksLikePatternInstruction(_ normalized: String) -> Bool {
        let craftSubstrings = [
            "row 1", "row 2", "round 1", "rnd 1", "cast on", "bind off", "stitch", " stitches",
            "sts ", " k2tog", "p2tog", " yo ", "repeat", " times", " inc", " dec",
            "knit", "purl", "crochet", " sc ", " dc ", "hdc", "ch ", "pattern note",
            "gauge", "finished size", "materials", "needle", "hook size", "abbrev"
        ]
        return craftSubstrings.contains { normalized.contains($0) }
    }

    /// Checks if the phrase is already covered by PatternStepParser's hardcoded junk patterns.
    private static func isAlreadyHardcoded(_ normalized: String) -> Bool {
        let hardcoded = [
            "share", "print", "subscribe", "newsletter", "sign up", "cookie", "privacy policy",
            "follow us", "tweet", "pin it", "buy now", "get the pdf", "add to cart", "skip to content",
            "skip to main", "menu", "home", "search", "you may also like", "related pattern",
            "related post", "leave a comment", "comments", "posted in", "tagged", "categories",
            "share this", "email this", "previous", "next post", "read more", "see more",
            "advertisement", "sponsored", "affiliate", "disclosure", "copyright ©", "all rights reserved",
            "follow on", "like us", "watch on", "download pattern", "free pattern", "pattern by ",
            "my notebook", "sign in", "create an account", "more from ", "see them all",
            "visits in the last 24 hours", "visitors right now"
        ]
        return hardcoded.contains(where: { normalized.contains($0) })
    }
}

// MARK: - Share Extension Helper

/// Standalone reader for the Share Extension target, which cannot import JunkPhraseStore.
/// Usage: `LearnedJunkPhraseReader.phraseStrings()` in WebContentExtractor.
enum LearnedJunkPhraseReader {
    private static let storageKey = "learned_junk_phrases"

    /// Reads learned junk phrase strings from App Group UserDefaults.
    /// Safe to call from the Share Extension (no dependency on JunkPhraseStore).
    static func phraseStrings() -> [String] {
        guard let defaults = UserDefaults(suiteName: "group.com.patternvault.app"),
              let data = defaults.data(forKey: storageKey),
              let phrases = try? JSONDecoder().decode([LearnedJunkPhrase].self, from: data) else {
            return []
        }
        return phrases.map { $0.phrase }
    }
}
