//
//  PatternStepParser.swift
//  PatternVault
//
//  Derives steps from pattern sourceContent (or description fallback) for step-by-step UI.
//

import Foundation

struct PatternStep: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let chartImageUrl: String?
    let chartLabel: String?
    let repeatInfo: RepeatInfo?

    init(title: String, body: String, chartImageUrl: String? = nil, chartLabel: String? = nil, repeatInfo: RepeatInfo? = nil) {
        self.title = title
        self.body = body
        self.chartImageUrl = chartImageUrl
        self.chartLabel = chartLabel
        self.repeatInfo = repeatInfo
    }
}

enum PatternStepParser {

    /// Truncates content at the first end-of-pattern sentinel so promo/social never appear in steps or display.
    static func truncateAtEndOfPattern(_ content: String?) -> String? {
        guard let s = content?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return content }
        let lower = s.lowercased()
        let sentinels = [
            "learn about", "more free knitting", "more worsted", "similar posts you might enjoy",
            "you might also like", "buy sunshower", "to top", "looks like an excellent", "leave a reply",
            "share your progress", "tag your pics", "we can't wait to see what you make",
            "shop our entire collection", "looking for more inspiration", "we have over "
        ]
        var earliestOffset: Int?
        for sentinel in sentinels {
            if let range = lower.range(of: sentinel) {
                let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                if let e = earliestOffset {
                    if offset < e { earliestOffset = offset }
                } else {
                    earliestOffset = offset
                }
            }
        }
        if let offset = earliestOffset, offset > 0 {
            let start = s.index(s.startIndex, offsetBy: offset)
            let lineStart = s[..<start].lastIndex(of: "\n").map { s.index(after: $0) } ?? s.startIndex
            return String(s[..<lineStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// Parses pattern content into steps. Uses sourceContent first; falls back to patternDescription as a single step.
    /// Treats Ravelry nav/sidebar as non-content and uses description fallback so we don't show "Step 1: ravelry, patterns, yarns...".
    static func parseSteps(sourceContent: String?, patternDescription: String?) -> [PatternStep] {
        let contentForSteps = truncateAtEndOfPattern(sourceContent) ?? sourceContent
        if let content = contentForSteps, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !looksLikeRavelryChrome(content) {
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

    // MARK: - Line cleanup

    /// Remove empty/trivial lines, bare URLs, and normalize whitespace in step body.
    private static func cleanStepBody(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                if line.isEmpty { return false }
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

    /// Section headings that are reference info (materials, gauge, sizes, notes), merged into one "Pattern details" step. Excludes "pattern" (container).
    private static let referenceHeadingTitles: Set<String> = [
        "materials", "gauge", "sizes", "notes", "abbreviations", "slip stitches",
        "abbreviation", "pattern notes", "sizing", "yarn", "needles", "hooks"
    ]

    /// Generic "PATTERN" section header: do not merge into Pattern details and do not create a step for it.
    private static func isContainerHeading(_ title: String) -> Bool {
        title.lowercased().trimmingCharacters(in: .whitespaces) == "pattern"
    }

    private static func isReferenceHeading(_ title: String) -> Bool {
        if isContainerHeading(title) { return false }
        let normalized = title.lowercased().trimmingCharacters(in: .whitespaces)
        if referenceHeadingTitles.contains(normalized) { return true }
        if normalized.contains("gauge") || normalized.contains("materials") || normalized.contains("abbreviations") { return true }
        if normalized.hasPrefix("slip stitch") { return true }
        return false
    }

    /// First line looks like a section heading (e.g. BASE, BODY, ### Finishing, Toe:, Heel Flap:).
    private static func looksLikeSectionHeading(firstLine: String) -> Bool {
        let t = firstLine.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.count > 55 { return false }
        if t.hasSuffix(".") || t.hasSuffix(",") { return false }
        if t.hasPrefix("## ") || t.hasPrefix("### ") { return true }
        let letters = t.filter(\.isLetter)
        if letters.count >= 3, letters.allSatisfy(\.isUppercase) { return true }
        if t.hasSuffix(":") && t.count <= 45 {
            let withoutColon = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
            let words = withoutColon.split(separator: " ")
            if words.count <= 6, let first = words.first, first.first?.isUppercase == true { return true }
        }
        return false
    }

    /// Build steps by grouping blocks under section headings. Reference sections (Materials, Gauge, etc.) are merged into one "Pattern details" step; construction sections become separate steps.
    private static func parseStepsBySectionHeadings(blocks: [String]) -> [PatternStep]? {
        var headingIndices: [(Int, String)] = []
        for (idx, block) in blocks.enumerated() {
            let first = block.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if looksLikeSectionHeading(firstLine: first) {
                let title: String
                if first.hasPrefix("### ") {
                    title = String(first.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                } else if first.hasPrefix("## ") {
                    title = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else {
                    title = first
                }
                if !title.isEmpty { headingIndices.append((idx, title)) }
            }
        }
        if headingIndices.isEmpty { return nil }

        let referenceRanges = headingIndices.enumerated().filter { isReferenceHeading($0.element.1) }
        let constructionRanges = headingIndices.enumerated().filter { !isReferenceHeading($0.element.1) && !isContainerHeading($0.element.1) }

        var steps: [PatternStep] = []

        if !referenceRanges.isEmpty {
            let startIdx = referenceRanges.first!.element.0
            let firstNonReferenceOffset = headingIndices.firstIndex(where: { isContainerHeading($0.1) || !isReferenceHeading($0.1) }) ?? headingIndices.count
            let endBlockIdx = firstNonReferenceOffset < headingIndices.count ? headingIndices[firstNonReferenceOffset].0 : blocks.count
            let referenceBlocks = (startIdx..<endBlockIdx).map { blocks[$0] }
            let body = referenceBlocks.joined(separator: "\n\n")
            let cleanedBody = cleanStepBody(body)
            if !cleanedBody.isEmpty {
                steps.append(PatternStep(title: "Pattern details", body: cleanedBody))
            }
        }

        for (j, (_, (start, title))) in constructionRanges.enumerated() {
            let nextConstruction = constructionRanges.dropFirst(j + 1).first
            let end = nextConstruction.map { headingIndices[$0.offset].0 } ?? blocks.count
            let sectionBlocks = blocks[start..<end]
            let body = sectionBlocks.joined(separator: "\n\n")
            let cleanedBody = cleanStepBody(body)
            if !cleanedBody.isEmpty {
                steps.append(PatternStep(title: cleanStepTitle(title), body: cleanedBody))
            }
        }

        if steps.isEmpty { return nil }
        if constructionRanges.isEmpty {
            return steps
        }
        if steps.count == 1 && referenceRanges.isEmpty {
            return nil
        }
        return steps
    }

    private static func parseStepsFromContent(_ text: String) -> [PatternStep] {
        let normalized = normalizeInput(text)
        let blocks = blocksFromNormalized(normalized)

        if let sectionSteps = parseStepsBySectionHeadings(blocks: blocks), !sectionSteps.isEmpty {
            return sectionSteps
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
                    let stepTitle = firstLine.count > 60 ? shortTitleForRowOrRound(firstLine: firstLine) : cleanStepTitle(title)
                    steps.append(PatternStep(title: stepTitle, body: cleanedBody))
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

    /// Short title for Row N / Round N when the first line is long, to avoid duplicating it in the UI.
    private static func shortTitleForRowOrRound(firstLine: String) -> String {
        if firstLine.range(of: #"^Round\s+\d+"#, options: .regularExpression) != nil,
           let numPart = firstLine.split(separator: " ").dropFirst().first {
            return "Round \(numPart)"
        }
        if firstLine.range(of: #"^Rows?\s+\d+"#, options: .regularExpression) != nil,
           let numPart = firstLine.split(separator: " ").dropFirst().first {
            return "Row \(numPart)"
        }
        return String(firstLine.prefix(50)).trimmingCharacters(in: .whitespaces)
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
            let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            let body = rest.isEmpty ? block : block
            return (firstLine, body)
        }
        if firstLine.range(of: #"^Round\s+\d+"#, options: .regularExpression) != nil {
            let lines = block.components(separatedBy: "\n")
            let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            let body = rest.isEmpty ? block : block
            return (firstLine, body)
        }
        return nil
    }
}
