//
//  ShareViewController.swift
//  SaveToPatternVault
//
//  Rich share extension UI for capturing craft patterns with AI-powered metadata.
//

import UIKit
import UniformTypeIdentifiers

// MARK: - Brand Colors (duplicated from Theme.swift since extension can't access main app assets)
private extension UIColor {
    static let brandWarmCream = UIColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0)
    static let brandSoftCoral = UIColor(red: 0.910, green: 0.514, blue: 0.420, alpha: 1.0)
    static let brandDeepPlum = UIColor(red: 0.290, green: 0.125, blue: 0.251, alpha: 1.0)
    static let brandSageGreen = UIColor(red: 0.659, green: 0.773, blue: 0.627, alpha: 1.0)
}

class ShareViewController: UIViewController {

    // MARK: - State

    private var sharedURL: String?
    private var sharedPdfData: Data?
    private var extractedContent: ExtractedContent?
    private var aiResult: AIPatternResult?
    private var videoExtractionResult: VideoExtractionResult?
    private var thumbnailImage: UIImage?
    private var currentTags: [String] = []
    private var isSaving = false

    // MARK: - UI Elements

    private let containerView = UIView()
    private let navBar = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let loadingOverlay = UIView()
    private let loadingSpinner = UIActivityIndicatorView(style: .large)
    private let loadingLabel = UILabel()

    private let imageView = UIImageView()
    private let titleField = UITextField()
    private let descriptionView = UITextView()
    private let tagsContainer = UIView()
    private let tagsStack = UIStackView()
    private let addTagButton = UIButton(type: .system)
    private let urlLabel = UILabel()
    private let statusControl = UISegmentedControl(items: ["Want to Make", "In Progress", "Completed"])
    private let materialsLabel = UILabel()
    private let difficultyLabel = UILabel()

