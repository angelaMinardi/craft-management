//
//  PatternDetailView.swift
//  PatternVault
//

import SwiftUI
import WebKit

struct PatternDetailView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    let pattern: Pattern

    @StateObject private var noteStore = ProjectNoteStore()
    @StateObject private var tagStore = TagStore()
    @StateObject private var imageStore = PatternImageStore()
    @StateObject private var yarnLinkStore = PatternYarnLinkStore()
    @State private var isEditingTitle = false
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var showDeleteConfirm = false
    @State private var showAddNote = false
    @State private var showTagPicker = false
    @State private var showWebView = false
    @State private var showPdfViewer = false
    @Environment(\.dismiss) private var dismiss

    private var current: Pattern {
        store.patterns.first(where: { $0.id == pattern.id }) ?? pattern
    }

    var body: some View {
        List {
            if let thumbnailUrl = current.thumbnailUrl, let imageURL = URL(string: thumbnailUrl) {
                Section {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 200)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            EmptyView()
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }
            }

            Section("Details") {
                if isEditingTitle {
                    TextField("Title", text: $editTitle)
                    TextField("Description", text: $editDescription, axis: .vertical)
                        .lineLimit(2...6)
                    HStack {
                        Button("Save") { saveEdit() }
                        Spacer()
                        Button("Cancel") { isEditingTitle = false }
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(current.title)
                            .font(.headline)
                        if let desc = current.patternDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onTapGesture {
                        editTitle = current.title
                        editDescription = current.patternDescription ?? ""
                        isEditingTitle = true
                    }
                }
            }

            // MARK: - Pattern Info
            Section("Pattern Info") {
                HStack {
                    Image(systemName: "scissors")
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .frame(width: 24)
                    Text("Craft Type")
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    Spacer()
                    if let craftType = current.craftType, !craftType.isEmpty {
                        Text(craftType.capitalized)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.deepPlum)
                    } else {
                        Text("Unknown")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    }
                }
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .frame(width: 24)
                    Text("Difficulty")
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    Spacer()
                    if let difficulty = current.difficulty, !difficulty.isEmpty {
                        Text(difficulty.capitalized)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.statusColor(for: difficultyStatus(difficulty)))
                    } else {
                        Text("Not set")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Image(systemName: "basket")
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .frame(width: 24)
                        Text("Materials")
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    if let materials = current.materials, !materials.isEmpty {
                        Text(materials)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                    } else {
                        Text("No materials info available")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                            .italic()
                    }
                }
                if let gauge = current.gauge, !gauge.isEmpty {
                    infoRow(icon: "ruler", label: "Gauge", value: gauge)
                }
                if let needleHook = current.needleHookSizes, !needleHook.isEmpty {
                    infoRow(icon: "hammer", label: "Needles / Hook", value: needleHook)
                }
                if let yarnYardage = current.yarnWeightYardage, !yarnYardage.isEmpty {
                    infoRow(icon: "spool", label: "Yarn weight & yardage", value: yarnYardage)
                }
                if let techniques = current.techniques, !techniques.isEmpty {
                    infoRow(icon: "list.bullet", label: "Techniques", value: techniques)
                }
                if let videoUrl = current.videoUrl, !videoUrl.isEmpty, let url = URL(string: videoUrl) {
                    HStack {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .frame(width: 24)
                        Link("Watch tutorial video", destination: url)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.softCoral)
                    }
                }
            }

            // MARK: - Yarn & supplies
            if !yarnLinkStore.links.isEmpty {
                Section("Yarn & supplies") {
                    ForEach(yarnLinkStore.links) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.brandName)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.deepPlum)
                            HStack(spacing: Theme.Spacing.sm) {
                                if let official = link.officialUrl, !official.isEmpty, let url = URL(string: official) {
                                    Link("Official site", destination: url)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.softCoral)
                                }
                                if let store = link.storeUrl, !store.isEmpty, let url = URL(string: store) {
                                    Link("Where to buy", destination: url)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.softCoral)
                                }
                            }
                        }
                    }
                }
            }

            // MARK: - Pattern Images
            if !imageStore.images.isEmpty {
                Section("Photos (\(imageStore.images.count))") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(imageStore.images) { img in
                                AsyncImage(url: URL(string: img.imageUrl)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 140, height: 140)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                                    case .failure:
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                            .fill(Theme.warmCream)
                                            .frame(width: 140, height: 140)
                                            .overlay {
                                                Image(systemName: "photo")
                                                    .foregroundStyle(Theme.deepPlum.opacity(0.3))
                                            }
                                    default:
                                        ProgressView()
                                            .frame(width: 140, height: 140)
                                    }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }

            // MARK: - Source
            Section("Source") {
                if let pdfUrlString = current.pdfUrl, !pdfUrlString.isEmpty, let pdfURL = URL(string: pdfUrlString) {
                    Button {
                        showPdfViewer = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Theme.softCoral)
                                .frame(width: 24)
                            Text("View PDF")
                                .foregroundStyle(Theme.deepPlum)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        }
                    }
                }

                if current.sourceContent != nil {
                    NavigationLink {
                        PatternContentView(pattern: current)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Theme.softCoral)
                                .frame(width: 24)
                            Text("View Pattern Content")
                                .foregroundStyle(Theme.deepPlum)
                            Spacer()
                        }
                    }
                }

                Button {
                    showWebView = true
                } label: {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.softCoral)
                            .frame(width: 24)
                        Text("Open in Browser")
                            .foregroundStyle(Theme.deepPlum)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    }
                }

                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        .frame(width: 24)
                    Text(current.sourcePlatform ?? domainFromURL(current.sourceUrl) ?? "Web")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                }
            }

            Section("Status") {
                ForEach(PatternStatus.allCases, id: \.self) { s in
                    Button {
                        changeStatus(to: s)
                    } label: {
                        HStack {
                            Text(s.displayName)
                            Spacer()
                            if current.status == s {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            // MARK: - Tags
            Section {
                if tagStore.patternTags.isEmpty {
                    Button {
                        showTagPicker = true
                    } label: {
                        Label("Add Tags", systemImage: "tag")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(tagStore.patternTags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.chipFill)
                                .clipShape(Capsule())
                        }
                    }
                    .onTapGesture {
                        showTagPicker = true
                    }
                }
            } header: {
                HStack {
                    Text("Tags")
                    Spacer()
                    Button {
                        showTagPicker = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                }
            }

            // MARK: - Notes
            Section {
                if noteStore.isLoading {
                    ProgressView("Loading notes...")
                } else if noteStore.notes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No notes yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(noteStore.notes) { note in
                        NavigationLink {
                            NoteDetailView(
                                noteStore: noteStore,
                                note: note,
                                patternId: current.id
                            )
                        } label: {
                            NoteRowView(note: note)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Notes (\(noteStore.notes.count))")
                    Spacer()
                    Button {
                        showAddNote = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                }
            }

            if let error = noteStore.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(Theme.softCoral)
                        .font(.caption)
                }
            }

            Section {
                Button("Delete Pattern", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.warmCream)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete Pattern", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deletePattern() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will also delete all notes. This cannot be undone.")
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView(
                noteStore: noteStore,
                patternId: current.id
            )
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerView(
                tagStore: tagStore,
                patternId: current.id
            )
        }
        .sheet(isPresented: $showWebView) {
            NavigationStack {
                InAppWebView(url: URL(string: current.sourceUrl)!)
                    .navigationTitle("Pattern Page")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showWebView = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            if let url = URL(string: current.sourceUrl) {
                                Link(destination: url) {
                                    Image(systemName: "safari")
                                }
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPdfViewer) {
            if let pdfUrlString = current.pdfUrl, let pdfURL = URL(string: pdfUrlString) {
                NavigationStack {
                    PDFViewerView(url: pdfURL)
                        .navigationTitle("Pattern PDF")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showPdfViewer = false }
                            }
                        }
                }
            }
        }
        .task {
            async let notes: () = noteStore.load(patternId: current.id)
            async let allTags: () = tagStore.loadAllTags()
            async let patternTags: () = tagStore.loadPatternTags(patternId: current.id)
            async let images: () = imageStore.load(patternId: current.id)
            async let yarnLinks: () = yarnLinkStore.load(patternId: current.id)
            _ = await (notes, allTags, patternTags, images, yarnLinks)
        }
        .refreshable {
            await noteStore.load(patternId: current.id)
            await tagStore.loadPatternTags(patternId: current.id)
            await imageStore.load(patternId: current.id)
            await yarnLinkStore.load(patternId: current.id)
        }
    }

    private func changeStatus(to status: PatternStatus) {
        guard let userId = auth.currentUserId else { return }
        Task {
            await store.updateStatus(pattern: current, userId: userId, status: status)
        }
    }

    private func saveEdit() {
        guard let userId = auth.currentUserId else { return }
        isEditingTitle = false
        Task {
            await store.update(
                pattern: current, userId: userId,
                title: editTitle,
                description: editDescription.isEmpty ? nil : editDescription
            )
        }
    }

    private func deletePattern() {
        guard let userId = auth.currentUserId else { return }
        Task {
            await store.delete(pattern: current, userId: userId)
            dismiss()
        }
    }

    private func domainFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .frame(width: 24)
                Text(label)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
        }
    }

    private func difficultyStatus(_ difficulty: String) -> PatternStatus {
        switch difficulty.lowercased() {
        case "beginner", "easy": return .wantToMake
        case "intermediate": return .inProgress
        default: return .completed // advanced/expert
        }
    }
}
