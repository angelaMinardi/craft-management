//
//  FormattedStepBodyView.swift
//  PatternVault
//
//  Renders step body text with visual hierarchy: section headings, NOTE lines, bullets, tables, paragraphs.
//

import SwiftUI

enum StepBodyBlockKind {
    case heading
    case note
    case bulletList
    case table
    case repeatReference
    case paragraph
}

struct StepBodyBlock: Identifiable {
    let id = UUID()
    let kind: StepBodyBlockKind
    let text: String
}

struct FormattedStepBodyView: View {
    let stepBody: String

    private var blocks: [StepBodyBlock] {
        let trimmed = stepBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let rawBlocks = trimmed.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return rawBlocks.map { block -> StepBodyBlock in
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let pipeLines = lines.filter { $0.contains("|") }
            if pipeLines.count >= 2 {
                return StepBodyBlock(kind: .table, text: block)
            }
            if block.contains("\n- ") || block.hasPrefix("- ") || block.contains("\n• ") || block.hasPrefix("• ") {
                return StepBodyBlock(kind: .bulletList, text: block)
            }
            if let first = lines.first, first.uppercased().hasPrefix("NOTE:") {
                return StepBodyBlock(kind: .note, text: block)
            }
            if lines.count == 1, let line = lines.first, line.count <= 50,
               !line.hasSuffix("."), !line.hasSuffix(","), !line.hasSuffix("!"), !line.hasSuffix("?") {
                let letters = line.filter(\.isLetter)
                let allCaps = letters.count >= 3 && letters.allSatisfy(\.isUppercase)
                if allCaps || line.count < 30 {
                    return StepBodyBlock(kind: .heading, text: block)
                }
            }
            if isRepeatReferenceBlock(block) {
                return StepBodyBlock(kind: .repeatReference, text: block)
            }
            return StepBodyBlock(kind: .paragraph, text: block)
        }
    }

    @ViewBuilder
    private var bodyView: some View {
        if blocks.isEmpty {
            Text("No content")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    blockView(block: block, isFirst: index == 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func blockView(block: StepBodyBlock, isFirst: Bool) -> some View {
        switch block.kind {
        case .heading:
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.softCoral)
                    .frame(width: 4, height: 20)
                Text(block.text)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.deepPlum)
            }
            .padding(.top, isFirst ? 0 : Theme.Spacing.xs)

        case .note:
            noteView(text: block.text)

        case .bulletList:
            bulletListView(text: block.text)

        case .table:
            tableView(text: block.text)

        case .repeatReference:
            repeatReferenceView(text: block.text)

        case .paragraph:
            paragraphView(text: block.text)
        }
    }

    /// Renders paragraph text with measurement emphasis; NOTE lines get callout container; repeat lines get italic + label; first line can be heading.
    private func paragraphView(text: String) -> some View {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.count <= 1, let single = lines.first, !single.isEmpty {
            return AnyView(measurementEmphasizedText(single).lineSpacing(4))
        }
        let nonEmpty = lines.filter { !$0.isEmpty }
        if nonEmpty.isEmpty {
            return AnyView(measurementEmphasizedText(text).lineSpacing(4))
        }
        let firstIsHeading = looksLikeHeadingLine(nonEmpty[0])
        return AnyView(
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if firstIsHeading && nonEmpty.count >= 2 {
                    headingAccentView(text: nonEmpty[0])
                    ForEach(Array(nonEmpty.dropFirst().enumerated()), id: \.offset) { _, line in
                        paragraphLineView(line: line)
                    }
                } else if firstIsHeading && nonEmpty.count == 1 {
                    headingAccentView(text: nonEmpty[0])
                } else {
                    ForEach(Array(nonEmpty.enumerated()), id: \.offset) { _, line in
                        paragraphLineView(line: line)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    private func looksLikeHeadingLine(_ line: String) -> Bool {
        guard line.count <= 50,
              !line.hasSuffix("."), !line.hasSuffix(","), !line.hasSuffix("!"), !line.hasSuffix("?") else { return false }
        let letters = line.filter(\.isLetter)
        let allCaps = letters.count >= 3 && letters.allSatisfy(\.isUppercase)
        return allCaps || line.count < 30
    }

    private func headingAccentView(text: String) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.softCoral)
                .frame(width: 4, height: 20)
            Text(text)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)
        }
    }

