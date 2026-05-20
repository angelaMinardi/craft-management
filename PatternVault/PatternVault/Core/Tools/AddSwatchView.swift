//
//  AddSwatchView.swift
//  PatternVault
//
//  Add or edit a swatch: photo, yarn, needle/hook, gauge, notes.
//

import SwiftUI
import PhotosUI

struct AddSwatchView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var swatchStore: SwatchStore
    @Environment(\.dismiss) private var dismiss

    var existingItem: Swatch?

    @StateObject private var yarnStashStore = YarnStashStore()
    @StateObject private var needleHookStore = NeedleHookStore()

    @State private var title = ""
    @State private var craft = "Knit"
    @State private var stitchPattern = ""

    @State private var linkedYarn: YarnStashItem?
    @State private var yarnName = ""

    @State private var linkedNeedle: NeedleHookItem?
    @State private var needleSize = ""

    @State private var stitchesPer4in = ""
    @State private var rowsPer4in = ""

    @State private var blocked = false
    @State private var washed = false
    @State private var notes = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: Image?
    @State private var existingPhotoUrl: String?

    @State private var isSaving = false

    private var isEditing: Bool { existingItem != nil }

    private let craftOptions = ["Knit", "Crochet", "Other"]

    private var canSave: Bool {
        // At minimum, need either a photo or some text — otherwise there's nothing to save.
        let hasAnyText = !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !yarnName.trimmingCharacters(in: .whitespaces).isEmpty
            || !needleSize.trimmingCharacters(in: .whitespaces).isEmpty
            || !stitchPattern.trimmingCharacters(in: .whitespaces).isEmpty
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto = photoData != nil || existingPhotoUrl != nil
        return (hasAnyText || hasPhoto) && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                basicsSection
                yarnSection
                needleSection
                gaugeSection
                finishingSection

                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let error = swatchStore.errorMessage {
                    Section {
                        VStack(spacing: Theme.Spacing.sm) {
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
            .navigationTitle(isEditing ? "Edit swatch" : "Add swatch")
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
            .onAppear { hydrateFromExisting() }
            .task {
                guard let userId = auth.currentUserId else { return }
                if yarnStashStore.items.isEmpty { await yarnStashStore.load(userId: userId) }
                if needleHookStore.items.isEmpty { await needleHookStore.load(userId: userId) }
            }
        }
    }

    private var photoSection: some View {
        Section("Photo") {
            if let photoPreview {
                photoPreview
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .cornerRadius(Theme.CornerRadius.medium)
                Button("Remove photo", role: .destructive) {
                    selectedPhoto = nil
                    photoData = nil
                    self.photoPreview = nil
                    existingPhotoUrl = nil
                }
            } else if let urlString = existingPhotoUrl, let u = URL(string: urlString) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxHeight: 220).cornerRadius(Theme.CornerRadius.medium)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.Semantic.textMuted)
                    @unknown default: EmptyView()
                    }
                }
                Button("Remove photo", role: .destructive) {
                    existingPhotoUrl = nil
                }
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(
                    photoPreview == nil && existingPhotoUrl == nil ? "Add photo" : "Change photo",
                    systemImage: "photo.badge.plus"
                )
            }
        }
    }

    private var basicsSection: some View {
        Section("Basics") {
            TextField("Title", text: $title, prompt: Text("e.g. Stockinette in Malabrigo Rios"))
                .textInputAutocapitalization(.sentences)
            Picker("Craft", selection: $craft) {
                ForEach(craftOptions, id: \.self) { Text($0).tag($0) }
            }
            TextField("Stitch pattern", text: $stitchPattern, prompt: Text("e.g. Stockinette, 1×1 rib"))
                .textInputAutocapitalization(.sentences)
        }
    }

    private var yarnSection: some View {
        Section("Yarn") {
            if !yarnStashStore.items.isEmpty {
                Picker("From stash", selection: $linkedYarn) {
                    Text("None").tag(nil as YarnStashItem?)
                    ForEach(yarnStashStore.items) { item in
                        Text(item.displaySummary).tag(item as YarnStashItem?)
                    }
                }
                .onChange(of: linkedYarn) { _, newValue in
                    if let y = newValue { yarnName = y.displaySummary }
                }
            }
            TextField("Yarn description", text: $yarnName, prompt: Text("e.g. Cascade 220 · Heather"))
                .textInputAutocapitalization(.sentences)
        }
    }

    private var needleSection: some View {
        Section("Needles / hook") {
            if !needleHookStore.items.isEmpty {
                Picker("From tools", selection: $linkedNeedle) {
                    Text("None").tag(nil as NeedleHookItem?)
                    ForEach(needleHookStore.items) { item in
                        Text(item.displaySummary).tag(item as NeedleHookItem?)
                    }
                }
                .onChange(of: linkedNeedle) { _, newValue in
                    if let n = newValue { needleSize = n.displaySummary }
                }
            }
            TextField("Size", text: $needleSize, prompt: Text("e.g. US 7 · 4.5mm"))
                .textInputAutocapitalization(.never)
        }
    }

    private var gaugeSection: some View {
        Section("Gauge (per 4\")") {
            TextField("Stitches per 4\"", text: $stitchesPer4in, prompt: Text("e.g. 20"))
                .keyboardType(.decimalPad)
            TextField("Rows per 4\"", text: $rowsPer4in, prompt: Text("e.g. 28"))
                .keyboardType(.decimalPad)
        }
    }

    private var finishingSection: some View {
        Section("Finishing") {
            Toggle("Blocked", isOn: $blocked)
            Toggle("Washed", isOn: $washed)
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoData = data
                if let uiImage = UIImage(data: data) {
                    photoPreview = Image(uiImage: uiImage)
                    // Clear the existing remote photo indicator — the new pick will replace it on save.
                    existingPhotoUrl = nil
                }
            }
        }
    }

    private func hydrateFromExisting() {
        guard let item = existingItem else { return }
        title = item.title ?? ""
        craft = (item.craft?.isEmpty == false ? item.craft! : "Knit")
        if !craftOptions.contains(craft) {
            // Normalize capitalization; fall back to "Other" if unknown.
            let normalized = craft.prefix(1).uppercased() + craft.dropFirst().lowercased()
            craft = craftOptions.contains(normalized) ? normalized : "Other"
        }
        stitchPattern = item.stitchPattern ?? ""
        yarnName = item.yarnName ?? ""
        needleSize = item.needleSize ?? ""
        stitchesPer4in = item.stitchesPer4in.map { $0 == $0.rounded() ? "\(Int($0))" : "\($0)" } ?? ""
        rowsPer4in = item.rowsPer4in.map { $0 == $0.rounded() ? "\(Int($0))" : "\($0)" } ?? ""
        blocked = item.blocked
        washed = item.washed
        notes = item.notes ?? ""
        existingPhotoUrl = item.photoUrl
    }

    private func save() {
        guard let userId = auth.currentUserId else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedStitchPattern = stitchPattern.trimmingCharacters(in: .whitespaces)
        let trimmedYarn = yarnName.trimmingCharacters(in: .whitespaces)
        let trimmedNeedle = needleSize.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let sts = Double(stitchesPer4in.trimmingCharacters(in: .whitespaces))
        let rows = Double(rowsPer4in.trimmingCharacters(in: .whitespaces))

        // If user typed yarn text manually and it no longer matches the linked stash item,
        // clear the stash link so we don't falsely claim a relationship.
        let yarnStashId = (linkedYarn?.displaySummary == trimmedYarn) ? linkedYarn?.id : nil
        let needleHookId = (linkedNeedle?.displaySummary == trimmedNeedle) ? linkedNeedle?.id : nil

        isSaving = true

        Task {
            let ok: Bool
            if let existing = existingItem {
                var updated = existing
                updated.title = trimmedTitle.isEmpty ? nil : trimmedTitle
                updated.craft = craft
                updated.stitchPattern = trimmedStitchPattern.isEmpty ? nil : trimmedStitchPattern
                updated.yarnName = trimmedYarn.isEmpty ? nil : trimmedYarn
                updated.yarnStashId = yarnStashId
                updated.needleSize = trimmedNeedle.isEmpty ? nil : trimmedNeedle
                updated.needleHookId = needleHookId
                updated.stitchesPer4in = sts
                updated.rowsPer4in = rows
                updated.blocked = blocked
                updated.washed = washed
                updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
                // If user removed the existing photo and didn't pick a new one, clear the URL.
                if existingPhotoUrl == nil && photoData == nil {
                    updated.photoUrl = nil
                }
                ok = await swatchStore.update(updated, newPhotoData: photoData)
            } else {
                ok = await swatchStore.add(
                    userId: userId,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    craft: craft,
                    needleSize: trimmedNeedle.isEmpty ? nil : trimmedNeedle,
                    needleHookId: needleHookId,
                    yarnName: trimmedYarn.isEmpty ? nil : trimmedYarn,
                    yarnStashId: yarnStashId,
                    stitchesPer4in: sts,
                    rowsPer4in: rows,
                    stitchPattern: trimmedStitchPattern.isEmpty ? nil : trimmedStitchPattern,
                    blocked: blocked,
                    washed: washed,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    photoData: photoData
                )
            }
            isSaving = false
            if ok {
                HapticService.success()
                dismiss()
            }
        }
    }
}
