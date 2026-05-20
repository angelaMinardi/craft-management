//
//  ShareViewController.swift
//  SaveToPatternVault
//
//  Rich share extension UI for capturing craft patterns with AI-powered metadata.
//

import UIKit
import UniformTypeIdentifiers

// MARK: - Entitlement cache (reads from App Group; main app writes usage when active)
private enum ExtensionEntitlementCache {
    private static let appGroupId = "group.com.corvidcraft.app"
    // Keep these in sync with EntitlementLimits in SubscriptionStore.swift — the
    // Share Extension target can't import main-app Swift files.
    private static let freeAIPerMonth = 5
    private static let freePatternLimit = 25
    private static let premiumAISoftCapPerMonth = 200

    static var canUseAI: Bool {
        #if DEBUG
        return true
        #else
        let defaults = UserDefaults(suiteName: appGroupId)
        let isPremium = defaults?.bool(forKey: "entitlement_is_premium") == true
        let used = defaults?.integer(forKey: "entitlement_ai_usage_this_month") ?? 0
        let month = defaults?.string(forKey: "entitlement_usage_month") ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())
        // New month since last sync: assume quota reset.
        if month != currentMonth { return true }
        let cap = isPremium ? premiumAISoftCapPerMonth : freeAIPerMonth
        return used < cap
        #endif
    }

    static var canAddPattern: Bool {
        let defaults = UserDefaults(suiteName: appGroupId)
        if defaults?.bool(forKey: "entitlement_is_premium") == true { return true }
        let count = defaults?.integer(forKey: "entitlement_pattern_count") ?? 0
        return count < freePatternLimit
    }
}

// MARK: - AI kill switch (cost cap): read from App Group; fetch from Supabase if stale)
private enum ExtensionAIKillSwitch {
    private static let appGroupId = "group.com.corvidcraft.app"
    private static let cacheKeyEnabled = "app_config_ai_enabled"
    private static let cacheKeyUpdated = "app_config_ai_enabled_updated"
    private static let cacheTTL: TimeInterval = 15 * 60

    /// Call before using AI. Fetches from Supabase if cache missing or older than 15 min.
    static func ensureCached() async {
        let defaults = UserDefaults(suiteName: appGroupId)
        let updated = defaults?.object(forKey: cacheKeyUpdated) as? Date
        if let updated, Date().timeIntervalSince(updated) < cacheTTL, defaults?.object(forKey: cacheKeyEnabled) != nil {
            return
        }
        guard let (url, anonKey) = config() else { return }
        let base = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard let fetchURL = URL(string: "\(base)/rest/v1/app_config?id=eq.1&select=ai_enabled") else { return }
        var request = URLRequest(url: fetchURL)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = json.first,
                  let enabled = row["ai_enabled"] as? Bool else { return }
            defaults?.set(enabled, forKey: cacheKeyEnabled)
            defaults?.set(Date(), forKey: cacheKeyUpdated)
            defaults?.synchronize()
        } catch {
            // Leave cache as-is; if no cache, isAIDisabledByKillSwitch will be false (allow AI)
        }
    }

    /// True when AI is disabled by kill switch (cost cap). Read after ensureCached().
    static var isAIDisabledByKillSwitch: Bool {
        let defaults = UserDefaults(suiteName: appGroupId)
        guard defaults?.object(forKey: cacheKeyEnabled) != nil else { return false }
        return (defaults?.bool(forKey: cacheKeyEnabled) ?? true) == false
    }

    private static func config() -> (url: String, anonKey: String)? {
        let defaults = UserDefaults(suiteName: appGroupId)
        if let url = defaults?.string(forKey: "supabase_url"),
           let key = defaults?.string(forKey: "supabase_anon_key"),
           !url.isEmpty, !key.isEmpty {
            let normalized = url.hasSuffix("/") ? String(url.dropLast()) : url
            if let parsed = URL(string: normalized),
               let scheme = parsed.scheme?.lowercased(),
               (scheme == "https" || scheme == "http"),
               parsed.host != nil {
                return (normalized, key)
            }
        }
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
           !url.isEmpty, !key.isEmpty {
            let normalized = url.hasSuffix("/") ? String(url.dropLast()) : url
            if let parsed = URL(string: normalized),
               let scheme = parsed.scheme?.lowercased(),
               (scheme == "https" || scheme == "http"),
               parsed.host != nil {
                return (normalized, key)
            }
        }
        return nil
    }
}

