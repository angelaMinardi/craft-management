//
//  GlossaryView.swift
//  PatternVault
//
//  Standalone searchable glossary of knitting and crochet abbreviations.
//  Grouped by category with craft filter.
//

import SwiftUI

struct GlossaryView: View {
    @State private var searchText = ""
    @State private var selectedCraft: CraftFilter = .all

    enum CraftFilter: String, CaseIterable {
        case all = "All"
        case knitting = "Knitting"
        case crochet = "Crochet"
    }

    private var filteredEntries: [StitchGlossary.Entry] {
        var entries = StitchGlossary.allEntries
        switch selectedCraft {
        case .knitting: entries = entries.filter { $0.craft == .knitting }
        case .crochet: entries = entries.filter { $0.craft == .crochet }
        case .all: break
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            entries = entries.filter {
                $0.abbreviation.lowercased().contains(query) ||
                $0.fullName.lowercased().contains(query) ||
                $0.description.lowercased().contains(query)
            }
        }
        return entries
    }

    private var groupedEntries: [(category: StitchGlossary.Entry.Category, entries: [StitchGlossary.Entry])] {
        let grouped = Dictionary(grouping: filteredEntries) { $0.category }
        return StitchGlossary.Entry.Category.allCases.compactMap { cat in
            guard let entries = grouped[cat], !entries.isEmpty else { return nil }
            return (cat, entries)
        }
    }

    var body: some View {
        List {
            Picker("Craft", selection: $selectedCraft) {
                ForEach(CraftFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if searchText.isEmpty {
                ForEach(groupedEntries, id: \.category) { group in
                    Section(group.category.rawValue) {
                        ForEach(group.entries) { entry in
                            glossaryRow(entry)
                        }
                    }
                }
            } else {
                ForEach(filteredEntries) { entry in
                    glossaryRow(entry)
                }
            }

            if filteredEntries.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    SpriteMascotView.idle(size: 64)
                    Text("No abbreviations found")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("\(filteredEntries.count) abbreviations")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .searchable(text: $searchText, prompt: "Search abbreviations")
        .scrollContentBackground(.hidden)
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Stitch Glossary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func glossaryRow(_ entry: StitchGlossary.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(entry.abbreviation)
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.deepPlum)
                Text(entry.fullName)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
                Spacer()
                Text(entry.craft == .crochet ? "Crochet" : "Knitting")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(entry.craft == .crochet ? Theme.softCoral : Theme.dustyBlue)
            }
            Text(entry.description)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
