//
//  AddNoteView.swift
//  PatternVault
//

import SwiftUI
import PhotosUI

struct AddNoteView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var noteStore: ProjectNoteStore
    @Environment(\.dismiss) private var dismiss

    let patternId: UUID

    /// When editing an existing note, pass it here
    var existingNote: ProjectNote?

    @State private var noteType: ProjectNoteType = .general
    @State private var content = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: Image?
    @State private var isSaving = false

    private var isEditing: Bool { existingNote != nil }
    private var canSave: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note Type") {
                    Picker("Type", selection: $noteType) {
                        ForEach(ProjectNoteType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Content") {
                    TextField("Write your note...", text: $content, axis: .vertical)
                        .lineLimit(4...12)
                }

                Section("Photo (optional)") {
                    if let photoPreview {
                        photoPreview
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)

                        Button("Remove Photo", role: .destructive) {
                            selectedPhoto = nil
                            photoData = nil
                            self.photoPreview = nil
                        }
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoPreview == nil ? "Add Photo" : "Change Photo", systemImage: "photo.badge.plus")
                    }
                }

                if let error = noteStore.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(Theme.softCoral)
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmCream)
            .navigationTitle(isEditing ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                loadPhoto(from: newItem)
            }
            .onAppear {
                if let note = existingNote {
                    noteType = note.noteType
                    content = note.content
                }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoData = data
                if let uiImage = UIImage(data: data) {
                    photoPreview = Image(uiImage: uiImage)
                }
            }
        }
    }

    private func save() {
        guard let userId = auth.currentUserId else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true

        Task {
            if let existing = existingNote {
                // Update existing note
                await noteStore.update(
                    noteId: existing.id,
                    content: trimmed,
                    noteType: noteType,
                    photoUrl: existing.photoUrl // keep existing photo for now
                )
                isSaving = false
                dismiss()
            } else {
                // Add new note
                let success = await noteStore.add(
                    patternId: patternId,
                    userId: userId,
                    noteType: noteType,
                    content: trimmed,
                    photoData: photoData
                )
                isSaving = false
                if success { dismiss() }
            }
        }
    }
}
