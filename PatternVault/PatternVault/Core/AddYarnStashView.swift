//
//  AddYarnStashView.swift
//  PatternVault
//

import SwiftUI

struct AddYarnStashView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var stashStore: YarnStashStore
    @Environment(\.dismiss) private var dismiss

    var existingItem: YarnStashItem?

    @State private var brandName = ""
    @State private var colorName = ""
    @State private var weight = ""
    @State private var yardagePerSkein = ""
    @State private var skeinsOwned = "1"
    @State private var location = ""
    @State private var notes = ""
    @State private var isSaving = false

    private var isEditing: Bool { existingItem != nil }
    private var canSave: Bool {
        !brandName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Brand or name", text: $brandName)
                        .textInputAutocapitalization(.words)
                    TextField("Color (optional)", text: $colorName)
                        .textInputAutocapitalization(.words)
                    TextField("Weight or spec (optional)", text: $weight, prompt: Text("e.g. DK, thread count, fabric weight"))
                        .textInputAutocapitalization(.words)
                }

                Section("Amount") {
                    TextField("Amount per unit (optional)", text: $yardagePerSkein, prompt: Text("e.g. 200 (yards per skein)"))
                        .keyboardType(.decimalPad)
                    TextField("Quantity", text: $skeinsOwned)
                        .keyboardType(.decimalPad)
                }

                Section("Details (optional)") {
                    TextField("Location (e.g. closet, bin)", text: $location)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let error = stashStore.errorMessage {
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
            .navigationTitle(isEditing ? "Edit item" : "Add to stash")
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
                    brandName = item.brandName
                    colorName = item.colorName ?? ""
                    weight = item.weight ?? ""
                    yardagePerSkein = item.yardagePerSkein.map { "\($0)" } ?? ""
                    skeinsOwned = item.skeinsOwned == 0 ? "" : "\(item.skeinsOwned)"
                    location = item.location ?? ""
                    notes = item.notes ?? ""
                }
            }
        }
    }

    private func save() {
        guard let userId = auth.currentUserId else { return }
        let brand = brandName.trimmingCharacters(in: .whitespaces)
        guard !brand.isEmpty else { return }
        let ypp: Int? = {
            let trimmed = yardagePerSkein.trimmingCharacters(in: .whitespaces)
            if let i = Int(trimmed) { return i }
            if let d = Double(trimmed) { return Int(d.rounded()) }
            return nil
        }()
        let skeins = Double(skeinsOwned.trimmingCharacters(in: .whitespaces)) ?? 1
        isSaving = true

        Task {
            if let existing = existingItem {
                var updated = existing
                updated.brandName = brand
                updated.colorName = colorName.isEmpty ? nil : colorName.trimmingCharacters(in: .whitespaces)
                updated.weight = weight.isEmpty ? nil : weight.trimmingCharacters(in: .whitespaces)
                updated.yardagePerSkein = ypp
                updated.skeinsOwned = max(0, skeins)
                updated.location = location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces)
                updated.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
                await stashStore.update(updated)
            } else {
                await stashStore.add(userId: userId, brandName: brand, colorName: colorName.isEmpty ? nil : colorName.trimmingCharacters(in: .whitespaces), weight: weight.isEmpty ? nil : weight.trimmingCharacters(in: .whitespaces), yardagePerSkein: ypp, skeinsOwned: max(0, skeins), location: location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces), notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces))
                if stashStore.errorMessage == nil, stashStore.items.count == 1 {
                    CelebrationStore.shared.unlock("stash_started")
                }
            }
            isSaving = false
            if stashStore.errorMessage == nil { dismiss() }
        }
    }
}
