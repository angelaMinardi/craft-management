//
//  SettingsView.swift
//  PatternVault
//

import AuthenticationServices
import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @ObservedObject var tutorialStore: AppTutorialStore
    @ObservedObject private var celebrationStore = CelebrationStore.shared
    private var currentStepAnchor: TutorialAnchor? {
        guard tutorialStore.isActive, tutorialStore.currentStep < AppTutorialStore.steps.count else { return nil }
        return AppTutorialStore.steps[tutorialStore.currentStep].anchorId
    }
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false
    /// The source passed to the paywall — defaults to Settings but callers
    /// can override before flipping showPaywall so analytics + copy stay in sync.
    @State private var paywallSource: GrowthOrchestrator.PaywallSource = .settings
    @State private var exportFileItem: ExportFileItem?
    @State private var isExporting = false
    @State private var isUserBackupExporting = false
    @StateObject private var ravelryImportStore = RavelryImportStore()
    @State private var showRavelryImportConfirm = false
    @State private var ravelryOAuthError: String?
    @State private var showMascotHelp = false
    @State private var showAIInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    profileCard
                    premiumSection
                    accountSection
                    userBackupSection
                    duplicatesSection
                    ravelrySection
                    #if DEBUG
                    testingExportSection
                    #endif
                    aboutSection
                    celebrationsSection
                    helpSection
                    if hasAnyLegalURL {
                        legalSection
                    }
                    appFooter
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can sign in again anytime.")
            }
            // App Review (2.1(a)): use .alert instead of .confirmationDialog so the
            // destructive Delete Account flow is presented as a centered modal on iPad
            // (the popover-style confirmationDialog was clipping at the bottom edge).
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Delete Account", role: .destructive) {
                    Task { await auth.deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete your account and all your data. This cannot be undone.")
            }
            .sheet(item: $exportFileItem) { item in
                exportReadySheet(fileURL: item.url, isUserBackup: item.isUserBackup)
            }
            .sheet(isPresented: $showPaywall, onDismiss: { paywallSource = .settings }) {
                PaywallView(source: paywallSource)
            }
            .sheet(isPresented: $showMascotHelp) {
                MascotHelpView()
            }
            .sheet(isPresented: $showAIInfo) {
                AIInfoView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ravelryOAuthCallback)) { notification in
                guard let url = notification.object as? URL, let userId = auth.currentUserId else { return }
                Task { await processRavelryCallback(url: url, userId: userId) }
            }
            .onAppear {
                if let userId = auth.currentUserId {
                    let defaults = UserDefaults(suiteName: "group.com.corvidcraft.app")
                    if let urlString = defaults?.string(forKey: "pendingRavelryCallbackURL"),
                       let url = URL(string: urlString) {
                        defaults?.removeObject(forKey: "pendingRavelryCallbackURL")
                        defaults?.synchronize()
                        Task { await processRavelryCallback(url: url, userId: userId) }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .processPendingRavelryCallback)) { _ in
                guard let userId = auth.currentUserId else { return }
                let defaults = UserDefaults(suiteName: "group.com.corvidcraft.app")
                guard let urlString = defaults?.string(forKey: "pendingRavelryCallbackURL"),
                      let url = URL(string: urlString) else { return }
                defaults?.removeObject(forKey: "pendingRavelryCallbackURL")
                defaults?.synchronize()
                Task { await processRavelryCallback(url: url, userId: userId) }
            }
            .alert("Ravelry", isPresented: Binding(get: { ravelryOAuthError != nil }, set: { if !$0 { ravelryOAuthError = nil } })) {
                Button("OK", role: .cancel) { ravelryOAuthError = nil }
            } message: {
                if let msg = ravelryOAuthError { Text(msg) }
            }
            .alert("Account", isPresented: Binding(get: { auth.errorMessage != nil }, set: { if !$0 { auth.clearError() } })) {
                Button("OK", role: .cancel) {
                    auth.clearError()
                }
            } message: {
                if let msg = auth.errorMessage { Text(msg) }
            }
            .task {
                if let userId = auth.currentUserId, RavelryOAuthService.shared.isConnected(userId: userId) {
                    await ravelryImportStore.fetchUsername(userId: userId)
                }
            }
            .confirmationDialog("Import from Ravelry", isPresented: $showRavelryImportConfirm) {
                Button("Import") {
                    guard let userId = auth.currentUserId else { return }
                    Task { await ravelryImportStore.importLibrary(userId: userId, patternStore: store) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will import patterns from your Ravelry library, favorites, queue, and projects, plus your yarn stash. Existing items won't be duplicated.")
            }
        }
    }

    // MARK: - Premium

    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Premium")

            Button {
                // Explicit user intent from Settings should never be suppressed.
                paywallSource = .settings
                showPaywall = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: SubscriptionStore.shared.isPremium ? "crown.fill" : "crown")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.honey)
                        .frame(width: 22)
                    Text(SubscriptionStore.shared.isPremium ? "Manage Premium" : "Upgrade to Premium")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.2))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .settingsRowHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SubscriptionStore.shared.isPremium ? "Manage Premium" : "Upgrade to Premium")

            // Restore Purchases (App Store Review guideline 3.1.1 — must be
            // available outside the paywall too).
            Button {
                Task {
                    await SubscriptionStore.shared.restorePurchases()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.sageGreen)
                        .frame(width: 22)
                    Text("Restore purchases")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.2))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .settingsRowHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restore purchases")

            if let restoreMessage = SubscriptionStore.shared.restoreNoResultMessage {
                Text(restoreMessage)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            // Manage Subscription (only visible to premium users).
            if SubscriptionStore.shared.isPremium {
                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dustyBlue)
                            .frame(width: 22)
                        Text("Manage subscription")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .settingsRowHitArea()
                }
                .accessibilityLabel("Manage subscription in the App Store")
            }

            // Redeem promo code (Holiday promos, re-engagement offers).
            // iOS presents the native App Store code-redemption sheet.
            Button {
                AnalyticsService.shared.track(
                    .offerCodeRedeemed,
                    properties: [AnalyticsService.Property.entrySurface: "settings"]
                )
                Task { @MainActor in
                    guard let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.activationState == .foregroundActive }) else {
                        return
                    }
                    try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.softCoral)
                        .frame(width: 22)
                    Text("Redeem promo code")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.2))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .settingsRowHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Redeem promo code")

            if !SubscriptionStore.shared.isPremium {
                Text("Free: 25 patterns, 5 AI/month, 20 note photos; includes ads. \(Theme.Premium.tagline)")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    // MARK: - User backup / export

    private var userBackupSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Backup")

            Button {
                Task { await exportUserBackup() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isUserBackupExporting {
                        ProgressView()
                            .scaleEffect(0.9)
                            .frame(width: 22)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.sageGreen)
                            .frame(width: 22)
                    }
                    Text("Export my data")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.2))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .settingsRowHitArea()
            }
            .buttonStyle(.plain)
            .disabled(isUserBackupExporting)
            .accessibilityLabel("Export my data")
            .accessibilityHint("Saves a backup of your patterns as JSON; use Share to save to Files or another app")

            Text("Save a JSON backup of your patterns (titles, status, source URLs, craft type, tags). Use Share to save to Files or send to another device.")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    /// Returns the Ravelry OAuth URL to open in browser. Call from MainActor.
    @MainActor
    private func startRavelryOAuthURL() async throws -> URL {
        try await RavelryOAuthService.shared.startOAuth()
    }

    /// Process Ravelry OAuth callback URL (from notification or pending store). Exchanges code for tokens and fetches username.
    @MainActor
    private func processRavelryCallback(url: URL, userId: UUID) async {
        // Skip if already connected — another callback path may have succeeded first
        if RavelryOAuthService.shared.isConnected(userId: userId) {
            if ravelryImportStore.ravelryUsername == nil {
                await ravelryImportStore.fetchUsername(userId: userId)
            }
            ravelryOAuthError = nil
            return
        }
        do {
            try await RavelryOAuthService.shared.handleCallback(url: url, userId: userId)
            await ravelryImportStore.fetchUsername(userId: userId)
            ravelryOAuthError = nil
        } catch {
            ravelryOAuthError = error.localizedDescription
        }
    }

    private func exportUserBackup() async {
        guard let userId = auth.currentUserId else { return }
        isUserBackupExporting = true
        defer { isUserBackupExporting = false }
        await store.load(userId: userId)
        let payload = DebugPatternExport.export(from: store.patterns)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let fileName = "corvidcraft_backup_\(dateStr).json"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        try? data.write(to: fileURL)
        exportFileItem = ExportFileItem(url: fileURL, isUserBackup: true)
    }

    // MARK: - Testing: Export patterns for assistant to read

    private var testingExportSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Testing")

            Button {
                Task { await exportPatternsForDebugging() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.9)
                            .frame(width: 22)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.sageGreen)
                            .frame(width: 22)
                    }
                    Text("Export patterns for debugging")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.2))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .settingsRowHitArea()
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .accessibilityLabel("Export patterns for debugging")
            .accessibilityHint("Saves a JSON snapshot of your patterns so the assistant can read it")

            Text("Save the file to your project folder (e.g. PatternVault/) so the assistant can see uploaded patterns.")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                .padding(.horizontal, Theme.Spacing.lg)

        }
    }

    private func exportReadySheet(fileURL: URL, isUserBackup: Bool = false) -> some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.sageGreen)
                Text("Exported \(store.patterns.count) pattern(s)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.deepPlum)
                Text(isUserBackup
                     ? "Your backup is ready. Tap Share to save to Files or send to another device."
                     : "Tap Share below and save the file to your project folder (e.g. Desktop/CraftManagement/PatternVault/) so the assistant can read it.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .multilineTextAlignment(.center)
                ShareLink(item: fileURL, preview: SharePreview(isUserBackup ? "corvidcraft_backup.json" : "uploaded_patterns.json", image: Image(systemName: "doc"))) {
                    Label("Share file", systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.sageGreen)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .padding(.horizontal, Theme.Spacing.xl)
            }
            .padding(Theme.Spacing.xl)
            .navigationTitle("Export ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { exportFileItem = nil }
                }
            }
        }
    }

    private func exportPatternsForDebugging() async {
        guard let userId = auth.currentUserId else { return }
        isExporting = true
        defer { isExporting = false }
        await store.load(userId: userId)
        let payload = DebugPatternExport.export(from: store.patterns)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let fileName = "uploaded_patterns.json"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        try? data.write(to: fileURL)
        exportFileItem = ExportFileItem(url: fileURL)
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Avatar circle with initial or mascot
            ZStack {
                Circle()
                    .fill(Theme.softCoral.opacity(0.12))
                    .frame(width: 64, height: 64)

                if let initial = userInitial {
                    Text(initial)
                        .font(Theme.Typography.titleBold)
                        .foregroundStyle(Theme.softCoral)
                } else {
                    SpriteMascotView.idle(size: 48)
                        .clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let name = auth.displayName {
                    Text(name)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.deepPlum)
                }

                if let email = auth.userEmail {
                    Text(email)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .borderedCard()
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Account")

            VStack(spacing: 0) {
                // Sign out
                Button { showSignOutConfirm = true } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.softCoral)
                            .frame(width: 22)
                        Text("Sign Out")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .settingsRowHitArea()
            }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign Out")
                .accessibilityHint("Signs out of your account")

                Divider()
                    .overlay(Theme.deepPlum.opacity(0.06))
                    .padding(.leading, 54)

                // Delete account
                Button { showDeleteConfirm = true } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Semantic.error.opacity(0.6))
                            .frame(width: 22)
                        Text("Delete Account")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Semantic.error.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete Account")
                .accessibilityHint("Permanently deletes your account and all data")
            }
            .borderedCard()
        }
    }

    // MARK: - Ravelry (connect account, import library)

    private var ravelrySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Ravelry")
            Text("Connect to import patterns, favorites, queue, and yarn stash from Ravelry.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))

            if let userId = auth.currentUserId {
                VStack(spacing: 0) {
                    if RavelryOAuthService.shared.isConnected(userId: userId) {
                        if let username = ravelryImportStore.ravelryUsername {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.sageGreen)
                                    .frame(width: 22)
                                Text("Connected as \(username)")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.deepPlum)
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.md)
                            .padding(.horizontal, Theme.Spacing.lg)
                            Divider().overlay(Theme.deepPlum.opacity(0.06)).padding(.leading, 54)
                        }
                        Button {
                            showRavelryImportConfirm = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                if ravelryImportStore.isImporting {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                        .frame(width: 22)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.sageGreen)
                                        .frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Import library, favorites, queue & stash")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.deepPlum)
                                    if ravelryImportStore.isImporting, ravelryImportStore.importProgressTotal > 0 {
                                        Text("\(ravelryImportStore.importProgressImported) of \(ravelryImportStore.importProgressTotal)")
                                            .font(Theme.Typography.caption2)
                                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                                    } else if let result = ravelryImportStore.lastImportResult {
                                        Text(result)
                                            .font(Theme.Typography.caption2)
                                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                                    }
                                }
                                Spacer()
                                if !ravelryImportStore.isImporting {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.deepPlum.opacity(0.2))
                                }
                            }
                            .padding(.vertical, Theme.Spacing.md)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .settingsRowHitArea()
                        }
                        .buttonStyle(.plain)
                        .disabled(ravelryImportStore.isImporting)
                        .accessibilityLabel("Import Ravelry library and stash")
                        Divider().overlay(Theme.deepPlum.opacity(0.06)).padding(.leading, 54)

                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dustyBlue)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle("Auto-sync daily", isOn: Binding(
                                    get: { ravelryImportStore.isAutoSyncEnabled },
                                    set: { ravelryImportStore.isAutoSyncEnabled = $0 }
                                ))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                                .tint(Theme.sageGreen)
                                if let lastSync = ravelryImportStore.lastSyncDate {
                                    Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                        .font(Theme.Typography.caption2)
                                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                                }
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .padding(.horizontal, Theme.Spacing.lg)
                        Divider().overlay(Theme.deepPlum.opacity(0.06)).padding(.leading, 54)

                        Button {
                            RavelryOAuthService.shared.disconnect(userId: userId)
                            ravelryImportStore.ravelryUsername = nil
                            ravelryImportStore.clearLastResult()
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "link")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.softCoral)
                                    .frame(width: 22)
                                Text("Disconnect Ravelry")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.softCoral)
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.md)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .settingsRowHitArea()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Disconnect Ravelry")
                    } else {
                        Button {
                            // Premium gate: Ravelry OAuth + bulk library import is a Premium-only feature.
                            if !SubscriptionStore.shared.isPremium {
                                paywallSource = .ravelryConnect
                                showPaywall = true
                                return
                            }
                            if !RavelryOAuthService.shared.isOAuthConfigured {
                                ravelryOAuthError = "Ravelry connection isn't available in this version. Please update the app to the latest version, or contact support if the problem continues."
                            } else {
                                Task {
                                    do {
                                        let url = try await startRavelryOAuthURL()
                                        guard let userId = auth.currentUserId else { return }
                                        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "corvidcraft") { [self] callbackURL, error in
                                            Task { @MainActor in
                                                if let error = error as? ASWebAuthenticationSessionError,
                                                   error.code == .canceledLogin || error.code == .presentationContextInvalid {
                                                    // canceledLogin: user dismissed the sheet
                                                    // presentationContextInvalid: onOpenURL already handled the callback
                                                    return
                                                }
                                                if let error = error {
                                                    // Don't overwrite success if onOpenURL path already connected
                                                    if RavelryOAuthService.shared.isConnected(userId: userId) { return }
                                                    ravelryOAuthError = error.localizedDescription
                                                    return
                                                }
                                                guard let callbackURL = callbackURL else { return }
                                                await processRavelryCallback(url: callbackURL, userId: userId)
                                            }
                                        }
                                        session.presentationContextProvider = RavelryAuthContextProvider.shared
                                        session.prefersEphemeralWebBrowserSession = false
                                        session.start()
                                    } catch {
                                        ravelryOAuthError = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "link")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.sageGreen)
                                    .frame(width: 22)
                                Text("Connect Ravelry")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.deepPlum)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.deepPlum.opacity(0.2))
                            }
                            .padding(.vertical, Theme.Spacing.md)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .settingsRowHitArea()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Connect Ravelry")
                    }
                }
                .borderedCard()
                if let err = ravelryImportStore.importError {
                    Text(err)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.softCoral)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
            }
        }
    }


    // MARK: - Duplicate patterns

    private var duplicatesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Duplicate patterns")
            NavigationLink {
                DuplicatesListView(store: store)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.softCoral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find duplicates")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.deepPlum)
                        Text("See patterns saved more than once and remove extras.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.3))
                }
                .padding(Theme.Spacing.md)
                .borderedCard()
                .settingsRowHitArea()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "About")

            VStack(spacing: 0) {
                aboutRow(icon: "info.circle", label: "Version", value: appVersion)

                Divider()
                    .overlay(Theme.deepPlum.opacity(0.06))
                    .padding(.leading, 54)

                aboutRow(icon: "hammer.fill", label: "Built with", value: "SwiftUI + Supabase")
                aboutRow(icon: "lock.shield.fill", label: "Your data", value: "Private & exportable")
            }
            .borderedCard()

            if !hasValidAIKeyConfigured {
                Text("Add GEMINI_API_KEY in Config to enable AI step analysis.")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    // MARK: - Celebrations (milestone toasts)

    private var celebrationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Celebrations")

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { celebrationStore.celebrationsEnabled },
                    set: { celebrationStore.celebrationsEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Milestone celebrations")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                        Text("Show a quick celebration when you hit a milestone")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    }
                }
                .tint(Theme.softCoral)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)

                let unlocked = CelebrationStore.knownMilestoneIds.filter { celebrationStore.unlockedMilestoneIds.contains($0) }
                if !unlocked.isEmpty {
                    Divider()
                        .overlay(Theme.deepPlum.opacity(0.06))
                        .padding(.leading, Theme.Spacing.lg)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Unlocked")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.top, Theme.Spacing.sm)
                        ForEach(unlocked, id: \.self) { milestoneId in
                            if let title = CelebrationStore.title(for: milestoneId) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.sageGreen)
                                    Text(title)
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.deepPlum)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                    }
                    .padding(.bottom, Theme.Spacing.sm)
                }
            }
            .borderedCard()
        }
    }

    // MARK: - Help (app tutorial)

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Help")

            VStack(spacing: 0) {
                Button {
                    tutorialStore.start()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dustyBlue)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show app tutorial")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            Text("Walk through the main screens again")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .settingsRowHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show app tutorial")
                .accessibilityHint("Walk through the main screens again")

                Divider()
                    .overlay(Theme.deepPlum.opacity(0.06))
                    .padding(.leading, 54)

                Button {
                    showMascotHelp = true
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.softCoral)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mascot interactions")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            Text("Learn Store, streaks, hearts, and treats")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .settingsRowHitArea()
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(Theme.deepPlum.opacity(0.06))
                    .padding(.leading, 54)

                Button {
                    showAIInfo = true
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.sageGreen)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How AI works in Corvid Craft")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            Text("What the AI does — and doesn't — do")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .settingsRowHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How AI works in Corvid Craft")
            }
            .borderedCard()
            .tutorialAnchor(.settingsTutorialRow, isActive: currentStepAnchor == .settingsTutorialRow)
        }
    }

    // MARK: - Legal (Privacy, Terms, Support)

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Legal")

            VStack(spacing: 0) {
                if let url = legalURL(for: "PrivacyPolicyURL") {
                    legalLinkRow(icon: "hand.raised.fill", label: "Privacy Policy", url: url)
                }
                if let url = legalURL(for: "TermsOfServiceURL") {
                    if legalURL(for: "PrivacyPolicyURL") != nil {
                        Divider()
                            .overlay(Theme.deepPlum.opacity(0.06))
                            .padding(.leading, 54)
                    }
                    legalLinkRow(icon: "doc.text.fill", label: "Terms of Service", url: url)
                }
                if let url = legalURL(for: "SupportURL") {
                    if legalURL(for: "PrivacyPolicyURL") != nil || legalURL(for: "TermsOfServiceURL") != nil {
                        Divider()
                            .overlay(Theme.deepPlum.opacity(0.06))
                            .padding(.leading, 54)
                    }
                    legalLinkRow(icon: "envelope.fill", label: "Contact & Support", url: url)
                }
            }
            .borderedCard()
        }
    }

    private var hasAnyLegalURL: Bool {
        legalURL(for: "PrivacyPolicyURL") != nil
            || legalURL(for: "TermsOfServiceURL") != nil
            || legalURL(for: "SupportURL") != nil
    }

    private func legalURL(for key: String) -> URL? {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty,
              let url = URL(string: value) else { return nil }
        return url
    }

    private func legalLinkRow(icon: String, label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dustyBlue)
                    .frame(width: 22)
                Text(label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.3))
            }
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.lg)
            .settingsRowHitArea()
        }
        .buttonStyle(.plain)
    }

    // MARK: - App Footer

    private var appFooter: some View {
        VStack(spacing: Theme.Spacing.md) {
            TappableMascotView(size: 72)

            Text("Corvid Craft")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.deepPlum.opacity(0.4))

            Text("Your craft companion")
                .font(Theme.Typography.captionSemibold)
                .foregroundStyle(Theme.deepPlum.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func aboutRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.dustyBlue)
                .frame(width: 22)
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
            Spacer()
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.4))
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var userInitial: String? {
        if let name = auth.displayName, let first = name.first {
            return String(first).uppercased()
        }
        if let email = auth.userEmail, let first = email.first {
            return String(first).uppercased()
        }
        return nil
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// True when Gemini API key is set and not a placeholder (so the wand can run). Used to show the Config hint when not configured.
    private var hasValidAIKeyConfigured: Bool {
        let g = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        let gemini = g?.trimmingCharacters(in: .whitespacesAndNewlines)
        func isValid(_ s: String?) -> Bool {
            guard let s, !s.isEmpty else { return false }
            if s == "placeholder" { return false }
            if s.lowercased().contains("your-") && s.lowercased().contains("-key-here") { return false }
            return true
        }
        return isValid(gemini)
    }
}

