//
//  StashMatchPatternsView.swift
//  PatternVault
//
//  From a stash item: shows vault patterns that work with this yarn and optional Ravelry results.
//  Displays yardage comparison (enough / short / left) when possible.
//

import SwiftUI

struct StashMatchPatternsView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    let stashItem: YarnStashItem

    @State private var ravelryResults: [PatternDiscoveryResult] = []
    @State private var isLoadingRavelry = false
    @State private var showAddSheet = false
    @State private var resultToSave: PatternDiscoveryResult?

    private var vaultPatterns: [Pattern] {
        let weight = (stashItem.weight ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let hasWeight = !weight.isEmpty
        return store.patterns.filter { pattern in
            if hasWeight {
                let yarnText = (pattern.yarnWeightYardage ?? "") + " " + (pattern.materials ?? "")
                if yarnText.isEmpty { return false }
                if !yarnText.localizedCaseInsensitiveContains(weight) {
                    return false
                }
            }
            return true
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                stashSummaryCard
                vaultSection
                if RavelryPatternSearchService.isConfigured {
                    ravelrySection
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Patterns for this yarn")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            if let result = resultToSave {
                AddPatternView(store: store, prefillURL: result.sourceUrl)
                    .onDisappear { resultToSave = nil }
            }
        }
        .task {
            if RavelryPatternSearchService.isConfigured {
                await runRavelrySearch()
            }
        }
    }

    private var stashSummaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Your yarn")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Text(stashItem.displaySummary)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
            if let yd = stashItem.totalYardage {
                Text("\(yd) yards total")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.sageGreen)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .borderedCard()
    }

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "In your vault")
            if vaultPatterns.isEmpty {
                Text("No patterns in your vault match this yarn. Try Find patterns to search Ravelry.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(vaultPatterns) { pattern in
                        NavigationLink(value: pattern) {
                            stashMatchPatternRow(pattern: pattern)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func stashMatchPatternRow(pattern: Pattern) -> some View {
        let required = YardageHelper.parseRequiredYardage(from: pattern)
        let comparison = YardageHelper.compare(stashYardage: stashItem.totalYardage, requiredYardage: required)
        return HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(pattern.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                if let craft = pattern.craftType, !craft.isEmpty {
                    Text(craft)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            Text(comparison.summary)
                .font(Theme.Typography.caption2)
                .foregroundStyle(yardageColor(comparison))
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.deepPlum.opacity(0.3))
        }
        .padding(Theme.Spacing.md)
        .borderedCard()
    }

    private func yardageColor(_ c: YardageComparison) -> Color {
        switch c {
        case .enough, .left: return Theme.sageGreen
        case .short: return Theme.softCoral
        case .unknown: return Theme.deepPlum.opacity(0.5)
        }
    }

    private var ravelrySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "More on Ravelry")
            if isLoadingRavelry {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().tint(Theme.softCoral)
                    Text("Searching...")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
            } else if ravelryResults.isEmpty {
                Text("No Ravelry results for this yarn.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(ravelryResults) { result in
                        ravelryResultRow(result)
                    }
                }
            }
        }
    }

    private func ravelryResultRow(_ result: PatternDiscoveryResult) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if let urlString = result.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Theme.warmCream)
                            .overlay(Image(systemName: "photo").foregroundStyle(Theme.deepPlum.opacity(0.3)))
                    default:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            } else {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(Theme.warmCream)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "doc.text").foregroundStyle(Theme.deepPlum.opacity(0.3)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                if let craft = result.craftType {
                    Text(craft)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            Button {
                resultToSave = result
                showAddSheet = true
            } label: {
                Text("Save to vault")
                    .font(Theme.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.sageGreen)
        }
        .padding(Theme.Spacing.md)
        .borderedCard()
    }

    private func runRavelrySearch() async {
        isLoadingRavelry = true
        defer { isLoadingRavelry = false }
        let weight = stashItem.weight ?? ""
        let criteria = RavelrySearchCriteria(
            query: "pattern",
            yarnWeight: weight.isEmpty ? nil : weight,
            needleSize: nil,
            craft: nil,
            freeOnly: false
        )
        if let list = await RavelryPatternSearchService.search(criteria: criteria) {
            ravelryResults = Array(list.prefix(12))
        } else {
            ravelryResults = []
        }
    }
}
