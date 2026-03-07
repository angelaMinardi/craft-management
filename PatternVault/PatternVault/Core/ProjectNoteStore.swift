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
            errorMessage = error.localizedDescription
        }
    }

    func add(patternId: UUID, userId: UUID, noteType: ProjectNoteType, content: String, photoData: Data?) async -> Bool {
        errorMessage = nil
        do {
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
                photoUrl: photoUrl
            )
            notes.insert(note, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func update(noteId: UUID, content: String?, noteType: ProjectNoteType?, photoUrl: String?) async {
        errorMessage = nil
        do {
            let updated = try await repo.updateNote(
                id: noteId,
                content: content,
                noteType: noteType,
                photoUrl: photoUrl
            )
            if let idx = notes.firstIndex(where: { $0.id == noteId }) {
                notes[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(noteId: UUID) async {
        errorMessage = nil
        do {
            try await repo.deleteNote(id: noteId)
            notes.removeAll { $0.id == noteId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