    private let cancelButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractSharedURL()
    }

    // MARK: - Setup

    private func setupUI() {
        // Container card
        containerView.backgroundColor = .brandWarmCream
        containerView.layer.cornerRadius = 16
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        setupNavBar()
        setupScrollContent()
        setupLoadingOverlay()
    }

    private func setupNavBar() {
        navBar.backgroundColor = .brandWarmCream
        navBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(navBar)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(separator)

        // Cancel button (X)
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .brandDeepPlum
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(cancelButton)

        // Save button (checkmark)
        saveButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        saveButton.tintColor = .brandSoftCoral
        saveButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(saveButton)

        // Title
        titleLabel.text = "Save to Pattern Vault"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .brandDeepPlum
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 52),

            cancelButton.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: navBar.trailingAnchor, constant: -16),
            saveButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            separator.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func setupScrollContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        containerView.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])

        // Image preview
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = .brandWarmCream
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        contentStack.addArrangedSubview(imageView)

        // Title field
        let titleContainer = createFieldContainer(label: "Title")
        titleField.placeholder = "Pattern title..."
        titleField.font = .systemFont(ofSize: 16)
        titleField.borderStyle = .none
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addArrangedSubview(titleField)
        contentStack.addArrangedSubview(titleContainer)

        // Description
        let descContainer = createFieldContainer(label: "Description")
        descriptionView.font = .systemFont(ofSize: 15)
        descriptionView.textColor = .label
        descriptionView.backgroundColor = .clear
        descriptionView.isScrollEnabled = false
        descriptionView.textContainerInset = .zero
        descriptionView.textContainer.lineFragmentPadding = 0
        descriptionView.translatesAutoresizingMaskIntoConstraints = false
        descriptionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        descContainer.addArrangedSubview(descriptionView)
        contentStack.addArrangedSubview(descContainer)

        // Tags
        let tagsHeader = createSectionLabel("Tags")
        contentStack.addArrangedSubview(tagsHeader)

        tagsStack.axis = .horizontal
        tagsStack.spacing = 8
        tagsStack.alignment = .center
        tagsStack.distribution = .fill

        let tagsScrollView = UIScrollView()
        tagsScrollView.showsHorizontalScrollIndicator = false
        tagsScrollView.translatesAutoresizingMaskIntoConstraints = false
        tagsStack.translatesAutoresizingMaskIntoConstraints = false
        tagsScrollView.addSubview(tagsStack)
        NSLayoutConstraint.activate([
            tagsStack.topAnchor.constraint(equalTo: tagsScrollView.topAnchor),
            tagsStack.leadingAnchor.constraint(equalTo: tagsScrollView.leadingAnchor),
            tagsStack.trailingAnchor.constraint(equalTo: tagsScrollView.trailingAnchor),
            tagsStack.bottomAnchor.constraint(equalTo: tagsScrollView.bottomAnchor),
            tagsStack.heightAnchor.constraint(equalTo: tagsScrollView.heightAnchor),
            tagsScrollView.heightAnchor.constraint(equalToConstant: 36),
        ])
        contentStack.addArrangedSubview(tagsScrollView)

        // Extra info (difficulty, materials)
        difficultyLabel.font = .systemFont(ofSize: 14)
        difficultyLabel.textColor = .brandDeepPlum.withAlphaComponent(0.6)
        difficultyLabel.isHidden = true
        contentStack.addArrangedSubview(difficultyLabel)

        materialsLabel.font = .systemFont(ofSize: 14)
        materialsLabel.textColor = .brandDeepPlum.withAlphaComponent(0.6)
        materialsLabel.numberOfLines = 0
        materialsLabel.isHidden = true
        contentStack.addArrangedSubview(materialsLabel)

        // URL
        let urlHeader = createSectionLabel("Source")
        contentStack.addArrangedSubview(urlHeader)
        urlLabel.font = .systemFont(ofSize: 13)
        urlLabel.textColor = .brandDeepPlum.withAlphaComponent(0.6)
        urlLabel.numberOfLines = 2
        urlLabel.lineBreakMode = .byTruncatingMiddle
        contentStack.addArrangedSubview(urlLabel)

        // Status
        let statusHeader = createSectionLabel("Status")
        contentStack.addArrangedSubview(statusHeader)
        statusControl.selectedSegmentIndex = 0
        contentStack.addArrangedSubview(statusControl)
    }

    private func setupLoadingOverlay() {
        loadingOverlay.backgroundColor = UIColor.brandWarmCream.withAlphaComponent(0.9)
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(loadingOverlay)

        let loadingStack = UIStackView(arrangedSubviews: [loadingSpinner, loadingLabel])
        loadingStack.axis = .vertical
        loadingStack.spacing = 12
        loadingStack.alignment = .center
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(loadingStack)

        loadingSpinner.startAnimating()
        loadingSpinner.color = .brandSoftCoral
        loadingLabel.text = "Analyzing pattern..."
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textColor = .brandDeepPlum.withAlphaComponent(0.6)

        // Pulse animation on the loading label
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        loadingLabel.layer.add(pulse, forKey: "pulse")

        NSLayoutConstraint.activate([
            loadingOverlay.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            loadingStack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
        ])
    }

    // MARK: - Helpers

    private func createFieldContainer(label: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        let lbl = createSectionLabel(label)
        stack.addArrangedSubview(lbl)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(divider)

        return stack
    }

    private func createSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .brandDeepPlum.withAlphaComponent(0.6)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func createTagChip(_ text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .brandSoftCoral.withAlphaComponent(0.12)
        container.layer.cornerRadius = 14

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .brandSoftCoral
        label.translatesAutoresizingMaskIntoConstraints = false

        let removeBtn = UIButton(type: .system)
        removeBtn.setImage(UIImage(systemName: "xmark.circle.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12)), for: .normal)
        removeBtn.tintColor = .brandSoftCoral.withAlphaComponent(0.6)
        removeBtn.tag = currentTags.firstIndex(of: text) ?? 0
        removeBtn.addTarget(self, action: #selector(removeTag(_:)), for: .touchUpInside)
        removeBtn.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(removeBtn)
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            removeBtn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            removeBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            removeBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 28),
        ])

        return container
    }

    private func refreshTagChips() {
        tagsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, tag) in currentTags.enumerated() {
            let chip = createTagChip(tag)
            chip.subviews.compactMap { $0 as? UIButton }.first?.tag = index
            tagsStack.addArrangedSubview(chip)
        }
        // Add "+" button
        let addBtn = UIButton(type: .system)
        addBtn.setImage(UIImage(systemName: "plus.circle.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        addBtn.tintColor = .brandSoftCoral
        addBtn.addTarget(self, action: #selector(addTagTapped), for: .touchUpInside)
        tagsStack.addArrangedSubview(addBtn)
    }

    // MARK: - Data Flow

    private func extractSharedURL() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No content to save")
            return
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] data, error in
                        DispatchQueue.main.async {
                            if let url = data as? URL {
                                self?.sharedPdfData = try? Data(contentsOf: url)
                                self?.sharedURL = url.absoluteString
                                self?.beginAnalysisForPdf()
                            } else if let pdfData = data as? Data {
                                self?.sharedPdfData = pdfData
                                self?.sharedURL = "file://pattern-vault/pdf"
                                self?.beginAnalysisForPdf()
                            } else {
                                self?.showError("Could not read PDF")
                            }
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] data, error in
                        DispatchQueue.main.async {
                            if let url = data as? URL {
                                self?.sharedURL = url.absoluteString
                                self?.beginAnalysis()
                            } else if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                                self?.sharedURL = url.absoluteString
                                self?.beginAnalysis()
                            } else {
                                self?.showError("Could not read URL")
                            }
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, error in
                        DispatchQueue.main.async {
                            if let text = data as? String, let url = self?.extractURL(from: text) {
                                self?.sharedURL = url
                                self?.beginAnalysis()
                            } else {
                                self?.showError("No URL found in shared text")
                            }
                        }
                    }
                    return
                }
            }
        }
        showError("Unsupported content type")
    }

    private func beginAnalysisForPdf() {
        urlLabel.text = "PDF pattern"
        titleField.text = titleField.text?.isEmpty == true ? "PDF Pattern" : titleField.text
        loadingOverlay.isHidden = true
    }

    private func beginAnalysis() {
        guard let urlString = sharedURL else { return }
        urlLabel.text = urlString
        loadingOverlay.isHidden = false

        Task {
            if isYouTubeURL(urlString) {
                loadingLabel.text = "Extracting from video..."
                if let videoResult = await SupabaseExtensionClient.extractPatternFromVideo(videoURL: urlString) {
                    self.videoExtractionResult = videoResult
                    self.aiResult = aiResultFromVideoExtraction(videoResult)
                    self.extractedContent = nil
                    await MainActor.run {
                        applyResultToUI()
                        loadingOverlay.isHidden = true
                    }
                    return
                }
            }

            if isTikTokURL(urlString) {
                loadingLabel.text = "Fetching TikTok..."
                if let tiktokContent = await TikTokContentExtractor.extract(from: urlString) {
                    self.extractedContent = tiktokContent
                    if let ogImage = tiktokContent.ogImageUrl {
                        await loadThumbnail(from: ogImage)
                    }
                    if let ogTitle = tiktokContent.ogTitle {
                        await MainActor.run { titleField.text = ogTitle }
                    }
                    loadingLabel.text = "Analyzing pattern..."
                    let result = await AIPatternAnalyzer.analyze(content: tiktokContent)
                    self.aiResult = result
                    await MainActor.run {
                        if let result {
                            titleField.text = result.title
                            descriptionView.text = result.summary
                            currentTags = result.tags
                            refreshTagChips()
                            if let d = result.difficulty {
                                difficultyLabel.text = "Difficulty: \(d.capitalized)"
                                difficultyLabel.isHidden = false
                            }
                            if let m = result.materials {
                                materialsLabel.text = "Materials: \(m)"
                                materialsLabel.isHidden = false
                            }
                        }
                        loadingOverlay.isHidden = true
                    }
                    return
                }
            }

            // Step 1: Extract web content
            loadingLabel.text = "Fetching page..."
            let content = await WebContentExtractor.extract(from: urlString)
            self.extractedContent = content

            // Show OG image immediately if available
            if let ogImage = content.ogImageUrl {
                await loadThumbnail(from: ogImage)
            }

            // Pre-fill with OG data while AI processes
            if let ogTitle = content.ogTitle {
                titleField.text = ogTitle
            }
            if let ogDesc = content.ogDescription {
                descriptionView.text = ogDesc
            }

            // Step 2: AI analysis
            loadingLabel.text = "Analyzing pattern..."
            let result = await AIPatternAnalyzer.analyze(content: content)
            self.aiResult = result

            // Update UI with AI results
            if let result {
                titleField.text = result.title
                descriptionView.text = result.summary
                currentTags = result.tags
                refreshTagChips()

                if let difficulty = result.difficulty {
                    difficultyLabel.text = "Difficulty: \(difficulty.capitalized)"
                    difficultyLabel.isHidden = false
                }
                if let materials = result.materials {
                    materialsLabel.text = "Materials: \(materials)"
                    materialsLabel.isHidden = false
                }
            } else {
                refreshTagChips()
            }

            loadingOverlay.isHidden = true
        }
    }

    private func isYouTubeURL(_ urlString: String) -> Bool {
        urlString.contains("youtube.com") || urlString.contains("youtu.be")
    }

    private func isTikTokURL(_ urlString: String) -> Bool {
        urlString.contains("tiktok.com")
    }

    private func aiResultFromVideoExtraction(_ v: VideoExtractionResult) -> AIPatternResult {
        AIPatternResult(
            title: v.title,
            summary: v.summary,
            tags: v.tags,
            craftType: v.craftType,
            difficulty: v.difficulty,
            materials: v.materials,
            cleanedContent: v.sourceContent,
            videoUrl: v.videoUrl,
            gauge: v.gauge,
            needleHookSizes: v.needleHookSizes,
            yarnWeightYardage: v.yarnWeightYardage,
            techniques: v.techniques,
            yarnLinks: v.yarnLinks.map { YarnLinkEntry(brandName: $0.brandName, officialUrl: $0.officialUrl, storeUrl: $0.storeUrl) }
        )
    }

    private func applyResultToUI() {
        guard let result = aiResult else { return }
        titleField.text = result.title
        descriptionView.text = result.summary
        currentTags = result.tags
        refreshTagChips()
        if let d = result.difficulty {
            difficultyLabel.text = "Difficulty: \(d.capitalized)"
            difficultyLabel.isHidden = false
        }
        if let m = result.materials {
            materialsLabel.text = "Materials: \(m)"
            materialsLabel.isHidden = false
        }
    }

    private func loadThumbnail(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                self.thumbnailImage = image
                self.imageView.image = image
                self.imageView.isHidden = false
            }
        } catch {}
    }

    private func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, range: range), let url = match.url {
            return url.absoluteString
        }
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func detectPlatform(from url: String) -> String? {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        if host.contains("tiktok") { return "tiktok" }
        if host.contains("youtube") || host.contains("youtu.be") { return "youtube" }
        if host.contains("ravelry") { return "Ravelry" }
        if host.contains("etsy") { return "Etsy" }
        if host.contains("lovecrafts") { return "LoveCrafts" }
        if host.contains("yarnspirations") { return "Yarnspirations" }
        if host.contains("knitpicks") || host.contains("knit-picks") { return "KnitPicks" }
        return nil
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        guard let urlString = sharedURL else { return }
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            titleField.layer.borderColor = UIColor.brandSoftCoral.cgColor
            titleField.layer.borderWidth = 1
            titleField.layer.cornerRadius = 6
            return
        }

        isSaving = true
        saveButton.isEnabled = false
        loadingLabel.text = "Saving..."
        loadingOverlay.isHidden = false

        let description = descriptionView.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusValues = ["want_to_make", "in_progress", "completed"]
        let status = statusValues[statusControl.selectedSegmentIndex]
        let sourceUrlToSave = sharedPdfData != nil ? "file://pattern-vault/pdf" : urlString
        let platform = detectPlatform(from: sourceUrlToSave)
        let tags = currentTags

        Task {
            do {
                try await SupabaseExtensionClient.savePattern(
                    title: title,
                    description: description,
                    sourceUrl: sourceUrlToSave,
                    sourcePlatform: platform,
                    thumbnailUrl: extractedContent?.ogImageUrl,
                    status: status,
                    tags: tags,
                    difficulty: aiResult?.difficulty,
                    materials: aiResult?.materials,
                    craftType: aiResult?.craftType,
                    sourceContent: aiResult?.cleanedContent ?? extractedContent?.pageText,
                    videoUrl: aiResult?.videoUrl,
                    gauge: aiResult?.gauge,
                    needleHookSizes: aiResult?.needleHookSizes,
                    yarnWeightYardage: aiResult?.yarnWeightYardage,
                    techniques: aiResult?.techniques,
                    pdfDataToUpload: sharedPdfData,
                    yarnLinks: aiResult?.yarnLinks.map { ($0.brandName, $0.officialUrl, $0.storeUrl) } ?? [],
                    imageUrls: extractedContent?.additionalImageUrls ?? [],
                    progressCallback: { [weak self] message in
                        DispatchQueue.main.async {
                            self?.loadingLabel.text = message
                        }
                    }
                )
                showSuccess()
            } catch {
                loadingOverlay.isHidden = true
                isSaving = false
                saveButton.isEnabled = true
                showError(error.localizedDescription)
            }
        }
    }

    @objc private func removeTag(_ sender: UIButton) {
        let index = sender.tag
        if index < currentTags.count {
            currentTags.remove(at: index)
            refreshTagChips()
        }
    }

    @objc private func addTagTapped() {
        let alert = UIAlertController(title: "Add Tag", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Tag name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            if let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                self?.currentTags.append(text)
                self?.refreshTagChips()
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Feedback

    private func showSuccess() {
        loadingSpinner.stopAnimating()
        loadingLabel.layer.removeAnimation(forKey: "pulse")
        loadingLabel.text = "Saved!"

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .brandSageGreen
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.widthAnchor.constraint(equalToConstant: 48).isActive = true
        checkmark.heightAnchor.constraint(equalToConstant: 48).isActive = true
        checkmark.contentMode = .scaleAspectFit
        checkmark.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        checkmark.alpha = 0

        if let stack = loadingSpinner.superview as? UIStackView {
            stack.insertArrangedSubview(checkmark, at: 0)
            loadingSpinner.isHidden = true
        }

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            checkmark.transform = .identity
            checkmark.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError(_ message: String) {
        loadingOverlay.isHidden = true

        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}
