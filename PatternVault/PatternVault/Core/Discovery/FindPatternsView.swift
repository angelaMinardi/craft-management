//
//  FindPatternsView.swift
//  PatternVault
//
//  Smart search: enter or select materials (yarn weight, needle/hook size, craft),
//  search Ravelry for free or paid patterns, open in Safari or save to vault.
//

import SwiftUI

struct FindPatternsView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @StateObject private var yarnStashStore = YarnStashStore()
    @StateObject private var needleHookStore = NeedleHookStore()

    @State private var keyword = ""
    @State private var yarnWeight = ""
    @State private var needleSize = ""
    @State private var craftOption: CraftOption = .any
    @State private var freeOnly = false

    @State private var results: [PatternDiscoveryResult] = []
    @State private var isLoading = false
    @State private var searchErrorMessage: String?
    @State private var showAddSheet = false
    @State private var resultToSave: PatternDiscoveryResult?

    enum CraftOption: String, CaseIterable {
        case any = "Any"
        case knitting = "Knitting"
        case crochet = "Crochet"

        var ravelryValue: String? {
            switch self {
            case .any: return nil
            case .knitting: return "knitting"
            case .crochet: return "crochet"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                yourMaterialsSection
                searchCriteriaSection
                if RavelryPatternSearchService.isConfigured {
                    searchButton
                    if isLoading {
                        loadingView
                    } else if let msg = searchErrorMessage {
                        errorView(msg)
                    } else if !results.isEmpty {
                        resultsSection
                    } else if searchErrorMessage == nil, results.isEmpty, !isLoading {
                        emptyPromptView
                    }
                } else {
                    searchInSafariButton
                    ravelrySetupHint
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Find patterns")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            if let result = resultToSave {
                AddPatternView(store: store, prefillURL: result.sourceUrl)
                    .onAppear {
                        // AddPatternView will fetch metadata and prefill title from URL
                    }
                    .onDisappear { resultToSave = nil }
            }
        }
        .task {
            guard let userId = auth.currentUserId else { return }
            await yarnStashStore.load(userId: userId)
            await needleHookStore.load(userId: userId)
        }
    }

    /// When API keys are not set, user can still search by opening Ravelry in Safari.
    private var searchInSafariButton: some View {
        Button {
            openRavelrySearchInSafari()
        } label: {
            Label("Search on Ravelry", systemImage: "safari")
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    /// Hint for in-app results; show only when Ravelry API is not configured.
    private var ravelrySetupHint: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("For results inside the app, add Ravelry API keys in Config.xcconfig.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.55))
                .multilineTextAlignment(.center)
            if let url = URL(string: "https://www.ravelry.com/pro/developer") {
                Link("Get API keys at ravelry.com/pro/developer", destination: url)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.dustyBlue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    private var yourMaterialsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeaderView(title: "Your materials")
            let stashWeights = Array(Set(yarnStashStore.items.compactMap { $0.weight }.filter { !$0.isEmpty })).sorted()
            let toolSizes = needleHookStore.items.map { $0.size }
            let toolCrafts = needleHookStore.items.map { $0.typeDisplayName }
            if stashWeights.isEmpty && toolSizes.isEmpty {
                Text("Add yarn and tools in Stash & Tools to see suggestions here.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
            } else {
                FlowLayout(spacing: Theme.Spacing.sm) {
                    ForEach(stashWeights, id: \.self) { w in
                        Button {
                            yarnWeight = w
                        } label: {
                            Text(w)
                                .font(Theme.Typography.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.chipFill)
                                .foregroundStyle(Theme.deepPlum)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(Array(Set(toolSizes)), id: \.self) { s in
                        Button {
                            needleSize = s
                        } label: {
                            Text(s)
                                .font(Theme.Typography.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.dustyBlue.opacity(0.15))
                                .foregroundStyle(Theme.deepPlum)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(Array(Set(toolCrafts)).filter { $0.lowercased() == "needle" || $0.lowercased() == "hook" }, id: \.self) { c in
                        Button {
                            craftOption = c.lowercased() == "hook" ? .crochet : .knitting
                        } label: {
                            Text(c)
                                .font(Theme.Typography.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.sageGreen.opacity(0.15))
                                .foregroundStyle(Theme.deepPlum)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchCriteriaSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Search criteria")
            VStack(spacing: Theme.Spacing.md) {
                TextField("Keyword (e.g. hat, sweater)", text: $keyword)
                    .textFieldStyle(.plain)
                    .padding(Theme.Spacing.md)
                    .background(Theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .autocorrectionDisabled()
                TextField("Yarn weight (e.g. DK, Worsted)", text: $yarnWeight)
                    .textFieldStyle(.plain)
                    .padding(Theme.Spacing.md)
                    .background(Theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .autocorrectionDisabled()
                TextField("Needle/hook size (e.g. 4 mm, US 7)", text: $needleSize)
                    .textFieldStyle(.plain)
                    .padding(Theme.Spacing.md)
                    .background(Theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .autocorrectionDisabled()
                Picker("Craft", selection: $craftOption) {
                    ForEach(CraftOption.allCases, id: \.self) { o in
                        Text(o.rawValue).tag(o)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Free patterns only", isOn: $freeOnly)
                    .tint(Theme.sageGreen)
            }
            .padding(Theme.Spacing.md)
            .borderedCard()
        }
    }

    private var searchButton: some View {
        Button {
            runSearch()
        } label: {
            Label("Search patterns", systemImage: "magnifyingglass")
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.softCoral)
            Text("Searching Ravelry...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.softCoral)
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                runSearch()
            }
            .font(Theme.Typography.captionSemibold)
            .foregroundStyle(Theme.deepPlum)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var emptyPromptView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Enter materials above and tap Search to find patterns.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Results")
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(results) { result in
                    discoveryResultCard(result)
                }
            }
        }
    }

    private func discoveryResultCard(_ result: PatternDiscoveryResult) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if let urlString = result.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Theme.warmCream)
                            .overlay(Image(systemName: "photo").foregroundStyle(Theme.deepPlum.opacity(0.3)))
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            } else {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(Theme.warmCream)
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "doc.text").foregroundStyle(Theme.deepPlum.opacity(0.3)))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(result.title)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                if let craft = result.craftType {
                    Text(craft)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
                HStack(spacing: Theme.Spacing.sm) {
                    if result.isFree {
                        Text("Free")
                            .font(Theme.Typography.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.sageGreen.opacity(0.2))
                            .foregroundStyle(Theme.sageGreen)
                            .clipShape(Capsule())
                    } else {
                        Text("Paid")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    }
                    Text("Ravelry")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.xs) {
                Button {
                    if let u = URL(string: result.sourceUrl) {
                        UIApplication.shared.open(u)
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.dustyBlue)
                }
                .accessibilityLabel("Open in Safari")
                Button {
                    resultToSave = result
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.sageGreen)
                }
                .accessibilityLabel("Save to Pattern Vault")
            }
        }
        .padding(Theme.Spacing.md)
        .borderedCard()
    }

    /// Builds Ravelry's website search URL and opens it in Safari (used when API keys are not set).
    private func openRavelrySearchInSafari() {
        var components = URLComponents(string: "https://www.ravelry.com/patterns/search")!
        let q = keyword.isEmpty ? "pattern" : keyword
        var fragment = "query=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)"
        if let c = craftOption.ravelryValue {
            fragment += "&craft=\(c)"
        }
        if freeOnly {
            fragment += "&availability=free"
        }
        if !yarnWeight.isEmpty {
            fragment += "&weight=\(yarnWeight.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? yarnWeight)"
        }
        if !needleSize.isEmpty {
            fragment += "&needle_size=\(needleSize.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? needleSize)"
        }
        components.fragment = fragment
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    private func runSearch() {
        searchErrorMessage = nil
        results = []
        isLoading = true
        Task {
            let criteria = RavelrySearchCriteria(
                query: keyword.isEmpty ? "pattern" : keyword,
                yarnWeight: yarnWeight.isEmpty ? nil : yarnWeight,
                needleSize: needleSize.isEmpty ? nil : needleSize,
                craft: craftOption.ravelryValue,
                freeOnly: freeOnly
            )
            if let list = await RavelryPatternSearchService.search(criteria: criteria) {
                results = list
                if list.isEmpty {
                    searchErrorMessage = "No patterns found. Try different materials or keywords."
                }
            } else {
                searchErrorMessage = "Search failed. Check your connection and try again."
            }
            isLoading = false
        }
    }
}
