//
//  SecondaryCounterConfigSheet.swift
//  PatternVault
//

import SwiftUI

struct SecondaryCounterConfigSheet: View {
    let existing: SecondaryCounter?
    let onSave: (SecondaryCounter) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var resetAfter: Int = 8
    @State private var hasMaxResets = false
    @State private var maxResets: Int = 6
    @State private var linkMode: SecondaryCounter.LinkMode = .oneWay
    @State private var color: String = "softCoral"

    private let colorOptions = ["softCoral", "sageGreen", "dustyBlue", "honey", "deepPlum"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Counter") {
                    TextField("Title", text: $title)
                    Stepper("Reset after \(resetAfter) rows", value: $resetAfter, in: 1...999)
                }

                Section("Cycle limit") {
                    Toggle("Set maximum cycles", isOn: $hasMaxResets)
                    if hasMaxResets {
                        Stepper("Max cycles: \(maxResets)", value: $maxResets, in: 1...999)
                    }
                }

                Section("Link mode") {
                    Picker("Mode", selection: $linkMode) {
                        Text("One-way").tag(SecondaryCounter.LinkMode.oneWay)
                        Text("Two-way").tag(SecondaryCounter.LinkMode.twoWay)
                        Text("Unlinked").tag(SecondaryCounter.LinkMode.unlinked)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Color") {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(colorOptions, id: \.self) { name in
                            Circle()
                                .fill(themeColor(name))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if color == name {
                                        Circle().stroke(selectedRingColor(for: name), lineWidth: 2.2)
                                    }
                                }
                                .onTapGesture { color = name }
                        }
                    }
                }

                if let onDelete {
                    Section {
                        Button("Delete Counter", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Counter" : "Edit Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let base = existing ?? SecondaryCounter(title: "", resetAfter: resetAfter)
                        var updated = base
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.resetAfter = max(1, resetAfter)
                        updated.maxResets = hasMaxResets ? maxResets : nil
                        updated.linkMode = linkMode
                        updated.isLinkedToGlobal = linkMode != .unlinked
                        updated.color = color
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let existing else { return }
                title = existing.title
                resetAfter = existing.resetAfter
                hasMaxResets = existing.maxResets != nil
                maxResets = existing.maxResets ?? maxResets
                linkMode = existing.linkMode
                color = existing.color
            }
        }
    }

    private func themeColor(_ name: String) -> Color {
        switch name {
        case "sageGreen": return Theme.sageGreen
        case "dustyBlue": return Theme.dustyBlue
        case "honey": return Theme.honey
        case "deepPlum": return Theme.deepPlum
        default: return Theme.softCoral
        }
    }

    private func selectedRingColor(for colorName: String) -> Color {
        switch colorName {
        case "deepPlum", "softCoral":
            return .white
        default:
            return Theme.Semantic.textPrimary
        }
    }
}
