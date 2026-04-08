//
//  AddNeedleHookView.swift
//  PatternVault
//
//  Add or edit any tool (needles, hooks, cutters, etc.).
//

import SwiftUI

struct AddNeedleHookView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var needleHookStore: NeedleHookStore
    @Environment(\.dismiss) private var dismiss

    var existingItem: NeedleHookItem?

    @State private var typeName = ""
    @State private var size = ""
    @State private var lengthCm = ""
    @State private var notes = ""
    @State private var isSaving = false

    private var isEditing: Bool { existingItem != nil }
    private var canSave: Bool {
        !typeName.trimmingCharacters(in: .whitespaces).isEmpty
        && !size.trimmingCharacters(in: .whitespaces).isEmpty
        && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    TextField("Tool type", text: $typeName, prompt: Text("e.g. Needle, Hook, Leather cutter, Rotary cutter"))
                        .textInputAutocapitalization(.words)
                    TextField("Size or spec", text: $size, prompt: Text("e.g. US 7, 4mm, 9mm blade"))
                        .textInputAutocapitalization(.never)
                }

                Section("Details (optional)") {
                    TextField("Length or dimensions", text: $lengthCm, prompt: Text("e.g. length in cm"))
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let error = needleHookStore.errorMessage {
                    Section {
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Something went wrong. Try again?")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                            SpriteMascotView.pouty(size: 56)
                            Text(error)
                                .foregroundStyle(Theme.softCoral)
                                .font(Theme.Typography.caption)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit tool" : "Add tool")
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
            .onAppear {
                if let item = existingItem {
                    typeName = item.type
                    size = item.size
                    lengthCm = item.lengthCm.map { "\($0)" } ?? ""
                    notes = item.notes ?? ""
                }
            }
        }
    }

    private func save() {
        guard let userId = auth.currentUserId else { return }
        let trimmedType = typeName.trimmingCharacters(in: .whitespaces)
        let trimmedSize = size.trimmingCharacters(in: .whitespaces)
        guard !trimmedType.isEmpty, !trimmedSize.isEmpty else { return }
        let length = Double(lengthCm.trimmingCharacters(in: .whitespaces))
        isSaving = true

        Task {
            if let existing = existingItem {
                var updated = existing
                updated.type = trimmedType
                updated.size = trimmedSize
                updated.lengthCm = length
                updated.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
                await needleHookStore.update(updated)
            } else {
                await needleHookStore.add(userId: userId, type: trimmedType, size: trimmedSize, lengthCm: length, notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces))
                if needleHookStore.errorMessage == nil, needleHookStore.items.count == 1 {
                    CelebrationStore.shared.unlock("toolbox_ready")
                }
            }
            isSaving = false
            if needleHookStore.errorMessage == nil { dismiss() }
        }
    }
}
