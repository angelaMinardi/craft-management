//
//  AddPatternView.swift
//  PatternVault
//

import SwiftUI
import UniformTypeIdentifiers

struct AddPatternView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @Environment(\.dismiss) private var dismiss

    var prefillURL: String?

    @State private var url = ""
    @State private var title = ""
    @State private var description = ""
    @State private var status: PatternStatus = .wantToMake
    @State private var isSaving = false
    @State private var isFetchingMetadata = false
    @State private var thumbnailUrl: String?
    @State private var attachedPdfData: Data?
    @State private var showPdfPicker = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var duplicateExisting: Pattern?
    @FocusState private var focusedField: Field?

    enum Field { case url, title, description }

    var body: some View {
        NavigationStack {
            Form {
                if store.errorMessage == nil {
                    Section {
                        SpriteMascotView.knitting(size: 72)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: Theme.Spacing.md, leading: 0, bottom: Theme.Spacing.sm, trailing: 0))
                    } header: {
                        EmptyView()
                    }
                }

                Section("Link") {
                    HStack {
                        TextField("Paste pattern URL", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .url)
                            .accessibilityLabel("Pattern URL")
                            .accessibilityHint("Paste the link to the pattern")
                            .onChange(of: url) { _, newValue in
                                scheduleFetch(for: newValue)
                            }
                        if isFetchingMetadata {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if let thumbnailUrl, let imageURL = URL(string: thumbnailUrl) {
                    Section {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 160)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                EmptyView()
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 80)
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Title (e.g. Cozy Cardigan)", text: $title)
                        .focused($focusedField, equals: .title)
                        .accessibilityLabel("Title")
                        .accessibilityHint("Pattern name")
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .description)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(PatternStatus.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("PDF (optional)") {
                    if attachedPdfData != nil {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Theme.softCoral)
                            Text("PDF attached")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            Spacer()
                            Button("Remove") {
                                attachedPdfData = nil
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.softCoral)
                        }
                    } else {
                        Button {
                            showPdfPicker = true
                        } label: {
                            Label("Attach PDF", systemImage: "doc.badge.plus")
                                .foregroundStyle(Theme.deepPlum)
                        }
                    }
                }

                if let error = store.errorMessage {
                    Section {
                        VStack(spacing: Theme.Spacing.sm) {
                            SpriteMascotView.pouty(size: 72)
                            Text(error)
                                .foregroundStyle(Theme.softCoral)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Add Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityHint("Close without saving")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(url.isEmpty || title.isEmpty || isSaving)
                        .accessibilityLabel("Save")
                        .accessibilityHint("Save the pattern to your vault")
                }
            }
            .onAppear {
                if let prefillURL, !prefillURL.isEmpty {
                    url = prefillURL
                }
            }
            .alert("You may already have this pattern", isPresented: Binding(get: { duplicateExisting != nil }, set: { if !$0 { duplicateExisting = nil } })) {
                Button("Cancel", role: .cancel) { duplicateExisting = nil }
                Button("Save anyway") { save(forceAdd: true) }
            } message: {
                if let existing = duplicateExisting {
                    Text("A pattern with this link is already in your vault: \"\(existing.title)\". Save anyway to add a duplicate?")
                }
            }
            .fileImporter(
                isPresented: $showPdfPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let first = urls.first else { return }
                guard first.startAccessingSecurityScopedResource() else { return }
                defer { first.stopAccessingSecurityScopedResource() }
                attachedPdfData = try? Data(contentsOf: first)
            }
        }
    }

    private func scheduleFetch(for urlString: String) {
        fetchTask?.cancel()
        guard !urlString.isEmpty, URL(string: urlString) != nil else { return }

        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await fetchMetadata(for: urlString)
        }
    }

    private func fetchMetadata(for urlString: String) async {
        isFetchingMetadata = true
        defer { isFetchingMetadata = false }

        // Detect platform for title fallback
        let platform = SourcePlatformHelper.platform(for: urlString)

        guard let metadata = await MetadataService.fetch(urlString: urlString) else {
            // Fallback: set platform-based title if still empty
            if title.isEmpty, let platform {
                title = "\(platform) Pattern"
            }
            return
        }

        if title.isEmpty, let fetchedTitle = metadata.title, !fetchedTitle.isEmpty {
            title = fetchedTitle
        } else if title.isEmpty, let platform {
            title = "\(platform) Pattern"
        }

        if description.isEmpty, let fetchedDesc = metadata.description, !fetchedDesc.isEmpty {
            description = fetchedDesc
        }

        if thumbnailUrl == nil, let fetchedImage = metadata.imageUrl {
            thumbnailUrl = fetchedImage
        }
    }

    private func save(forceAdd: Bool = false) {
        guard let userId = auth.currentUserId else { return }
        if !forceAdd, let existing = PatternDuplicateHelper.existingMatch(for: url, in: store.patterns) {
            duplicateExisting = existing
            return
        }
        duplicateExisting = nil
        isSaving = true
        Task {
            let desc = description.isEmpty ? nil : description
            let success = await store.add(
                userId: userId,
                title: title,
                description: desc,
                sourceUrl: url,
                status: status,
                thumbnailUrl: thumbnailUrl
            )
            if success, let pdfData = attachedPdfData, let newPattern = store.patterns.first {
                await store.attachPdf(pattern: newPattern, userId: userId, pdfData: pdfData)
            }
            isSaving = false
            if success {
                HapticService.success()
                if store.patterns.count == 1 { CelebrationStore.shared.unlock("first_pattern") }
                if store.patterns.count == 10 { CelebrationStore.shared.unlock("vault_10") }
                dismiss()
            }
        }
    }
}
