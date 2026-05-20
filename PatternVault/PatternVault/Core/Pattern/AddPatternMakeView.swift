//
//  AddPatternMakeView.swift
//  PatternVault
//

import SwiftUI

struct AddPatternMakeView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    let patternId: UUID
    let existingCount: Int
    /// Size labels derived from multi-size repeat instructions (e.g. ["Small", "Medium", "Large"]).
    /// When non-empty, shows a size picker and saves the selected index to the make record.
    var sizeOptions: [String] = []
    var onSaved: ((PatternMake) -> Void)?

    @State private var name = ""
    @State private var sizeName = ""
    @State private var yardageUsed = ""
    @State private var sizeMeasurements = ""
    @State private var selectedSizeIndex: Int = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let repo = PatternMakeRepository()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Make") {
                    TextField("Name", text: $name, prompt: Text("e.g. Gift for Mom"))
                        .textInputAutocapitalization(.words)
                }
                if sizeOptions.count > 1 {
                    Section("Pattern size") {
                        Picker("Size", selection: $selectedSizeIndex) {
                            ForEach(sizeOptions.indices, id: \.self) { i in
                                Text(sizeOptions[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Details (optional)") {
                    TextField("Size", text: $sizeName, prompt: Text("e.g. M, 36\" chest"))
                        .textInputAutocapitalization(.words)
                    TextField("Yardage used", text: $yardageUsed)
                        .keyboardType(.numberPad)
                    TextField("Measurements", text: $sizeMeasurements, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let error = errorMessage {
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
            .navigationTitle("Add make")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if name.isEmpty {
                    name = "Make \(existingCount + 1)"
                }
            }
        }
    }

    private func save() {
        guard let userId = auth.currentUserId else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let yardage = Int(yardageUsed.trimmingCharacters(in: .whitespaces))
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let make = try await repo.add(
                    patternId: patternId, userId: userId,
                    name: trimmedName,
                    sizeName: sizeName.isEmpty ? nil : sizeName.trimmingCharacters(in: .whitespaces),
                    yardageUsed: yardage,
                    sizeMeasurements: sizeMeasurements.isEmpty ? nil : sizeMeasurements.trimmingCharacters(in: .whitespaces),
                    sizeIndex: sizeOptions.count > 1 ? selectedSizeIndex : nil
                )
                onSaved?(make)
                isSaving = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
