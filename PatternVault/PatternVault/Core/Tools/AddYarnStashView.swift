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
    @State private var barcode = ""
    @State private var dyeLot = ""
    @State private var fiberContent = ""
    @State private var isSaving = false
    @State private var showScanner = false
    @State private var showLabelCamera = false
    @State private var lookupStatus: LookupStatus = .idle
    @State private var labelStatus: LabelScanStatus = .idle

    enum LookupStatus: Equatable {
        case idle
        case searching
        case filled(String)
        case noMatch
    }

    enum LabelScanStatus: Equatable {
        case idle
        case scanning
        case success(String)
        case problem(String)
    }

    private var isEditing: Bool { existingItem != nil }
    private var canSave: Bool {
        !brandName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    HStack {
                        TextField("Brand or name", text: $brandName)
                            .textInputAutocapitalization(.words)
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.sageGreen)
                        }
                        .buttonStyle(.plain)
                        Button {
                            showLabelCamera = true
                        } label: {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.sageGreen)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan label with camera")
                    }
                    lookupStatusView
                    labelStatusView
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
                    TextField("Dye lot", text: $dyeLot)
                    TextField("Fiber content (e.g. 80% wool, 20% nylon)", text: $fiberContent)
                    TextField("Location (e.g. closet, bin)", text: $location)
                    if !barcode.isEmpty {
                        HStack {
                            Image(systemName: "barcode")
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                            Text(barcode)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        }
                    }
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
            .onAppear {
                if let item = existingItem {
                    brandName = item.brandName
                    colorName = item.colorName ?? ""
                    weight = item.weight ?? ""
                    yardagePerSkein = item.yardagePerSkein.map { "\($0)" } ?? ""
                    skeinsOwned = item.skeinsOwned == 0 ? "" : "\(item.skeinsOwned)"
                    location = item.location ?? ""
                    notes = item.notes ?? ""
                    barcode = item.barcode ?? ""
                    dyeLot = item.dyeLot ?? ""
                    fiberContent = item.fiberContent ?? ""
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    barcode = code
                    showScanner = false
                    lookUpBarcode(code)
                }
            }
            .sheet(isPresented: $showLabelCamera) {
                LabelCameraView { imageData in
                    showLabelCamera = false
                    analyzeLabel(imageData)
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var lookupStatusView: some View {
        switch lookupStatus {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                Text("Looking up product…")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
        case .filled(let name):
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.sageGreen)
                Text("Found: \(name)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
            }
        case .noMatch:
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                Text("Barcode saved, but no product match was found. Add the details below manually.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var labelStatusView: some View {
        switch labelStatus {
        case .idle:
            EmptyView()
        case .scanning:
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                Text("Reading label…")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
        case .success(let summary):
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.sageGreen)
                Text(summary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
            }
        case .problem(let message):
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.softCoral)
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
        }
    }

    /// Send the photographed label to Gemini, then fill in any fields the user
    /// hasn't already entered. Never overwrites existing input.
    private func analyzeLabel(_ imageData: Data) {
        labelStatus = .scanning
        Task {
            do {
                let info = try await YarnLabelAnalyzer.analyze(imageData: imageData)
                guard !info.isEmpty else {
                    labelStatus = .problem("Couldn't read details off the label. Try a clearer, straight-on photo.")
                    return
                }

                var filled: [String] = []
                func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }

                if isBlank(brandName), let b = info.displayBrand { brandName = b; filled.append("brand") }
                if isBlank(colorName), let c = info.colorName, !c.isEmpty { colorName = c; filled.append("color") }
                if isBlank(weight), let w = info.weight, !w.isEmpty { weight = w; filled.append("weight") }
                if isBlank(fiberContent), let f = info.fiberContent, !f.isEmpty { fiberContent = f; filled.append("fiber") }
                if isBlank(yardagePerSkein), let y = info.yardagePerSkein { yardagePerSkein = "\(y)"; filled.append("yardage") }
                if isBlank(dyeLot), let d = info.dyeLot, !d.isEmpty { dyeLot = d; filled.append("dye lot") }

                if filled.isEmpty {
                    labelStatus = .success("Label read — the matching fields were already filled in.")
                } else {
                    labelStatus = .success("Filled from label: \(filled.joined(separator: ", ")).")
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't read the label. Please try again."
                labelStatus = .problem(message)
            }
        }
    }

    /// Look the scanned barcode up against the product database and fill in any
    /// fields the user hasn't already entered. Best-effort — on miss/failure we
    /// keep the raw barcode so it still saves with the item.
    private func lookUpBarcode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        lookupStatus = .searching
        Task {
            let info = await BarcodeLookupService.lookup(barcode: trimmed)
            guard let info else {
                lookupStatus = .noMatch
                return
            }

            // Fill empty fields only — never overwrite what the user typed.
            let matchedBrand = info.brand ?? info.title
            if brandName.trimmingCharacters(in: .whitespaces).isEmpty,
               let matchedBrand, !matchedBrand.isEmpty {
                brandName = matchedBrand
            }
            // Keep the full product title in notes so nothing is lost when the
            // title is more specific than the brand alone (e.g. colorway).
            if let title = info.title, !title.isEmpty,
               title != brandName,
               notes.trimmingCharacters(in: .whitespaces).isEmpty {
                notes = title
            }

            lookupStatus = .filled(info.title ?? info.brand ?? trimmed)
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
                updated.barcode = barcode.isEmpty ? nil : barcode.trimmingCharacters(in: .whitespaces)
                updated.dyeLot = dyeLot.isEmpty ? nil : dyeLot.trimmingCharacters(in: .whitespaces)
                updated.fiberContent = fiberContent.isEmpty ? nil : fiberContent.trimmingCharacters(in: .whitespaces)
                await stashStore.update(updated)
            } else {
                await stashStore.add(userId: userId, brandName: brand, colorName: colorName.isEmpty ? nil : colorName.trimmingCharacters(in: .whitespaces), weight: weight.isEmpty ? nil : weight.trimmingCharacters(in: .whitespaces), yardagePerSkein: ypp, skeinsOwned: max(0, skeins), location: location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces), notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces), barcode: barcode.isEmpty ? nil : barcode.trimmingCharacters(in: .whitespaces), dyeLot: dyeLot.isEmpty ? nil : dyeLot.trimmingCharacters(in: .whitespaces), fiberContent: fiberContent.isEmpty ? nil : fiberContent.trimmingCharacters(in: .whitespaces))
                if stashStore.errorMessage == nil, stashStore.items.count == 1 {
                    CelebrationStore.shared.unlock("stash_started")
                }
            }
            isSaving = false
            if stashStore.errorMessage == nil { dismiss() }
        }
    }
}