private extension View {
    func settingsRowHitArea() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

// MARK: - Ravelry OAuth presentation context

private final class RavelryAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = RavelryAuthContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene, windowScene.activationState == .foregroundActive else { continue }
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) { return key }
            if let first = windowScene.windows.first { return first }
        }
        if let anyWindowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let first = anyWindowScene.windows.first {
            return first
        }
        return ASPresentationAnchor()
    }
}

// MARK: - Testing export types

private struct ExportFileItem: Identifiable {
    let id = UUID()
    let url: URL
    var isUserBackup: Bool = false
}

/// Snapshot of patterns for debugging; written to JSON so the assistant can read uploaded patterns.
private struct DebugPatternExport: Encodable {
    let exportedAt: String
    let count: Int
    let patterns: [DebugPatternEntry]

    static func export(from patterns: [Pattern]) -> DebugPatternExport {
        let entries = patterns.map { DebugPatternEntry(from: $0) }
        return DebugPatternExport(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            count: entries.count,
            patterns: entries
        )
    }
}

private struct DebugPatternEntry: Encodable {
    let id: String
    let title: String
    let sourceUrl: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let patternDescriptionPreview: String?
    let sourceContentLength: Int?
    let sourceContentPreview: String?
    let sourcePlatform: String?
    let thumbnailUrl: String?
    let pdfUrl: String?

    init(from p: Pattern) {
        id = p.id.uuidString
        title = p.title
        sourceUrl = p.sourceUrl
        status = p.status.rawValue
        createdAt = ISO8601DateFormatter().string(from: p.createdAt)
        updatedAt = ISO8601DateFormatter().string(from: p.updatedAt)
        patternDescriptionPreview = p.patternDescription.map { String($0.prefix(300)) }
        sourceContentLength = p.sourceContent.map { $0.count }
        sourceContentPreview = p.sourceContent.map { String($0.prefix(500)) }
        sourcePlatform = p.sourcePlatform
        thumbnailUrl = p.thumbnailUrl
        pdfUrl = p.pdfUrl
    }
}
