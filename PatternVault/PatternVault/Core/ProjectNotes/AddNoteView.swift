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

    /// When adding a note for a specific step, pass the step index
    var stepIndex: Int?

    @State private var noteType: ProjectNoteType = .general
    @State private var content = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: Image?
    @State private var isSaving = false
    @State private var showPaywall = false

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

                if let stepIndex {
                    Section {
                        Label("Note for Step \(stepIndex + 1)", systemImage: "bookmark.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.dustyBlue)
                    }
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
                        VStack(spacing: Theme.Spacing.sm) {
                            SpriteMascotView.pouty(size: 56)
                            Text(error)
                                .foregroundStyle(Theme.softCoral)
                                .font(Theme.Typography.caption)
                                .multilineTextAlignment(.center)
                            if error.localizedCaseInsensitiveContains("Premium") || (error.localizedCaseInsensitiveContains("photo") && error.localizedCaseInsensitiveContains("limit")) {
                                Button(Theme.Premium.seePremiumTitle) {
                                    if GrowthOrchestrator.shared.canShowPaywall(source: .notePhotoLimit) {
                                        showPaywall = true
                                    }
                                }
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.softCoral)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .notePhotoLimit)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Note" : (stepIndex != nil ? "Step Note" : "Add Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
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
                await noteStore.update(
                    noteId: existing.id,
                    userId: userId,
                    content: trimmed,
                    noteType: noteType,
                    photoUrl: existing.photoUrl
                )
                isSaving = false
                HapticService.success()
                dismiss()
            } else {
                let success = await noteStore.add(
                    patternId: patternId,
                    userId: userId,
                    noteType: noteType,
                    content: trimmed,
                    photoData: photoData,
                    stepIndex: stepIndex
                )
                isSaving = false
                if success {
                    HapticService.success()
                    CelebrationStore.shared.unlock("first_note")
                    UserDefaults.standard.set(true, forKey: "mascot_has_any_note")
                    UserDefaults(suiteName: "group.com.patternvault.app")?.set(true, forKey: "mascot_has_any_note")
                    dismiss()
                }
            }
        }
    }
}
