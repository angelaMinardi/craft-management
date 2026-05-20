//
//  PDFAnnotationStore.swift
//  PatternVault
//
//  File-based persistence for PencilKit drawings on PDF patterns.
//  One .drawing file per pattern UUID in Application Support/PDFAnnotations/.
//

import Foundation
import PencilKit

@MainActor
final class PDFAnnotationStore: ObservableObject {
    static let shared = PDFAnnotationStore()

    private let storageDir: URL
    private var saveTimer: Timer?
    private var pendingWrites: [UUID: Data] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("PDFAnnotations", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func load(patternId: UUID) -> Data? {
        let url = fileURL(for: patternId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Debounced save — buffers writes and flushes after 0.5s of inactivity.
    func save(data: Data?, patternId: UUID) {
        guard let data, !data.isEmpty else {
            pendingWrites.removeValue(forKey: patternId)
            return
        }
        pendingWrites[patternId] = data
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushPendingWrites()
            }
        }
    }

    /// Immediate save — use when the view is being dismissed.
    func saveImmediately(data: Data?, patternId: UUID) {
        saveTimer?.invalidate()
        guard let data, !data.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL(for: patternId))
            pendingWrites.removeValue(forKey: patternId)
            return
        }
        writeToDisk(data: data, patternId: patternId)
        pendingWrites.removeValue(forKey: patternId)
    }

    func delete(patternId: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: patternId))
        pendingWrites.removeValue(forKey: patternId)
    }

    // MARK: - Private

    private func fileURL(for patternId: UUID) -> URL {
        storageDir.appendingPathComponent("\(patternId.uuidString).drawing")
    }

    private func flushPendingWrites() {
        for (patternId, data) in pendingWrites {
            writeToDisk(data: data, patternId: patternId)
        }
        pendingWrites.removeAll()
    }

    private func writeToDisk(data: Data, patternId: UUID) {
        let url = fileURL(for: patternId)
        try? data.write(to: url, options: .atomic)
    }
}
