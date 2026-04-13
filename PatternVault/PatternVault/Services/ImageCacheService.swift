//
//  ImageCacheService.swift
//  PatternVault
//
//  Caches pattern/note images locally (user-scoped) so they load offline and update when online.
//

import Foundation
import CryptoKit
import UIKit
import SwiftUI

/// Loads images from local cache when available; otherwise downloads from URL and caches for next time.
/// Cache is stored in Caches/PatternImageCache/{userId}/ so it can be purged by the system and is per-user.
/// Enforces a 200 MB size limit with LRU eviction.
final class ImageCacheService {
    static let shared = ImageCacheService()

    private let fileManager = FileManager.default
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Maximum total cache size in bytes (200 MB).
    private let maxCacheSize: Int64 = 200_000_000

    /// Running total of bytes stored on disk across all user directories.
    private var totalCacheSize: Int64 = 0

    /// Last access time per cache file path (absolute path string).
    private var accessTimes: [String: Date] = [:]

    /// Serial queue protecting mutable cache bookkeeping.
    private let lock = NSLock()

    private init() {
        scanExistingCache()
    }

    /// Walk all files under PatternImageCache to seed `totalCacheSize` and `accessTimes`.
    private func scanExistingCache() {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let root = caches.appendingPathComponent("PatternImageCache", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        var size: Int64 = 0
        var times: [String: Date] = [:]
        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { continue }
            size += Int64(data.count)
            times[fileURL.path] = Date.distantPast
        }
        lock.lock()
        totalCacheSize = size
        accessTimes = times
        lock.unlock()
    }

    /// Cache directory for a user: Caches/PatternImageCache/{userId}
    private func cacheDirectory(userId: UUID) -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("PatternImageCache", isDirectory: true)
            .appendingPathComponent(userId.uuidString, isDirectory: true)
        return dir
    }

    /// Stable filename from URL (SHA256 prefix + extension).
    private func cacheFilename(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.lowercased()
        let safeExt = ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) ? ext : "jpg"
        return String(hex.prefix(32)) + "." + safeExt
    }

    /// If cached file exists, returns its data immediately. Otherwise returns nil (caller can then load from network).
    func cachedData(for url: URL, userId: UUID) -> Data? {
        guard let dir = cacheDirectory(userId: userId) else { return nil }
        let fileURL = dir.appendingPathComponent(cacheFilename(for: url))
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // Update LRU access time
        let path = fileURL.path
        lock.lock()
        accessTimes[path] = Date()
        lock.unlock()
        return data
    }

    /// Load image data: from cache if present, otherwise download, save to cache, and return. Returns nil when offline and not cached.
    func imageData(for url: URL, userId: UUID) async -> Data? {
        if let cached = cachedData(for: url, userId: userId) {
            return cached
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard !data.isEmpty, UIImage(data: data) != nil else { return nil }
            saveToCache(data: data, remoteURL: url, userId: userId)
            return data
        } catch {
            return nil
        }
    }

    func saveToCache(data: Data, remoteURL: URL, userId: UUID) {
        guard let dir = cacheDirectory(userId: userId) else { return }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(cacheFilename(for: remoteURL))
        let newFileSize = Int64(data.count)
        let path = fileURL.path

        // If we're overwriting an existing file, subtract old size first
        lock.lock()
        if let oldData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
            totalCacheSize -= Int64(oldData.count)
        }
        lock.unlock()

        try? data.write(to: fileURL)

        lock.lock()
        totalCacheSize += newFileSize
        accessTimes[path] = Date()
        lock.unlock()

        evictIfNeeded()
    }

    /// Remove least recently accessed files until total cache size is within the limit.
    private func evictIfNeeded() {
        lock.lock()
        guard totalCacheSize > maxCacheSize else {
            lock.unlock()
            return
        }
        // Sort by access time ascending (oldest first)
        let sorted = accessTimes.sorted { $0.value < $1.value }
        lock.unlock()

        for (path, _) in sorted {
            lock.lock()
            let currentSize = totalCacheSize
            lock.unlock()
            if currentSize <= maxCacheSize { break }

            let fileURL = URL(fileURLWithPath: path)
            guard let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { continue }
            let fileSize = fileData.count
            do {
                try fileManager.removeItem(at: fileURL)
                lock.lock()
                totalCacheSize -= Int64(fileSize)
                accessTimes.removeValue(forKey: path)
                lock.unlock()
            } catch {
                // File may already be gone; skip
            }
        }
    }

    /// Remove all cached images for a user (e.g. on logout). Optional.
    func clearCache(userId: UUID) {
        guard let dir = cacheDirectory(userId: userId) else { return }
        let dirPath = dir.path
        // Remove matching entries from bookkeeping before deleting
        lock.lock()
        let pathsToRemove = accessTimes.keys.filter { $0.hasPrefix(dirPath) }
        for path in pathsToRemove {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
                totalCacheSize -= Int64(data.count)
            }
            accessTimes.removeValue(forKey: path)
        }
        lock.unlock()
        try? fileManager.removeItem(at: dir)
    }
}

// MARK: - Cached async image view

enum CachedImagePhase {
    case loading
    case success(Image)
    case failure
}

/// Loads an image from local cache when available; otherwise downloads and caches. Use when url and userId are non-nil; falls back to loading/placeholder when userId is nil or offline.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let userId: UUID?
    @ViewBuilder let content: (CachedImagePhase) -> Content

    @State private var phase: CachedImagePhase = .loading

    private let cache = ImageCacheService.shared

    var body: some View {
        content(phase)
            .task(id: url?.absoluteString) {
                await load()
            }
    }

    private func load() async {
        guard let url = url else {
            phase = .failure
            return
        }
        if let userId = userId {
            if let data = await cache.imageData(for: url, userId: userId),
               let uiImage = UIImage(data: data) {
                phase = .success(Image(uiImage: uiImage))
            } else {
                phase = .failure
            }
        } else {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    phase = .success(Image(uiImage: uiImage))
                } else {
                    phase = .failure
                }
            } catch {
                phase = .failure
            }
        }
    }
}