// MARK: - Brand Colors
// Keep in sync with PatternVault/Theme.swift UIKit section (uiWarmCream, uiSoftCoral, uiDeepPlum, uiSageGreen).
// Extension target cannot import main app Swift files.
private extension UIColor {
    static let brandWarmCream = UIColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0)
    static let brandSoftCoral = UIColor(red: 0.910, green: 0.514, blue: 0.420, alpha: 1.0)
    static let brandDeepPlum = UIColor(red: 0.290, green: 0.125, blue: 0.251, alpha: 1.0)
    static let brandSageGreen = UIColor(red: 0.659, green: 0.773, blue: 0.627, alpha: 1.0)
}

class ShareViewController: UIViewController {

    // MARK: - State

    private enum ShareLoadingState {
        case extracting
        case fetching
        case analyzing
        case saving(message: String)
    }

    private var sharedURL: String?
    private var sharedPdfData: Data?
    private var pdfPageImages: [Data] = []
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
    private let fallbackNoticeLabel = UILabel()
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
        saveButton.titleLabel?.font = roundedFont(size: 17, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(saveButton)

        // Title
        titleLabel.text = "Save to Corvid Craft"
        titleLabel.font = roundedFont(size: 17, weight: .semibold)
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
        titleField.attributedPlaceholder = NSAttributedString(
            string: "Pattern title...",
            attributes: [.foregroundColor: UIColor.brandDeepPlum.withAlphaComponent(0.55)]
        )
        titleField.font = roundedFont(size: 16, weight: .regular)
        titleField.textColor = .brandDeepPlum
        titleField.tintColor = .brandSoftCoral
        titleField.borderStyle = .none
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addArrangedSubview(titleField)
        contentStack.addArrangedSubview(titleContainer)

        // Description
        let descContainer = createFieldContainer(label: "Description")
        descriptionView.font = roundedFont(size: 15, weight: .regular)
        descriptionView.textColor = .brandDeepPlum
        descriptionView.tintColor = .brandSoftCoral
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
        difficultyLabel.font = roundedFont(size: 14, weight: .regular)
        difficultyLabel.textColor = .brandDeepPlum.withAlphaComponent(0.82)
        difficultyLabel.isHidden = true
        contentStack.addArrangedSubview(difficultyLabel)

        materialsLabel.font = roundedFont(size: 14, weight: .regular)
        materialsLabel.textColor = .brandDeepPlum.withAlphaComponent(0.82)
        materialsLabel.numberOfLines = 0
        materialsLabel.isHidden = true
        contentStack.addArrangedSubview(materialsLabel)

        fallbackNoticeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fallbackNoticeLabel.textColor = .brandDeepPlum.withAlphaComponent(0.86)
        fallbackNoticeLabel.numberOfLines = 0
        fallbackNoticeLabel.isHidden = true
        fallbackNoticeLabel.text = "Some details may need a quick edit. You can still save right now."
        contentStack.addArrangedSubview(fallbackNoticeLabel)

        // URL
        let urlHeader = createSectionLabel("Source")
        contentStack.addArrangedSubview(urlHeader)
        urlLabel.font = roundedFont(size: 13, weight: .regular)
        urlLabel.textColor = .brandDeepPlum.withAlphaComponent(0.82)
        urlLabel.numberOfLines = 2
        urlLabel.lineBreakMode = .byTruncatingMiddle
        contentStack.addArrangedSubview(urlLabel)

        // Status
        let statusHeader = createSectionLabel("Status")
        contentStack.addArrangedSubview(statusHeader)
        statusControl.selectedSegmentIndex = 0
        statusControl.backgroundColor = UIColor.brandWarmCream.withAlphaComponent(0.85)
        statusControl.selectedSegmentTintColor = .brandSoftCoral
        statusControl.setTitleTextAttributes(
            [
                .foregroundColor: UIColor.brandDeepPlum,
                .font: roundedFont(size: 13, weight: .semibold)
            ],
            for: .normal
        )
        statusControl.setTitleTextAttributes(
            [
                .foregroundColor: UIColor.white,
                .font: roundedFont(size: 13, weight: .semibold)
            ],
            for: .selected
        )
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
        loadingLabel.font = roundedFont(size: 15, weight: .medium)
        loadingLabel.textColor = .brandDeepPlum.withAlphaComponent(0.88)

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

    private func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func createSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = roundedFont(size: 13, weight: .semibold)
        label.textColor = .brandDeepPlum.withAlphaComponent(0.82)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func createTagChip(_ text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .brandSoftCoral.withAlphaComponent(0.14)
        container.layer.cornerRadius = 14

        let label = UILabel()
        label.text = text
        label.font = roundedFont(size: 13, weight: .medium)
        label.textColor = .brandDeepPlum
        label.translatesAutoresizingMaskIntoConstraints = false

        let removeBtn = UIButton(type: .system)
        removeBtn.setImage(UIImage(systemName: "xmark.circle.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12)), for: .normal)
        removeBtn.tintColor = .brandDeepPlum.withAlphaComponent(0.8)
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

    private func setLoadingState(_ state: ShareLoadingState) {
        loadingOverlay.isHidden = false
        switch state {
        case .extracting:
            loadingLabel.text = "Gathering your pattern details..."
        case .fetching:
            loadingLabel.text = "Fetching source details..."
        case .analyzing:
            loadingLabel.text = "Organizing this pattern for you..."
        case .saving(let message):
            loadingLabel.text = message
        }
    }

    private func enterEditableFallback(message: String, suggestedTitle: String = "Saved Pattern") {
        loadingOverlay.isHidden = true
        fallbackNoticeLabel.text = message
        fallbackNoticeLabel.isHidden = false

        if (titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            titleField.text = suggestedTitle
        }
        if currentTags.isEmpty, let url = sharedURL {
            currentTags = AIPatternAnalyzer.fallbackTags(sourceUrl: url)
            refreshTagChips()
        }
    }

    private func showTerminalError(_ message: String, retryHandler: (() -> Void)? = nil) {
        loadingOverlay.isHidden = true
        let alert = UIAlertController(title: "Couldn't complete this step", message: message, preferredStyle: .alert)
        if let retryHandler {
            alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
                retryHandler()
            })
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
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
            showTerminalError("No content was shared to Corvid Craft.", retryHandler: { [weak self] in self?.extractSharedURL() })
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            showTerminalError("This share type is not supported yet.", retryHandler: { [weak self] in self?.extractSharedURL() })
            return
        }

        // Prefer PDF when present.
        if let pdfProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) {
            let maxPdfSize = 50_000_000 // 50 MB — covers complex pattern books and scan-heavy PDFs
            pdfProvider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] data, _ in
                DispatchQueue.main.async {
                    if let url = data as? URL {
                        guard let pdfData = try? Data(contentsOf: url) else {
                            self?.showTerminalError("Could not read this PDF. Try sharing again from the source app.", retryHandler: { [weak self] in self?.extractSharedURL() })
                            return
                        }
                        if pdfData.count > maxPdfSize {
                            self?.showTerminalError("PDF is too large (max 50 MB). Try sharing just the relevant pages, or open the pattern URL directly.", retryHandler: { [weak self] in self?.extractSharedURL() })
                            return
                        }
                        self?.sharedPdfData = pdfData
                        self?.sharedURL = url.absoluteString
                        self?.beginAnalysisForPdf()
                    } else if let pdfData = data as? Data {
                        if pdfData.count > maxPdfSize {
                            self?.showTerminalError("PDF is too large (max 50 MB). Try sharing just the relevant pages, or open the pattern URL directly.", retryHandler: { [weak self] in self?.extractSharedURL() })
                            return
                        }
                        self?.sharedPdfData = pdfData
                        self?.sharedURL = "file://pattern-vault/pdf"
                        self?.beginAnalysisForPdf()
                    } else {
                        self?.showTerminalError("Could not read this PDF. Try sharing again from the source app.", retryHandler: { [weak self] in self?.extractSharedURL() })
                    }
                }
            }
            return
        }

