//
//  TagPickerView.swift
//  PatternVault
//

import SwiftUI

struct TagPickerView: View {
    @ObservedObject var tagStore: TagStore
    let patternId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTagIds: Set<UUID> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(TagStore.categoryOrder, id: \.self) { category in
                    if let tags = tagStore.tagsByCategory[category], !tags.isEmpty {
                        Section(TagStore.categoryDisplayNames[category] ?? category) {
                            ForEach(tags) { tag in
                                Button {
                                    toggleTag(tag.id)
                                } label: {
                                    HStack {
                                        Text(tag.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedTagIds.contains(tag.id) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmCream)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                selectedTagIds = Set(tagStore.patternTags.map(\.id))
            }
        }
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIds.contains(id) {
            selectedTagIds.remove(id)
        } else {
            selectedTagIds.insert(id)
        }
    }

    private func save() {
        isSaving = true
        Task {
            await tagStore.setTags(patternId: patternId, tagIds: selectedTagIds)
            isSaving = false
            dismiss()
        }
    }
}
