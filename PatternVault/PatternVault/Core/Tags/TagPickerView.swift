//
//  TagPickerView.swift
//  PatternVault
//

import SwiftUI

struct TagPickerView: View {
    @ObservedObject var tagStore: TagStore
    let patternId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTagIds: Set<UUID> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                if tagStore.tagsByCategory.values.allSatisfy({ $0.isEmpty }) {
                    VStack(spacing: Theme.Spacing.xl) {
                        Spacer()
                        TappableMascotView(size: 100)
                        Text("No tags yet")
                            .font(Theme.Typography.sectionTitle)
                            .foregroundStyle(Theme.deepPlum)
                        Text("Tags will appear here once they're created for your patterns.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
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
                                                        .transition(.scale.combined(with: .opacity))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Tags")
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
                    }
                }
            }
            .onAppear {
                selectedTagIds = Set(tagStore.patternTags.map(\.id))
            }
        }
    }

    private func toggleTag(_ id: UUID) {
        withAnimation(reduceMotion ? .none : Theme.Motion.spring) {
            if selectedTagIds.contains(id) {
                selectedTagIds.remove(id)
            } else {
                selectedTagIds.insert(id)
            }
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
