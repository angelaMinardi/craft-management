//
//  PatternContentView.swift
//  PatternVault
//

import SwiftUI

struct PatternContentView: View {
    let pattern: Pattern

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header info
                if let craftType = pattern.craftType, !craftType.isEmpty {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "scissors")
                            .foregroundStyle(Theme.softCoral)
                        Text(craftType.capitalized)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.deepPlum)

                        if let difficulty = pattern.difficulty, !difficulty.isEmpty {
                            Text("·")
                                .foregroundStyle(Theme.deepPlum.opacity(0.3))
                            Text(difficulty.capitalized)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.deepPlum)
                        }
                    }
                    .padding(.horizontal)
                }

                if let materials = pattern.materials, !materials.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Materials")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        Text(materials)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                    }
                    .padding(.horizontal)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                    .padding(.horizontal)
                }

                if let gauge = pattern.gauge, !gauge.isEmpty {
                    contentBlock(label: "Gauge", value: gauge, icon: "ruler")
                }
                if let needleHook = pattern.needleHookSizes, !needleHook.isEmpty {
                    contentBlock(label: "Needles / Hook", value: needleHook, icon: "hammer")
                }
                if let yarnYardage = pattern.yarnWeightYardage, !yarnYardage.isEmpty {
                    contentBlock(label: "Yarn weight & yardage", value: yarnYardage, icon: "spool")
                }
                if let techniques = pattern.techniques, !techniques.isEmpty {
                    contentBlock(label: "Techniques", value: techniques, icon: "list.bullet")
                }
                if let videoUrl = pattern.videoUrl, !videoUrl.isEmpty, let url = URL(string: videoUrl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Tutorial video")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        Link(destination: url) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(Theme.softCoral)
                                Text("Watch video")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.softCoral)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                    .padding(.horizontal)
                }

                // Extracted content — structured
                if let content = pattern.sourceContent, !content.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Pattern Content")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.deepPlum)

                        Divider()
                            .overlay(Theme.softCoral.opacity(0.3))
                    }
                    .padding(.horizontal)

                    let sections = parseContent(content)
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        switch section.kind {
                        case .heading:
                            Text(section.text)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.deepPlum)
                                .padding(.top, index > 0 ? Theme.Spacing.sm : 0)
                                .padding(.horizontal)

                        case .bulletList:
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                ForEach(bulletLines(from: section.text), id: \.self) { line in
                                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 5))
                                            .foregroundStyle(Theme.softCoral)
                                            .padding(.top, 7)
                                        Text(line)
                                            .font(Theme.Typography.body)
                                            .foregroundStyle(Theme.deepPlum)
                                    }
                                }
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                            .padding(.horizontal)

                        case .table:
                            tableView(from: section.text)
                                .padding(.horizontal)

                        case .paragraph:
                            Text(section.text)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                                .textSelection(.enabled)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        Text("No extracted content available")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        Text("Try opening the original page in browser.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.warmCream)
        .navigationTitle("Pattern Content")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = URL(string: pattern.sourceUrl) {
                    Link(destination: url) {
                        Label("Safari", systemImage: "safari")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contentBlock(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.softCoral)
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
        }
        .padding(.horizontal)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        .padding(.horizontal)
    }

    // MARK: - Content Parsing

    private enum ContentKind {
        case heading, bulletList, paragraph, table
    }

    private struct ContentSection {
        let kind: ContentKind
        let text: String
    }

    private func parseContent(_ text: String) -> [ContentSection] {
        let blocks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return blocks.map { block in
            // Table: multiple lines containing pipe separators
            let lines = block.components(separatedBy: "\n")
            let pipeLines = lines.filter { $0.contains(" | ") || $0.contains("| ") }
            if pipeLines.count >= 2 {
                return ContentSection(kind: .table, text: block)
            }
            // Bullet list: contains lines starting with "- "
            if block.contains("\n- ") || block.hasPrefix("- ") {
                return ContentSection(kind: .bulletList, text: block)
            }
            // Heading: single short line, no trailing punctuation
            if lines.count == 1 && block.count < 60
                && !block.hasSuffix(".") && !block.hasSuffix(",")
                && !block.hasSuffix("!") && !block.hasSuffix("?") {
                return ContentSection(kind: .heading, text: block)
            }
            return ContentSection(kind: .paragraph, text: block)
        }
    }

    private func bulletLines(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    // MARK: - Table Rendering

    @ViewBuilder
    private func tableView(from text: String) -> some View {
        let rows = parseTableRows(from: text)
        if rows.count >= 2 {
            VStack(spacing: 0) {
                // Header row
                let header = rows[0]
                HStack(spacing: 0) {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(Theme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.deepPlum)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                    }
                }
                .background(Theme.softCoral.opacity(0.15))

                // Data rows
                ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum)
                                .frame(maxWidth: .infinity, alignment: .center)
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
        }
    }

    private func parseTableRows(from text: String) -> [[String]] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { row in
                row.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }
}
