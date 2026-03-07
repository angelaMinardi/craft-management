//
//  NoteDetailView.swift
//  PatternVault
//

import SwiftUI

struct NoteDetailView: View {
    @ObservedObject var noteStore: ProjectNoteStore
    let note: ProjectNote
    let patternId: UUID

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var current: ProjectNote {
        noteStore.notes.first(where: { $0.id == note.id }) ?? note
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Type badge
                HStack {
                    Image(systemName: Theme.noteTypeIcon(for: current.noteType))
                        .foregroundStyle(Theme.noteTypeColor(for: current.noteType))
                    Text(current.noteType.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.noteTypeColor(for: current.noteType))
                    Spacer()
                }

                // Content
                Text(current.content)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum)

                // Photo
                if let photoUrl = current.photoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(Theme.CornerRadius.small)
                        case .failure:
                            Label("Photo unavailable", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                                .font(Theme.Typography.caption)
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 100)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                // Timestamps
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Created \(current.createdAt, style: .date) at \(current.createdAt, style: .time)")
                    if current.updatedAt != current.createdAt {
                        Text("Updated \(current.updatedAt, style: .relative) ago")
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))

                Spacer()
            }
            .padding()
        }
        .background(Theme.warmCream)
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddNoteView(
                noteStore: noteStore,
                patternId: patternId,
                existingNote: current
            )
        }
        .confirmationDialog("Delete Note", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteNote() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func deleteNote() {
        Task {
            await noteStore.delete(noteId: current.id)
            dismiss()
        }
    }
}
