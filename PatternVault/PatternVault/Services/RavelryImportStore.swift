//
//  RavelryImportStore.swift
//  PatternVault
//
//  Coordinates fetching Ravelry library and importing into Pattern Vault with dedupe and progress.
//

import Foundation

@MainActor
final class RavelryImportStore: ObservableObject {

    @Published var ravelryUsername: String?
    @Published var isImporting = false
    @Published var importProgressImported: Int = 0
    @Published var importProgressTotal: Int = 0
    @Published var importError: String?
    @Published var lastImportResult: String?

    private let pageSize = 50
    private static let lastSyncKey = "ravelryLastSyncDate"
    private static let autoSyncKey = "ravelryAutoSyncEnabled"

    var isAutoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoSyncKey) }
    }

    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncKey) }
    }

    var shouldAutoSync: Bool {
        guard isAutoSyncEnabled else { return false }
        guard let last = lastSyncDate else { return true }
        return Date().timeIntervalSince(last) > 24 * 60 * 60
    }

    func fetchUsername(userId: UUID) async {
        ravelryUsername = nil
        do {
            let user = try await RavelryUserService.fetchCurrentUser(userId: userId)
            ravelryUsername = user.username
        } catch {
            ravelryUsername = nil
        }
    }

    /// Import Ravelry library, favorites, projects, and queue into Pattern Vault. Also imports stash into yarn stash.
    func importLibrary(userId: UUID, patternStore: PatternStore, yarnStashStore: YarnStashStore? = nil) async {
        let username: String
        if let existing = ravelryUsername {
            username = existing
        } else {
            do {
                let user = try await RavelryUserService.fetchCurrentUser(userId: userId)
                username = user.username
            } catch {
                importError = "Could not load your Ravelry username."
                return
            }
        }
        if username != ravelryUsername { ravelryUsername = username }
        importError = nil
        lastImportResult = nil
        isImporting = true
        importProgressImported = 0
        importProgressTotal = 0
        defer {
            isImporting = false
            lastSyncDate = Date()
        }

        var entriesByPatternId: [Int: RavelryLibraryEntry] = [:]
        func merge(_ batch: [RavelryLibraryEntry]) {
            for e in batch where entriesByPatternId[e.patternId] == nil {
                entriesByPatternId[e.patternId] = e
            }
        }

        do {
            var page = 1
            repeat {
                let batch = try await RavelryUserService.fetchLibrary(userId: userId, username: username, page: page, pageSize: pageSize)
                merge(batch)
                if batch.count < pageSize { break }
                page += 1
            } while true

            page = 1
            repeat {
                let batch = try await RavelryUserService.fetchFavorites(userId: userId, username: username, page: page, pageSize: pageSize)
                merge(batch)
                if batch.count < pageSize { break }
                page += 1
            } while true

            page = 1
            repeat {
                let batch = try await RavelryUserService.fetchProjects(userId: userId, username: username, page: page, pageSize: pageSize)
                merge(batch)
                if batch.count < pageSize { break }
                page += 1
            } while true

            // Queue
            page = 1
            repeat {
                let batch = try await RavelryUserService.fetchQueue(userId: userId, username: username, page: page, pageSize: pageSize)
                merge(batch)
                if batch.count < pageSize { break }
                page += 1
            } while true
        } catch {
            importError = error.localizedDescription
            return
        }

        var allEntries = Array(entriesByPatternId.values)
        importProgressTotal = allEntries.count
        if allEntries.isEmpty {
            lastImportResult = "No patterns in your Ravelry library, favorites, projects, or queue."
            return
        }

        let patternIds = allEntries.map(\.patternId)
        let batchSize = 50
        for start in stride(from: 0, to: patternIds.count, by: batchSize) {
            let chunk = Array(patternIds[start ..< min(start + batchSize, patternIds.count)])
            do {
                let details = try await RavelryUserService.fetchPatternDetails(userId: userId, patternIds: chunk)
                for i in allEntries.indices {
                    let id = allEntries[i].patternId
                    guard let detail = details[id] else { continue }
                    if let v = detail.imageUrl, !v.isEmpty { allEntries[i].imageUrl = v }
                    if let v = detail.pdfUrl, !v.isEmpty { allEntries[i].pdfUrl = v }
                    if let v = detail.description, !v.isEmpty { allEntries[i].patternDescription = v }
                    if let v = detail.difficulty, !v.isEmpty { allEntries[i].difficulty = v }
                    if let v = detail.gauge, !v.isEmpty { allEntries[i].gauge = v }
                    if let v = detail.craftName, !v.isEmpty { allEntries[i].craftName = v }
                    if let v = detail.needleHookSizes, !v.isEmpty { allEntries[i].needleHookSizes = v }
                    if let v = detail.yarnWeightYardage, !v.isEmpty { allEntries[i].yarnWeightYardage = v }
                }
            } catch {
                #if DEBUG
                print("[Ravelry] fetchPatternDetails failed: \(error)")
                #endif
            }
        }

        await patternStore.load(userId: userId)
        var existingUrls = Set(patternStore.patterns.map(\.sourceUrl))
        var imported = 0
        for entry in allEntries {
            let sourceUrl = "https://www.ravelry.com/patterns/library/\(entry.permalink)"
            if existingUrls.contains(sourceUrl) { continue }
            if !SubscriptionStore.shared.canAddPattern(currentPatternCount: patternStore.patterns.count + imported) {
                importError = "Pattern limit reached. Upgrade to Premium for unlimited patterns."
                break
            }
            let added = await patternStore.add(
                userId: userId,
                title: entry.name,
                description: entry.patternDescription,
                sourceUrl: sourceUrl,
                status: .wantToMake,
                thumbnailUrl: entry.imageUrl,
                difficulty: entry.difficulty,
                craftType: entry.craftName,
                pdfUrl: entry.pdfUrl,
                gauge: entry.gauge,
                needleHookSizes: entry.needleHookSizes,
                yarnWeightYardage: entry.yarnWeightYardage,
                enrichmentStatus: "pending"
            )
            if added {
                imported += 1
                existingUrls.insert(sourceUrl)
            }
            importProgressImported = imported
        }

        // Reload to trigger enrichment polling for newly imported patterns
        if imported > 0 {
            await patternStore.load(userId: userId)
        }

        // Import Ravelry stash into yarn stash
        var stashImported = 0
        if let yarnStashStore {
            do {
                var stashEntries: [RavelryStashEntry] = []
                var page = 1
                repeat {
                    let batch = try await RavelryUserService.fetchStash(userId: userId, username: username, page: page, pageSize: pageSize)
                    stashEntries.append(contentsOf: batch)
                    if batch.count < pageSize { break }
                    page += 1
                } while true

                await yarnStashStore.load(userId: userId)
                let existingStash = Set(yarnStashStore.items.map { "\($0.brandName.lowercased())|\($0.colorName?.lowercased() ?? "")|\($0.weight?.lowercased() ?? "")" })
                for entry in stashEntries {
                    let key = "\(entry.name.lowercased())|\(entry.colorway?.lowercased() ?? "")|\(entry.weightCategory?.lowercased() ?? "")"
                    if existingStash.contains(key) { continue }
                    let ypp = entry.yardage.map { Int($0.rounded()) }
                    await yarnStashStore.add(
                        userId: userId,
                        brandName: entry.name,
                        colorName: entry.colorway,
                        weight: entry.weightCategory,
                        yardagePerSkein: ypp,
                        skeinsOwned: entry.skeins,
                        location: entry.location,
                        notes: nil
                    )
                    stashImported += 1
                }
            } catch {
                #if DEBUG
                print("[Ravelry] stash import failed: \(error)")
                #endif
            }
        }

        var resultParts: [String] = []
        if imported > 0 {
            resultParts.append("Imported \(imported) pattern\(imported == 1 ? "" : "s")")
        }
        if stashImported > 0 {
            resultParts.append("\(stashImported) stash item\(stashImported == 1 ? "" : "s")")
        }
        if resultParts.isEmpty {
            lastImportResult = "No new patterns or stash items to import."
        } else {
            lastImportResult = resultParts.joined(separator: " and ") + "."
        }
    }

    func clearLastResult() {
        lastImportResult = nil
        importError = nil
    }
}