    @ViewBuilder
    private func paragraphLineView(line: String) -> some View {
        if line.uppercased().hasPrefix("NOTE:") {
            noteCalloutLineView(line: line)
        } else if isRepeatReferenceBlock(line) {
            repeatReferenceLineView(line: line)
        } else {
            measurementEmphasizedText(line)
                .lineSpacing(4)
        }
    }

    private func noteCalloutLineView(line: String) -> some View {
        let prefix = String(line.prefix(5))
        let rest = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        let content = HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Text(prefix)
                .font(Theme.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.softCoral)
            measurementEmphasizedText(rest)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        return ZStack(alignment: .leading) {
            content
                .background(Theme.softCoral.opacity(0.06))
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.softCoral)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .stroke(Theme.softCoral.opacity(0.2), lineWidth: 1)
        )
    }

    private func repeatReferenceLineView(line: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Repeat")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.dustyBlue)
            Text(line)
                .font(Theme.Typography.body)
                .italic()
                .foregroundStyle(Theme.deepPlum)
                .padding(.leading, Theme.Spacing.xs)
        }
    }

    /// Splits text into segments and returns concatenated Text with measurements/numbers emphasized.
    private func measurementEmphasizedText(_ text: String) -> Text {
        let segments = parseMeasurementSegments(text)
        return segments.reduce(Text("")) { acc, pair in
            let (str, emphasized) = pair
            let t = Text(str)
                .font(Theme.Typography.body)
                .foregroundStyle(emphasized ? Theme.softCoral : Theme.deepPlum)
                .fontWeight(emphasized ? .semibold : .regular)
            return acc + t
        }
    }

    /// Finds measurement/size segments and knitting abbreviations to emphasize.
    private func parseMeasurementSegments(_ text: String) -> [(String, Bool)] {
        // Order matters: longer patterns first to avoid partial overlaps.
        // 1) Square-bracket sizes; 2) Parenthetical sizes; 3) Number before (; 4) X stitches/inches/rows
        // 5) X"; 6) X (more) times; 7) hyphenated X-inch; 8) knitting abbreviations (k2tog, ssk, etc.)
        // 9) k/p + number (k1, k2, p1, K63)
        let pattern = #"\[\d+(?:\s*[^\]]*)?\]|\(\d+(?:\s*,\s*\d+)*\)|\d+(?:\s*[½¼¾]|\s*\.\s*\d+)?(?=\s*\()|\d+(?:\s*[½¼¾]|\s*\.\s*\d+)?\s*(?:stitches|sts?|inches|rows?)\b|\d+(?:\s*[½¼¾]|\s*\.\s*\d+)?\s*\"|\d+\s+(?:more\s+)?times\b|\d+(?:\s*[½¼¾]|\s*\.\s*\d+)?\s*-\s*inch(es)?\b|\b(?:k2tog|p2tog|ssk|yo|m1l?|m1r?|cdd|s2kp2|p2sso|psso|sl\s*1)\b|\b[kpKP]\d+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return [(text, false)]
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var segments: [(String, Bool)] = []
        var lastEnd = 0
        for m in matches {
            if m.range.location > lastEnd {
                let plain = ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
                segments.append((plain, false))
            }
            let emph = ns.substring(with: m.range)
            segments.append((emph, true))
            lastEnd = m.range.location + m.range.length
        }
        if lastEnd < ns.length {
            segments.append((ns.substring(from: lastEnd), false))
        }
        if segments.isEmpty { return [(text, false)] }
        return segments
    }

    private func isRepeatReferenceBlock(_ block: String) -> Bool {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let lower = firstLine.lowercased()
        return lower.contains("repeat from row")
            || lower.contains("repeat from *")
            || lower.hasPrefix("repeat row ")
            || lower.hasPrefix("repeat rows ")
            || lower.hasPrefix("work as for ")
            || lower.hasPrefix("same as ")
            || lower.hasPrefix("continuing as for ")
            || lower.hasPrefix("continue as for ")
    }

    private func repeatReferenceView(text: String) -> some View {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? text
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Repeat")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.dustyBlue)
            Text(line)
                .font(Theme.Typography.body)
                .italic()
                .foregroundStyle(Theme.deepPlum)
                .padding(.leading, Theme.Spacing.xs)
        }
    }

    private func noteView(text: String) -> some View {
        let lines = text.components(separatedBy: "\n")
        let content = VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.uppercased().hasPrefix("NOTE:") {
                    let prefix = String(line.prefix(5))
                    let rest = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Text(prefix)
                            .font(Theme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.softCoral)
                        Text(rest)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                    }
                } else {
                    Text(line)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        return ZStack(alignment: .leading) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.softCoral.opacity(0.06))
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.softCoral)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .stroke(Theme.softCoral.opacity(0.2), lineWidth: 1)
        )
    }

    private func bulletListView(text: String) -> some View {
        let bulletLines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line -> String in
                if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
                return line
            }
            .filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(bulletLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Theme.softCoral)
                        .padding(.top, 7)
                    measurementEmphasizedText(line)
                }
            }
        }
    }

    private func tableView(text: String) -> some View {
        let rows = parseTableRows(text)
        if rows.count >= 2 {
            let numericColumns = numericColumnFlags(rows: rows)
            return AnyView(
                VStack(spacing: 0) {
                    let header = rows[0]
                    HStack(spacing: 0) {
                        ForEach(Array(header.enumerated()), id: \.offset) { i, cell in
                            Text(cell)
                                .font(Theme.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.deepPlum)
                                .frame(maxWidth: .infinity, alignment: i < numericColumns.count && numericColumns[i] ? .trailing : .center)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                        }
                    }
                    .background(Theme.softCoral.opacity(0.15))
                    .overlay(
                        Rectangle()
                            .fill(Theme.softCoral.opacity(0.4))
                            .frame(height: 1),
                        alignment: .bottom
                    )

                    ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { rowIdx, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                                Text(cell)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.deepPlum)
                                    .frame(maxWidth: .infinity, alignment: i < numericColumns.count && numericColumns[i] ? .trailing : .center)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .background(rowIdx % 2 == 0 ? Theme.cardBackground : Color.clear)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .stroke(Theme.deepPlum.opacity(0.1), lineWidth: 1)
                )
            )
        }
        return AnyView(
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
                .lineSpacing(4)
        )
    }

    /// For each column, true if the majority of body cells look numeric (digits, optional decimal, optional " in"/" cm").
    private func numericColumnFlags(rows: [[String]]) -> [Bool] {
        guard rows.count >= 2, let colCount = rows.first?.count else { return [] }
        let bodyRows = Array(rows.dropFirst())
        return (0..<colCount).map { col in
            let cells = bodyRows.compactMap { row -> String? in
                guard col < row.count else { return nil }
                return row[col].trimmingCharacters(in: .whitespaces)
            }
            guard !cells.isEmpty else { return false }
            let numericCount = cells.filter { looksNumeric($0) }.count
            return numericCount >= (cells.count * 2) / 3
        }
    }

    private func looksNumeric(_ cell: String) -> Bool {
        let t = cell.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return false }
        let pattern = #"^\d+(\.\d+)?\s*(in|cm)?$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    private func parseTableRows(_ text: String) -> [[String]] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { row in
                row.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        bodyView
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(stepBody)
    }
}
