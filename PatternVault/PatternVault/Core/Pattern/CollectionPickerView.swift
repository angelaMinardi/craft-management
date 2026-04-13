//
//  CollectionPickerView.swift
//  PatternVault
//

import SwiftUI

struct CollectionPickerView: View {
    @EnvironmentObject private var auth: AuthService
    @ObservedObject var collectionStore: CollectionStore
    let currentCollectionId: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNewFolderField = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        Text("No folder")
                            .foregroundStyle(Theme.deepPlum)
                        Spacer()
                        if currentCollectionId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.sageGreen)
                        }
                    }
                }

                ForEach(collectionStore.collections) { collection in
                    Button {
                        onSelect(collection.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: collection.icon)
                                .foregroundStyle(Theme.dustyBlue)
                            Text(collection.name)
                                .foregroundStyle(Theme.deepPlum)
                            Spacer()
                            if currentCollectionId == collection.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.sageGreen)
                            }
                        }
                    }
                }

                if showNewFolderField {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(Theme.sageGreen)
                        TextField("Folder name", text: $newFolderName)
                            .submitLabel(.done)
                            .onSubmit { createFolder() }
                        Button("Add") { createFolder() }
                            .foregroundStyle(Theme.sageGreen)
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Button {
                        showNewFolderField = true
                    } label: {
                        Label("New folder…", systemImage: "folder.badge.plus")
                            .foregroundStyle(Theme.sageGreen)
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard let userId = auth.currentUserId else { return }
        Task {
            await collectionStore.create(name: name, userId: userId)
        }
        newFolderName = ""
        showNewFolderField = false
    }
}
