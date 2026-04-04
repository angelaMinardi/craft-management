//
//  ProjectNoteStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class ProjectNoteStore: ObservableObject {
    @Published var notes: [ProjectNote] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo = ProjectNoteRepository()

    var generalCount: Int { notes.filter { $0.noteType == .general }.count }
    var yarnInfoCount: Int { notes.filter { $0.noteType == .yarnInfo }.count }
    var modificationsCount: Int { notes.filter { $0.noteType == .modifications }.count }
    var progressUpdateCount: Int { notes.filter { $0.noteType == .progressUpdate }.count }

    func load(patternId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            notes = try await repo.fetchNotes(patternId: patternId)
        } catch {
            #if DEBUG
            print("[ProjectNoteStore] load failed: \(error)")
            #endif
            errorMessage = "Could not load notes. Please try again."
        }
    }

    func add(
        patternId: UUID,
        userId: UUID,
        noteType: ProjectNoteType,
        content: String,
        photoData: Data?,
        durationMinutes: Int? = nil
    ) async -> Bool {
        errorMessage = nil
        do {
            if photoData != nil {
                let count = try await repo.countNotesWithPhoto(userId: userId)
                if !SubscriptionStore.shared.canAddNotePhoto(currentNotePhotoCount: count) {
                    errorMessage = "Note photo limit reached. Upgrade to Premium for unlimited photos."
                    return false
                }
            }
            var photoUrl: String? = nil
            let noteId = UUID()
            if let photoData {
                photoUrl = try await repo.uploadPhoto(imageData: photoData, noteId: noteId)
            }
            let note = try await repo.addNote(
                patternId: patternId,
                userId: userId,
                noteType: noteType,
                content: content,
                photoUrl: photoUrl,
                durationMinutes: durationMinutes
            )
            notes.insert(note, at: 0)
            return true
        } catch {
            #if DEBUG
            print("[ProjectNoteStore] add failed: \(error)")
            #endif
            errorMessage = "Could not save note. Please try again."
            return false
        }
    }

    func update(noteId: UUID, userId: UUID, content: String?, noteType: ProjectNoteType?, photoUrl: String?) async {
        errorMessage = nil
        do {
            let updated = try await repo.updateNote(
                id: noteId,
                userId: userId,
                content: content,
                noteType: noteType,
                photoUrl: photoUrl
            )
            if let idx = notes.firstIndex(where: { $0.id == noteId }) {
                notes[idx] = updated
            }
        } catch {
            #if DEBUG
            print("[ProjectNoteStore] update failed: \(error)")
            #endif
            errorMessage = "Could not update note. Please try again."
        }
    }

    func delete(noteId: UUID, userId: UUID) async {
        errorMessage = nil
        do {
            try await repo.deleteNote(id: noteId, userId: userId)
            notes.removeAll { $0.id == noteId }
        } catch {
            #if DEBUG
            print("[ProjectNoteStore] delete failed: \(error)")
            #endif
            errorMessage = "Could not delete note. Please try again."
        }
    }
}
