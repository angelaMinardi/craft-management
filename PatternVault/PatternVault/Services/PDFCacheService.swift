//
//  PDFCacheService.swift
//  PatternVault
//
//  Caches downloaded PDF files locally for offline access.
//  Max cache: 500MB with TTL + LRU eviction.
//

import Foundation

enum PDFCacheService {
    private static let cacheDir = "PatternPDFs"
    private static let maxCacheBytes: UInt64 = 500_000_000 // 500 MB
    private static let cacheTTL: TimeInterval = 30 * 24 * 60 * 60
    private static let accessIndexFilename = "access-index.json"

    private static var cacheDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent(cacheDir)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func sourceKey(for sourceURL: URL) -> String {
        var hash = UInt64(1469598103934665603)
        for byte in sourceURL.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func fileURL(for patternId: UUID, sourceURL: URL) -> URL? {
        cacheDirectory?.appendingPathComponent("\(patternId.uuidString)_\(sourceKey(for: sourceURL)).pdf")
    }

    private static func legacyFileURL(for patternId: UUID) -> URL? {
        cacheDirectory?.appendingPathComponent("\(patternId.uuidString).pdf")
    }

    private static func accessIndexURL(in dir: URL) -> URL {
        dir.appendingPathComponent(accessIndexFilename)
    }

    private static func loadAccessIndex(in dir: URL) -> [String: TimeInterval] {
        let url = accessIndexURL(in: dir)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveAccessIndex(_ index: [String: TimeInterval], in dir: URL) {
        let url = accessIndexURL(in: dir)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: url)
    }

    private static func touchAccess(for filename: String, in dir: URL) {
        var index = loadAccessIndex(in: dir)
        index[filename] = Date().timeIntervalSince1970
        saveAccessIndex(index, in: dir)
    }

    private static func removeAccessEntry(for filename: String, in dir: URL) {
        var index = loadAccessIndex(in: dir)
        index.removeValue(forKey: filename)
        saveAccessIndex(index, in: dir)
    }

    static func cachedPDF(for patternId: UUID, sourceURL: URL) -> Data? {
        guard let dir = cacheDirectory else { return nil }
        let file = fileURL(for: patternId, sourceURL: sourceURL) ?? dir.appendingPathComponent("\(patternId.uuidString).pdf")
        if !FileManager.default.fileExists(atPath: file.path),
           let legacyFile = legacyFileURL(for: patternId),
           FileManager.default.fileExists(atPath: legacyFile.path),
           legacyFile.path != file.path {
            try? FileManager.default.moveItem(at: legacyFile, to: file)
            touchAccess(for: file.lastPathComponent, in: dir)
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let accessIndex = loadAccessIndex(in: dir)
        let lastAccess = accessIndex[file.lastPathComponent] ?? fileTimestamp(file) ?? 0
        if Date().timeIntervalSince1970 - lastAccess > cacheTTL {
            try? FileManager.default.removeItem(at: file)
            removeAccessEntry(for: file.lastPathComponent, in: dir)
            return nil
        }
        touchAccess(for: file.lastPathComponent, in: dir)
        return try? Data(contentsOf: file)
    }

    static func cachePDF(data: Data, patternId: UUID, sourceURL: URL) {
        guard let dir = cacheDirectory,
              let file = fileURL(for: patternId, sourceURL: sourceURL) else { return }
        removeAllCachedPDFs(for: patternId, keeping: file.lastPathComponent)
        try? data.write(to: file)
        touchAccess(for: file.lastPathComponent, in: dir)
        evictIfNeeded()
    }

    static func loadOrDownload(url: URL, patternId: UUID) async -> Data? {
        if let cached = cachedPDF(for: patternId, sourceURL: url) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            cachePDF(data: data, patternId: patternId, sourceURL: url)
            return data
        } catch {
            return nil
        }
    }

    static func removeAllCachedPDFs(for patternId: UUID, keeping keptFilename: String? = nil) {
        guard let dir = cacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let prefix = patternId.uuidString
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            if let keptFilename, file.lastPathComponent == keptFilename { continue }
            try? FileManager.default.removeItem(at: file)
            removeAccessEntry(for: file.lastPathComponent, in: dir)
        }
    }

    private static func evictIfNeeded() {
        guard let dir = cacheDirectory else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let pdfFiles = files.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfFiles.isEmpty else { return }

        let accessIndex = loadAccessIndex(in: dir)
        let now = Date().timeIntervalSince1970

        var totalSize: UInt64 = 0
        var fileInfos: [(url: URL, size: UInt64, lastAccess: TimeInterval)] = []
        for file in pdfFiles {
            let lastAccess = accessIndex[file.lastPathComponent] ?? fileTimestamp(file) ?? 0
            if now - lastAccess > cacheTTL {
                try? fm.removeItem(at: file)
                removeAccessEntry(for: file.lastPathComponent, in: dir)
                continue
            }
            guard let size = fileSize(file) else { continue }
            totalSize += size
            fileInfos.append((file, size, lastAccess))
        }

        guard totalSize > maxCacheBytes else { return }
        // Evict oldest first
        fileInfos.sort { $0.lastAccess < $1.lastAccess }
        for info in fileInfos {
            try? fm.removeItem(at: info.url)
            removeAccessEntry(for: info.url.lastPathComponent, in: dir)
            totalSize -= info.size
            if totalSize <= maxCacheBytes { break }
        }
    }

    private static func fileTimestamp(_ file: URL) -> TimeInterval? {
        guard let values = try? file.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey]) else { return nil }
        return (values.contentAccessDate ?? values.contentModificationDate)?.timeIntervalSince1970
    }

    private static func fileSize(_ file: URL) -> UInt64? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return UInt64(size)
    }
}
