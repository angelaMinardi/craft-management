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
final class ImageCacheService {
    static let shared = ImageCacheService()

    private let fileManager = FileManager.default
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private init() {}

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
        return try? Data(contentsOf: fileURL)
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
        try? data.write(to: fileURL)
    }

    /// Remove all cached images for a user (e.g. on logout). Optional.
    func clearCache(userId: UUID) {
        guard let dir = cacheDirectory(userId: userId) else { return }
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
