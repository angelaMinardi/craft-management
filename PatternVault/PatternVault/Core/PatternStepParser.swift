//
//  PatternStepParser.swift
//  PatternVault
//
//  Derives steps from pattern sourceContent (or description fallback) for step-by-step UI.
//  Preprocesses content to remove junk and produce consistent, instruction-only steps.
//

import Foundation

struct PatternStep: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

enum PatternStepParser {

    /// Parses pattern content into steps. Uses sourceContent first; falls back to patternDescription as a single step.
    /// Treats Ravelry nav/sidebar as non-content and uses description fallback so we don't show "Step 1: ravelry, patterns, yarns...".
    static func parseSteps(sourceContent: String?, patternDescription: String?) -> [PatternStep] {
        if let content = sourceContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !looksLikeRavelryChrome(content) {
            let steps = parseStepsFromContent(content)
            if !steps.isEmpty { return steps }
        }
        let body = patternDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Using your preferred materials, follow the pattern instructions."
        return [PatternStep(title: "Step 1", body: cleanStepBody(body))]
    }

    /// True if the text is Ravelry nav/sidebar/footer rather than pattern instructions (so we don't show it as steps).
    static func looksLikeRavelryChrome(_ text: String?) -> Bool {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        let lower = t.lowercased()
        let navPhrases = ["my notebook", "sign in", "create an account"]
        let navItems = ["patterns", "yarns", "people", "groups", "forums"]
        let navCount = navPhrases.filter { lower.contains($0) }.count
        let itemCount = navItems.filter { lower.contains($0) }.count
        if navCount >= 1 && itemCount >= 2 { return true }
        if lower.contains("visits in the last 24 hours") && lower.contains("visitors right now") { return true }
        if lower.contains("more from") && lower.contains("see them all") { return true }
        return false
    }