        attemptLoadURL(from: providers, providerIndex: 0)
    }

    /// Tries each provider/type combination before giving up.
    private func attemptLoadURL(from providers: [NSItemProvider], providerIndex: Int) {
        guard providerIndex < providers.count else {
            showTerminalError("No URL found in shared content.", retryHandler: { [weak self] in self?.extractSharedURL() })
            return
        }
        let provider = providers[providerIndex]
        let candidateTypeIds = candidateTypeIdentifiers(for: provider)
        guard !candidateTypeIds.isEmpty else {
            attemptLoadURL(from: providers, providerIndex: providerIndex + 1)
            return
        }

        attemptLoadURL(
            from: provider,
            typeIds: candidateTypeIds,
            typeIndex: 0,
            onFound: { [weak self] url in
                self?.sharedURL = url
                self?.beginAnalysis()
            },
            onExhausted: { [weak self] in
                self?.attemptLoadURL(from: providers, providerIndex: providerIndex + 1)
            }
        )
    }

    private func candidateTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        let prioritized: [String] = [
            UTType.url.identifier,
            "public.url",
            "public.url-name",
            UTType.plainText.identifier,
            UTType.text.identifier,
            "public.text",
            "public.utf8-plain-text",
            "public.data"
        ]

        var result: [String] = []
        var seen = Set<String>()
        for typeId in prioritized where provider.hasItemConformingToTypeIdentifier(typeId) {
            if seen.insert(typeId).inserted { result.append(typeId) }
        }
        // Firefox often uses custom identifiers.
        for typeId in provider.registeredTypeIdentifiers {
            if seen.insert(typeId).inserted {
                result.append(typeId)
            }
        }
        return result
    }

    private func attemptLoadURL(
        from provider: NSItemProvider,
        typeIds: [String],
        typeIndex: Int,
        onFound: @escaping (String) -> Void,
        onExhausted: @escaping () -> Void
    ) {
        guard typeIndex < typeIds.count else {
            onExhausted()
            return
        }
        let typeId = typeIds[typeIndex]
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] data, _ in
            DispatchQueue.main.async {
                if let extracted = self?.extractURL(fromSharedItem: data) {
                    onFound(extracted)
                } else {
                    self?.attemptLoadURL(
                        from: provider,
                        typeIds: typeIds,
                        typeIndex: typeIndex + 1,
                        onFound: onFound,
                        onExhausted: onExhausted
                    )
                }
            }
        }
    }

    private func extractURL(fromSharedItem item: Any?) -> String? {
        ShareURLExtractor.extractURL(fromSharedItem: item)
    }

    private func beginAnalysisForPdf() {
        guard let pdfData = sharedPdfData else {
            urlLabel.text = "PDF pattern"
            titleField.text = titleField.text?.isEmpty == true ? "PDF Pattern" : titleField.text
            loadingOverlay.isHidden = true
            return
        }
        urlLabel.text = "PDF pattern"
        fallbackNoticeLabel.isHidden = true
        setLoadingState(.extracting)

        Task {
            // Extract text from PDF
            let pageText = PDFTextExtractor.extractText(from: pdfData)

            // Render up to 5 pages as images for gallery (same as website image extraction)
            let renderedPages = PDFPageRenderer.renderPages(
                from: pdfData, maxPages: 5, scale: 2.0, jpegQuality: 0.8
            )
            let pageImages = renderedPages.map(\.imageData)

            let minTextLength = 50
            guard let text = pageText, text.count >= minTextLength else {
                await MainActor.run {
                    self.pdfPageImages = pageImages
                    // Still show first page as thumbnail even without text
                    if let firstImage = pageImages.first, let uiImage = UIImage(data: firstImage) {
                        self.thumbnailImage = uiImage
                        self.imageView.image = uiImage
                        self.imageView.isHidden = false
                    }
                    enterEditableFallback(
                        message: "This PDF has limited extractable text. Add a title and save, then refine later.",
                        suggestedTitle: "PDF Pattern"
                    )
                }
                return
            }

            let content = ExtractedContent(
                ogTitle: nil,
                ogDescription: nil,
                ogImageUrl: nil,
                additionalImageUrls: [],
                pageText: text,
                sourceUrl: sharedURL ?? "file://pattern-vault/pdf",
                videoUrls: [],
                patternPdfUrl: nil
            )
            self.extractedContent = content

            await MainActor.run {
                self.pdfPageImages = pageImages

                // Show first page as thumbnail preview
                if let firstImage = pageImages.first, let uiImage = UIImage(data: firstImage) {
                    self.thumbnailImage = uiImage
                    self.imageView.image = uiImage
                    self.imageView.isHidden = false
                }

                let inferredTitle = self.inferredPdfTitle(from: text, sourceURL: self.sharedURL)
                let inferredSummary = self.inferredPdfSummary(from: text)
                let fallbackTags = AIPatternAnalyzer.fallbackTags(sourceUrl: self.sharedURL ?? "file://pattern-vault/pdf")

                titleField.text = inferredTitle
                descriptionView.text = inferredSummary
                currentTags = fallbackTags
                refreshTagChips()

                fallbackNoticeLabel.text = "Full details will be added automatically after you save."
                fallbackNoticeLabel.isHidden = false
                loadingOverlay.isHidden = true
            }
        }
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func inferredPdfTitle(from text: String, sourceURL: String?) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let candidate = lines.first(where: { $0.count >= 4 && $0.count <= 80 && !$0.contains("http") }) {
            return candidate
        }
        if let sourceURL,
           let url = URL(string: sourceURL),
           url.isFileURL {
            let base = url.deletingPathExtension().lastPathComponent
            let cleaned = base
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return "PDF Pattern"
    }

    private func inferredPdfSummary(from text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ")
        if compact.isEmpty {
            return "Imported from PDF. You can edit details before saving."
        }
        return String(compact.prefix(260))
    }

    private func beginAnalysis() {
        guard let urlString = sharedURL else { return }
        urlLabel.text = urlString
        fallbackNoticeLabel.isHidden = true
        loadingOverlay.isHidden = false

        Task {
            // Cache AI kill switch so saveTapped can decide enrichment
            await ExtensionAIKillSwitch.ensureCached()

            if isYouTubeURL(urlString) {
                setLoadingState(.fetching)
                let content = await WebContentExtractor.extract(from: urlString)
                self.extractedContent = content
                if let ogImage = content.ogImageUrl {
                    await loadThumbnail(from: ogImage)
                }
                await MainActor.run {
                    var ytTitle = content.ogTitle ?? ""
                    ytTitle = ytTitle.replacingOccurrences(of: " - YouTube", with: "")
                    titleField.text = self.nonEmpty(ytTitle) ?? "YouTube Pattern"
                    descriptionView.text = content.ogDescription
                    currentTags = AIPatternAnalyzer.fallbackTags(sourceUrl: urlString)
                    refreshTagChips()
                    fallbackNoticeLabel.text = "Full details will be added automatically after you save."
                    fallbackNoticeLabel.isHidden = false
                    loadingOverlay.isHidden = true
                }
                return
            }

            if isTikTokURL(urlString) {
                setLoadingState(.fetching)
                if let tiktokContent = await TikTokContentExtractor.extract(from: urlString) {
                    self.extractedContent = tiktokContent
                    if let ogImage = tiktokContent.ogImageUrl {
                        await loadThumbnail(from: ogImage)
                    }
                    await MainActor.run {
                        titleField.text = tiktokContent.ogTitle
                        descriptionView.text = tiktokContent.ogDescription
                        currentTags = AIPatternAnalyzer.fallbackTags(sourceUrl: urlString)
                        refreshTagChips()
                        fallbackNoticeLabel.text = "Full details will be added automatically after you save."
                        fallbackNoticeLabel.isHidden = false
                        loadingOverlay.isHidden = true
                    }
                } else {
                    await MainActor.run {
                        enterEditableFallback(message: "Couldn't fetch TikTok details, but you can save this link and edit details.")
                    }
                }
                return
            }

            // Ravelry and other URLs: fetch content only (no AI in extension).
            setLoadingState(.fetching)
            var content: ExtractedContent
            if RavelryPatternExtractor.isRavelryPatternURL(urlString),
               let ravelryContent = await RavelryPatternExtractor.extract(from: urlString) {
                content = ravelryContent
            } else {
                content = await WebContentExtractor.extract(from: urlString)
                if RavelryPatternExtractor.isRavelryPatternURL(urlString), let raw = content.pageText {
                    let filtered = RavelryPatternExtractor.filterRavelryChrome(from: raw)
                    content = ExtractedContent(
                        ogTitle: content.ogTitle,
                        ogDescription: content.ogDescription,
                        ogImageUrl: content.ogImageUrl,
                        additionalImageUrls: content.additionalImageUrls,
                        pageText: filtered,
                        sourceUrl: content.sourceUrl,
                        videoUrls: content.videoUrls,
                        patternPdfUrl: nil
                    )
                }
            }
            self.extractedContent = content

            if let ogImage = content.ogImageUrl {
                await loadThumbnail(from: ogImage)
            }

            await MainActor.run {
                if let ogTitle = content.ogTitle {
                    titleField.text = ogTitle
                }
                if let ogDesc = content.ogDescription {
                    descriptionView.text = ogDesc
                }
                currentTags = AIPatternAnalyzer.fallbackTags(sourceUrl: urlString)
                refreshTagChips()
                fallbackNoticeLabel.text = "Full details will be added automatically after you save."
                fallbackNoticeLabel.isHidden = false
                loadingOverlay.isHidden = true
            }
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
            yarnLinks: v.yarnLinks.map { YarnLinkEntry(brandName: $0.brandName, officialUrl: $0.officialUrl, storeUrl: $0.storeUrl) },
            parsedStepsJSON: v.parsedSteps,
            isFallback: false
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

    /// Downloads up to N image URLs as compressed JPEG data for Gemini vision analysis.
    private static func downloadImagesForAnalysis(urls: [String], maxWidth: CGFloat = 800, quality: CGFloat = 0.6) async -> [Data] {
        var results: [Data] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { continue }
                let scale = min(1.0, maxWidth / image.size.width)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
                if let jpeg = resized.jpegData(compressionQuality: quality) {
                    results.append(jpeg)
                }
            } catch {
                continue
            }
        }
        return results
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
        ShareURLExtractor.extractURL(from: text)
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

        if SupabaseExtensionClient.authInfo() == nil {
            enterEditableFallback(message: "Please open Corvid Craft and sign in first, then try saving again.")
            return
        }

        titleField.layer.borderWidth = 0
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            titleField.layer.borderColor = UIColor.brandSoftCoral.cgColor
            titleField.layer.borderWidth = 1
            titleField.layer.cornerRadius = 6
            let alert = UIAlertController(title: nil, message: "Please enter a pattern title.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        if !ExtensionEntitlementCache.canAddPattern {
            enterEditableFallback(message: "Pattern limit reached. You can still edit details, then upgrade in app to save more.")
            return
        }

        isSaving = true
        saveButton.isEnabled = false
        setLoadingState(.saving(message: "Saving to your vault..."))

        let description = descriptionView.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusValues = ["want_to_make", "in_progress", "completed"]
        let status = statusValues[statusControl.selectedSegmentIndex]
        let sourceUrlToSave = sharedPdfData != nil ? "file://pattern-vault/pdf" : urlString
        let platform = detectPlatform(from: sourceUrlToSave)
        let tags = currentTags
        let pdfUrlToSave = extractedContent?.patternPdfUrl
        var sourceContentToSave = extractedContent?.pageText
        if platform == "Ravelry", RavelryPatternExtractor.looksLikeRavelryChrome(sourceContentToSave) {
            sourceContentToSave = nil
        }
        let videoUrlToSave = (platform == "tiktok" ? extractedContent?.videoUrls.first : nil)
        let isTikTok = platform == "tiktok"

        // TikTok videos: skip AI enrichment — captions produce poor steps/descriptions
        if isTikTok { sourceContentToSave = nil }
        let shouldEnrich = !isTikTok && ExtensionEntitlementCache.canUseAI && !ExtensionAIKillSwitch.isAIDisabledByKillSwitch
        let enrichmentStatus = isTikTok ? "complete" : (shouldEnrich ? "pending" : "failed")

        let capturedExtractedContent = extractedContent
        let capturedPdfData = sharedPdfData
        let capturedPdfPageImages = pdfPageImages

        Task {
            let saveTask = Task {
                let saveResult = try await SupabaseExtensionClient.savePattern(
                    title: title,
                    description: description,
                    sourceUrl: sourceUrlToSave,
                    sourcePlatform: platform,
                    thumbnailUrl: capturedExtractedContent?.ogImageUrl,
                    status: status,
                    tags: tags,
                    sourceContent: sourceContentToSave,
                    videoUrl: videoUrlToSave,
                    pdfUrl: pdfUrlToSave,
                    pdfDataToUpload: capturedPdfData,
                    imageUrls: capturedExtractedContent?.additionalImageUrls ?? [],
                    pdfPageImageData: capturedPdfPageImages,
                    enrichmentStatus: enrichmentStatus,
                    progressCallback: { [weak self] message in
                        DispatchQueue.main.async {
                            self?.setLoadingState(.saving(message: message))
                        }
                    }
                )
                try Task.checkCancellation()
                return saveResult
            }

            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(60))
                saveTask.cancel()
            }

            do {
                let saveResult = try await saveTask.value
                timeoutTask.cancel()
                if shouldEnrich {
                    // Best-effort fire-and-forget; main app will also trigger enrichment
                    // for any pending patterns on launch, so this is not critical.
                    Task.detached(priority: .utility) {
                        await SupabaseExtensionClient.requestEnrichment(patternId: saveResult.patternId)
                    }
                }
                let defaults = UserDefaults(suiteName: "group.com.corvidcraft.app")
                defaults?.set(saveResult.patternId, forKey: "savedPatternId")
                defaults?.set(title, forKey: "savedPatternTitle")
                defaults?.synchronize()
                showSuccess(warnings: saveResult.warnings, enriching: shouldEnrich)
            } catch is CancellationError {
                timeoutTask.cancel()
                loadingOverlay.isHidden = true
                isSaving = false
                saveButton.isEnabled = true
                showTerminalError("Save timed out. Please try again.", retryHandler: { [weak self] in self?.saveTapped() })
            } catch {
                timeoutTask.cancel()
                loadingOverlay.isHidden = true
                isSaving = false
                saveButton.isEnabled = true
                let ns = error as NSError
                let url = (ns.userInfo["NSURLErrorFailingURLStringKey"] as? String) ?? (ns.userInfo["NSURLErrorFailingURLKey"] as? URL)?.absoluteString ?? "—"
                let connection = SupabaseExtensionClient.connectionDiagnostics()
                #if DEBUG
                NSLog("[SaveToPatternVault] save failed: domain=%@ code=%ld desc=%@ failingURL=%@ diag=%@", ns.domain, ns.code, error.localizedDescription, url, connection)
                #endif
                // Write to app group so main app can show in Settings → Last share error
                let defaults = UserDefaults(suiteName: "group.com.corvidcraft.app")
                let diagnostic = "domain=\(ns.domain) code=\(ns.code) url=\(url) \(connection)"
                defaults?.set(diagnostic, forKey: "lastShareErrorDiagnostic")
                defaults?.set(Date(), forKey: "lastShareErrorDate")
                defaults?.synchronize()
                let message: String
                if let e = error as? SupabaseExtensionError {
                    switch e {
                    case .notAuthenticated:
                        message = "Open Corvid Craft, sign in, and try sharing again."
                    case .missingConfig:
                        message = "App config is missing. Open Corvid Craft once and try again."
                    case .saveFailed:
                        message = SupabaseExtensionError.messageForNetworkError(error)
                    }
                } else {
                    message = SupabaseExtensionError.messageForNetworkError(error)
                }
                showTerminalError(message, retryHandler: { [weak self] in self?.saveTapped() })
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
                let normalized = text.lowercased()
                if self?.currentTags.contains(where: { $0.lowercased() == normalized }) == true { return }
                self?.currentTags.append(text)
                self?.refreshTagChips()
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Feedback

    private func showSuccess(warnings: [String] = [], enriching: Bool = false) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)

        loadingSpinner.stopAnimating()
        loadingLabel.layer.removeAnimation(forKey: "pulse")
        loadingLabel.text = enriching
            ? "Saved! Full details coming soon."
            : "Saved without AI analysis."

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
            guard let self else { return }
            if warnings.isEmpty {
                self.extensionContext?.completeRequest(returningItems: nil)
                return
            }
            let message = "Pattern saved, but \(warnings.joined(separator: " "))"
            let alert = UIAlertController(title: "Saved with warnings", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.extensionContext?.completeRequest(returningItems: nil)
            })
            self.present(alert, animated: true)
        }
    }

}