    // MARK: - Input normalization

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func normalizeInput(_ text: String) -> String {
        let normalized = decodeHTMLEntities(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.joined(separator: "\n")
    }

    /// Collapse multiple blank lines into double newline; trim each line.
    private static func blocksFromNormalized(_ text: String) -> [String] {
        let doubled = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return doubled.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Junk detection (blocks and lines we should not keep)

    private static let junkFirstLinePatterns: [String] = [
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

    /// Combined hardcoded + user-learned junk patterns.
    /// Uses LearnedJunkPhraseReader so this can run in a synchronous nonisolated context (same data as JunkPhraseStore).
    private static var allJunkPatterns: [String] {
        let learned = LearnedJunkPhraseReader.phraseStrings()
        return junkFirstLinePatterns + learned
    }

    private static func isJunkBlock(block: String, firstLine: String) -> Bool {
        let lower = firstLine.lowercased()
        if firstLine.count < 3 { return true }
        if allJunkPatterns.contains(where: { lower.contains($0) }) { return true }
        if lower.allSatisfy({ $0.isNumber || $0.isWhitespace || ".,;:/-".contains($0) }) { return true }
        if firstLine.hasPrefix("http://") || firstLine.hasPrefix("https://") { return true }
        if block.components(separatedBy: "\n").filter({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("http") }).count > 2 { return true }
        return false
    }

    /// Remove junk lines and normalize whitespace in step body.
    private static func cleanStepBody(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                if line.isEmpty { return false }
                let lower = line.lowercased()
                if allJunkPatterns.contains(where: { lower.contains($0) }) { return false }
                if line.hasPrefix("http://") || line.hasPrefix("https://") { return false }
                if line.count < 2 && !line.allSatisfy({ $0.isLetter || $0.isNumber }) { return false }
                return true
            }
        let joined = lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.count > 2500 {
            return String(joined.prefix(2480)) + "..."
        }
        return joined
    }

    /// Strip leading/trailing junk and normalize; used for step titles.
    private static func cleanStepTitle(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "Step" }
        if t.count > 60 { return String(t.prefix(57)) + "..." }
        return t
    }

    // MARK: - Step parsing

    private static func parseStepsFromContent(_ text: String) -> [PatternStep] {
        let normalized = normalizeInput(text)
        var blocks = blocksFromNormalized(normalized)
        blocks = blocks.filter { block in
            let first = block.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return !isJunkBlock(block: block, firstLine: first)
        }

        var steps: [PatternStep] = []
        var i = 0
        while i < blocks.count {
            let block = blocks[i]
            let lines = block.components(separatedBy: "\n")
            let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""

            if let (title, body) = parseStepBlock(firstLine: firstLine, block: block) {
                let cleanedBody = cleanStepBody(body)
                if !cleanedBody.isEmpty {
                    steps.append(PatternStep(title: cleanStepTitle(title), body: cleanedBody))
                }
                i += 1
                continue
            }

            if firstLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil,
               let dotIdx = firstLine.firstIndex(of: "."),
               let num = Int(firstLine[..<dotIdx].trimmingCharacters(in: .whitespaces)) {
                let stepTitle = "Step \(num)"
                let afterNum = firstLine[firstLine.index(after: dotIdx)...].trimmingCharacters(in: .whitespaces)
                let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                let stepBody = cleanStepBody(rest.isEmpty ? afterNum : block)
                if !stepBody.isEmpty {
                    steps.append(PatternStep(title: stepTitle, body: stepBody))
                }
                i += 1
                continue
            }

            if firstLine.lowercased().hasPrefix("step "), let numPart = firstLine.split(separator: " ").dropFirst().first {
                let title = "Step \(numPart)"
                let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                let stepBody = cleanStepBody(body.isEmpty ? String(firstLine) : body)
                if !stepBody.isEmpty {
                    steps.append(PatternStep(title: title, body: stepBody))
                }
                i += 1
                continue
            }
            if firstLine.lowercased().hasPrefix("round "), let numPart = firstLine.split(separator: " ").dropFirst().first {
                let title = "Round \(numPart)"
                let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                let stepBody = cleanStepBody(body.isEmpty ? String(firstLine) : body)
                if !stepBody.isEmpty {
                    steps.append(PatternStep(title: title, body: stepBody))
                }
                i += 1
                continue
            }

            i += 1
        }

        if !steps.isEmpty { return steps }

        // No clear step structure: return one step with cleaned full content, or split only if blocks look like instructions
        let cleanedFull = cleanStepBody(blocks.joined(separator: "\n\n"))
        if cleanedFull.isEmpty {
            return []
        }
        if blocks.count == 1 {
            return [PatternStep(title: "Step 1", body: cleanedFull)]
        }
        let instructionBlocks = blocks.filter { block in
            let first = block.components(separatedBy: "\n").first ?? ""
            return block.count >= 20 && !first.hasPrefix("http")
        }
        if instructionBlocks.isEmpty {
            return [PatternStep(title: "Step 1", body: cleanedFull)]
        }
        if instructionBlocks.count > 12 {
            return [PatternStep(title: "Step 1", body: cleanedFull)]
        }
        return instructionBlocks.enumerated().map { index, block in
            let firstLine = block.components(separatedBy: "\n").first ?? block
            let isShortHeading = firstLine.count < 80 && !firstLine.hasSuffix(".") && !firstLine.hasSuffix(",")
            let title = isShortHeading ? cleanStepTitle(firstLine) : "Step \(index + 1)"
            let body: String
            if isShortHeading && block.contains("\n") {
                body = cleanStepBody(block.components(separatedBy: "\n").dropFirst().joined(separator: "\n"))
            } else {
                body = cleanStepBody(block)
            }
            return PatternStep(title: title, body: body.isEmpty ? cleanStepBody(block) : body)
        }.filter { !$0.body.isEmpty }
    }

    private static func parseStepBlock(firstLine: String, block: String) -> (title: String, body: String)? {
        if firstLine.range(of: #"^Step\s+\d+"#, options: .regularExpression) != nil {
            let lines = block.components(separatedBy: "\n")
            let title = lines.first ?? "Step 1"
            let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            return (title, body.isEmpty ? title : body)
        }
        if firstLine.range(of: #"^Rows?\s+\d+"#, options: .regularExpression) != nil {
            let lines = block.components(separatedBy: "\n")
            let title = lines.first ?? "Step"
            let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            return (title, body.isEmpty ? title : body)
        }
        return nil
    }
}
