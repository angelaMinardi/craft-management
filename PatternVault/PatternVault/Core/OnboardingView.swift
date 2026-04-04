//
//  OnboardingView.swift
//  PatternVault
//
//  Multi-step onboarding: companion naming, notifications, craft selection,
//  stash & goals, personalized summary, and premium paywall.
//

import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("onboarding_companion_name") private var companionName = ""
    @AppStorage("onboarding_selected_crafts") private var selectedCraftsRaw = ""
    @AppStorage("onboarding_pattern_count") private var patternCountText = ""
    @AppStorage("onboarding_organizing_goal") private var organizingGoal = ""
    @AppStorage("onboarding_milestone_auth_required_shown") private var authRequiredShown = false

    @State private var currentPage = 0
    @State private var mascotBounce = false
    @State private var titleAppeared = false
    @State private var subtitleAppeared = false
    @State private var buttonAppeared = false
    @State private var isCelebrating = false
    @State private var isAnalyzing = false
    @State private var analysisProgress: CGFloat = 0
    @State private var showPaywall = false
    @State private var showDiscountOffer = false
    @State private var notificationStatus: String?
    @FocusState private var focusedField: Field?

    private let totalPages = 5

    private let craftOptions = ["Knitting", "Crochet", "Sewing", "Embroidery", "Quilting", "Weaving", "Macramé", "Cross Stitch"]

    private enum Field: Hashable {
        case companionName
        case patternCount
        case organizingGoal
    }

    // MARK: - Selected crafts helpers

    private var selectedCrafts: Set<String> {
        Set(selectedCraftsRaw.split(separator: ",").map { String($0) })
    }

    private func toggleCraft(_ craft: String) {
        var crafts = selectedCrafts
        if crafts.contains(craft) {
            crafts.remove(craft)
        } else {
            crafts.insert(craft)
        }
        selectedCraftsRaw = crafts.sorted().joined(separator: ",")
    }

    private var isEditingField: Bool {
        focusedField != nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.warmCream.ignoresSafeArea()
            SparkleBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: progress + skip
                topBar

                TabView(selection: $currentPage) {
                    companionPage.tag(0)
                    notificationsPage.tag(1)
                    craftSelectionPage.tag(2)
                    stashGoalsPage.tag(3)
                    summaryPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentPage)
                .offset(y: isEditingField ? -56 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isEditingField)

                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Theme.softCoral : Theme.deepPlum.opacity(0.18))
                            .frame(width: index == currentPage ? 8 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.bottom, Theme.Spacing.lg)

                // Primary action button
                primaryButton
                    .padding(.bottom, Theme.Spacing.xxl + 8)
            }

            // Celebration overlay
            if isCelebrating {
                celebrationOverlay
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            if !SubscriptionStore.shared.isPremium {
                showDiscountOffer = true
            }
        }) {
            onboardingPaywallView
        }
        .sheet(isPresented: $showDiscountOffer) {
            discountOfferView
        }
        .onAppear {
            triggerPageAnimations()
            trackSlide(currentPage)
        }
        .onChange(of: currentPage) { _, newPage in
            focusedField = nil
            triggerPageAnimations()
            trackSlide(newPage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("Pattern Vault")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum.opacity(0.8))

            Spacer()

            // Pill progress bar
            Capsule()
                .fill(Theme.deepPlum.opacity(0.12))
                .frame(width: 72, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.softCoral)
                        .frame(width: 72 * progressFraction)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)
                }

            Spacer()

            Button("Skip") {
                withAnimation(.easeOut(duration: 0.25)) {
                    GrowthOrchestrator.shared.markOnboardingCompleted()
                    GrowthOrchestrator.shared.registerFrictionEvent(.interruptionHeavyFlow)
                    AnalyticsService.shared.track(.onboardingSkipped, properties: [
                        AnalyticsService.Property.stepIndex: "\(currentPage)"
                    ])
                    hasSeenOnboarding = true
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.deepPlum.opacity(0.6))
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Primary Button

    @ViewBuilder
    private var primaryButton: some View {
        if currentPage == totalPages - 1 {
            // Summary page — "Finalize" button
            Button {
                HapticService.mediumImpact()
                startAnalysisAndFinish()
            } label: {
                Text(isAnalyzing ? "Analyzing..." : "Finalize")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.softCoral)
                    .clipShape(Capsule())
            }
            .buttonStyle(OnboardingButtonStyle())
            .padding(.horizontal, Theme.Spacing.xxl)
            .disabled(isAnalyzing)
            .opacity(isAnalyzing ? 0.7 : 1)
        } else if currentPage == 1 {
            // Notifications page — two buttons
            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    requestNotifications()
                } label: {
                    Text("Allow")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.softCoral)
                        .clipShape(Capsule())
                }
                .buttonStyle(OnboardingButtonStyle())
                .padding(.horizontal, Theme.Spacing.xxl)

                Button {
                    advanceToNextPage()
                } label: {
                    Text("Not Now")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                }
            }
        } else {
            Button {
                advanceToNextPage()
            } label: {
                HStack(spacing: 6) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, 16)
                .background(Theme.softCoral)
                .clipShape(Capsule())
            }
            .buttonStyle(OnboardingButtonStyle())
        }
    }

    // MARK: - Page 0: Meet Your Crafting Companion

    private var companionPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 16)

            // Mascot in nest
            mascotHero(size: 176, style: .waving)
                .frame(height: 200)

            Spacer().frame(height: Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.md) {
                Text("Meet Your Crafting\nCompanion.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .offset(y: titleAppeared ? 0 : 16)
                    .opacity(titleAppeared ? 1 : 0)

                Text("Hello! I'm here to help you get organized. What should we name me?")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .offset(y: subtitleAppeared ? 0 : 12)
                    .opacity(subtitleAppeared ? 1 : 0)
            }

            TextField("Your Companion's Name", text: $companionName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focusedField, equals: .companionName)
                .onSubmit { focusedField = nil }
                .foregroundStyle(Theme.deepPlum)
                .tint(Theme.deepPlum)
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .stroke(Theme.deepPlum.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)

            Spacer()
        }
    }

    // MARK: - Page 1: Companion Named + Notifications

    private var notificationsPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 16)

            mascotHero(size: 150, style: .idle)
                .frame(height: 180)

            VStack(spacing: Theme.Spacing.md) {
                Text("Companion Named!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .offset(y: titleAppeared ? 0 : 16)
                    .opacity(titleAppeared ? 1 : 0)

                if !companionName.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Love Your Companion?")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.7))
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.honey)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
                    )
                }

                Text("It's time for some details!")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
                    .offset(y: subtitleAppeared ? 0 : 12)
                    .opacity(subtitleAppeared ? 1 : 0)
            }

            Spacer().frame(height: Theme.Spacing.xl)

            // Notifications card
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.softCoral)
                    Text("Allow Notifications")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                }

                Text("Framed reminders for a helpful nudge, not an annoyance!")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.xl)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.xl)

            if let status = notificationStatus {
                Text(status)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.sageGreen)
                    .padding(.top, Theme.Spacing.sm)
            }

            Spacer()
        }
    }

    // MARK: - Page 2: Tell Us About Your Craft

    private var craftSelectionPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 16)

            mascotHero(size: 140, style: .thinking)
                .frame(height: 170)

            VStack(spacing: Theme.Spacing.md) {
                Text("Tell Us About\nYour Craft.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .multilineTextAlignment(.center)
                    .offset(y: titleAppeared ? 0 : 16)
                    .opacity(titleAppeared ? 1 : 0)

                // Craft chips
                FlowLayout(spacing: Theme.Spacing.sm) {
                    ForEach(craftOptions, id: \.self) { craft in
                        Button {
                            HapticService.lightImpact()
                            toggleCraft(craft)
                        } label: {
                            Text(craft)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedCrafts.contains(craft) ? .white : Theme.deepPlum)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(selectedCrafts.contains(craft) ? Theme.deepPlum : Theme.cardBackground)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(selectedCrafts.contains(craft) ? Color.clear : Theme.deepPlum.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .offset(y: subtitleAppeared ? 0 : 12)
                .opacity(subtitleAppeared ? 1 : 0)

                Text("This helps us surface the tools you are most likely to use first.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
        }
    }

    // MARK: - Page 3: Your Stash & Goals

    private var stashGoalsPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 16)

            mascotHero(size: 140, style: .knitting)
                .frame(height: 170)

            VStack(spacing: Theme.Spacing.md) {
                Text("Your Stash & Goals.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .offset(y: titleAppeared ? 0 : 16)
                    .opacity(titleAppeared ? 1 : 0)

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How many patterns do you have?")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                        TextField("1", text: $patternCountText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .patternCount)
                            .foregroundStyle(Theme.deepPlum)
                            .tint(Theme.deepPlum)
                            .padding(14)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .stroke(Theme.deepPlum.opacity(0.1), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your organizing goal?")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                        TextField("Get my yarn under control", text: $organizingGoal)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .organizingGoal)
                            .onSubmit { focusedField = nil }
                            .foregroundStyle(Theme.deepPlum)
                            .tint(Theme.deepPlum)
                            .padding(14)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .stroke(Theme.deepPlum.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .offset(y: subtitleAppeared ? 0 : 12)
                .opacity(subtitleAppeared ? 1 : 0)

                Text("Knowing your stash helps us personalize your vault.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
        }
    }

    // MARK: - Page 4: Summary / Almost Ready

    private var summaryPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 16)

            if isAnalyzing {
                // Analyzing state
                VStack(spacing: Theme.Spacing.xl) {
                    Text("Your Vault is\nAlmost Ready!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .multilineTextAlignment(.center)

                    Text("Analyzing your craft preferences...")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))

                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Theme.deepPlum.opacity(0.1), lineWidth: 6)
                            .frame(width: 80, height: 80)
                        Circle()
                            .trim(from: 0, to: analysisProgress)
                            .stroke(Theme.sageGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: analysisProgress)
                    }

                    mascotHero(size: 120, style: .thinking)
                }
            } else {
                mascotHero(size: 140, style: .knitting)
                    .frame(height: 170)

                VStack(spacing: Theme.Spacing.md) {
                    Text("Your Vault & Goals!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .offset(y: titleAppeared ? 0 : 16)
                        .opacity(titleAppeared ? 1 : 0)

                    Text("Analyzing your craft preferences...")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        .offset(y: subtitleAppeared ? 0 : 12)
                        .opacity(subtitleAppeared ? 1 : 0)

                    // Summary bullets
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        summaryRow(label: "Companion's Name", value: displayCompanionName)
                        summaryRow(label: "Favorite Craft", value: displayCrafts)
                        summaryRow(label: "Current Stash Size", value: displayPatternCount)
                        summaryRow(label: "Organizing Goal", value: displayGoal)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .offset(y: subtitleAppeared ? 0 : 12)
                    .opacity(subtitleAppeared ? 1 : 0)
                }
            }

            Spacer()
        }
    }

    // MARK: - Celebration Overlay

    private var celebrationOverlay: some View {
        ZStack {
            Theme.warmCream.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Text("Your Companion Named.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)

                SpriteMascotView.jumping(size: 200) {
                    // After jump, show paywall or finish
                    isCelebrating = false
                    showPaywall = true
                }

                if !displayCompanionName.isEmpty {
                    Text(displayCompanionName)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.softCoral)
                }

                Spacer()
            }
        }
    }

    // MARK: - Onboarding Paywall

    private var onboardingPaywallView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // Hero
                    VStack(spacing: Theme.Spacing.md) {
                        mascotHero(size: 120, style: .idle)

                        Text("Unlock Pattern\nVault Premium.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.lg)

                    // Annual plan card
                    VStack(spacing: Theme.Spacing.md) {
                        Text("Annual Plan")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.deepPlum)

                        Text("Full access to Pattern Vault Premium")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))

                        Text("$19.99/year")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.xl)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                            .stroke(Theme.softCoral, lineWidth: 2)
                    )
                    .padding(.horizontal, Theme.Spacing.lg)

                    Text("Cancel anytime. Get all features!")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Benefits
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        onboardingBenefitRow("Unlimited Pattern Storage")
                        onboardingBenefitRow("Tool Inventory Tracker")
                        onboardingBenefitRow("Stash Organizer with Image Recognition")
                        onboardingBenefitRow("Ad-Free Experience")
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    // Subscribe button
                    Button {
                        Task {
                            let yearly = SubscriptionStore.shared.products.first { $0.id == SubscriptionStore.yearlyProductId }
                            if let product = yearly {
                                let success = await SubscriptionStore.shared.purchase(product)
                                if success {
                                    showPaywall = false
                                    finishOnboarding()
                                }
                            }
                        }
                    } label: {
                        Text("Subscribe")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.softCoral)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(OnboardingButtonStyle())
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.md)
                }
                .padding(.bottom, 40)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showPaywall = false
                    } label: {
                        HStack(spacing: 4) {
                            Text("Close")
                                .font(Theme.Typography.caption)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                        }
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    }
                }
            }
        }
        .task {
            await SubscriptionStore.shared.refreshProducts()
        }
    }

    // MARK: - Discount Offer (shown after paywall dismiss)

    private var discountOfferView: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                mascotHero(size: 100, style: .waving)

                Text("Wait,\nDon't Miss Out.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .multilineTextAlignment(.center)

                // Discount badge
                Text("60% OFF")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Theme.softCoral)
                    .clipShape(Capsule())

                Text("$7.99 for your first year")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))

                Button {
                    // Attempt yearly purchase (discounted via intro offer in StoreKit config)
                    Task {
                        let yearly = SubscriptionStore.shared.products.first { $0.id == SubscriptionStore.yearlyProductId }
                        if let product = yearly {
                            let success = await SubscriptionStore.shared.purchase(product)
                            if success {
                                showDiscountOffer = false
                                finishOnboarding()
                            }
                        }
                    }
                } label: {
                    Text("Redeem Offer")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.softCoral)
                        .clipShape(Capsule())
                }
                .buttonStyle(OnboardingButtonStyle())
                .padding(.horizontal, Theme.Spacing.xxl)

                Button {
                    showDiscountOffer = false
                    finishOnboarding()
                } label: {
                    Text("Continue to Free Version")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.softCoral)
                }

                Spacer()
            }
            .background(Theme.screenGradient.ignoresSafeArea())
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Helpers

    private enum OnboardingMascotStyle {
        case waving
        case thinking
        case idle
        case knitting
    }

    private func mascotHero(size: CGFloat, style: OnboardingMascotStyle = .waving) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large * 2)
                .fill(Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                .frame(width: size + 24, height: size + 24)

            Group {
                switch style {
                case .waving:
                    SpriteMascotView.waving(size: size)
                case .thinking:
                    SpriteMascotView.thinking(size: size)
                case .idle:
                    SpriteMascotView.idle(size: size)
                case .knitting:
                    SpriteMascotView.knitting(size: size)
                }
            }
            .scaleEffect(mascotBounce ? 1 : 0.7)
            .opacity(mascotBounce ? 1 : 0)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text("• \(label):")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.7))
            Text(value.isEmpty ? "—" : value)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum)
                .lineLimit(1)
        }
    }

    private func onboardingBenefitRow(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.sageGreen)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
        }
    }

    private var displayCompanionName: String {
        let name = companionName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Sprite" : name
    }

    private var displayCrafts: String {
        let crafts = selectedCrafts.sorted()
        if crafts.isEmpty { return "Not set" }
        return crafts.joined(separator: ", ")
    }

    private var displayPatternCount: String {
        patternCountText.isEmpty ? "0" : patternCountText
    }

    private var displayGoal: String {
        organizingGoal.trimmingCharacters(in: .whitespaces).isEmpty ? "Not set" : organizingGoal
    }

    private var progressFraction: CGFloat {
        CGFloat(currentPage + 1) / CGFloat(totalPages)
    }

    private func advanceToNextPage() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationStatus = granted ? "Notifications enabled ✓" : "You can enable later in Settings"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    advanceToNextPage()
                }
            }
        }
    }

    private func startAnalysisAndFinish() {
        isAnalyzing = true
        analysisProgress = 0

        // Simulate analysis progress
        let steps: [(delay: Double, progress: CGFloat)] = [
            (0.3, 0.2), (0.8, 0.45), (1.3, 0.7), (1.8, 0.9), (2.3, 1.0)
        ]
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
                withAnimation { analysisProgress = step.progress }
            }
        }

        // Show celebration after analysis
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            isAnalyzing = false
            isCelebrating = true
        }
    }

    private func finishOnboarding() {
        authRequiredShown = true
        GrowthOrchestrator.shared.markOnboardingCompleted()
        GrowthOrchestrator.shared.registerPositiveEvent(.onboardingComplete)
        hasSeenOnboarding = true
    }

    private func triggerPageAnimations() {
        mascotBounce = false
        titleAppeared = false
        subtitleAppeared = false
        buttonAppeared = false

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.08)) {
            mascotBounce = true
        }
        withAnimation(.easeOut(duration: 0.38).delay(0.22)) {
            titleAppeared = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.42)) {
            subtitleAppeared = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.58)) {
            buttonAppeared = true
        }
    }

    private func trackSlide(_ page: Int) {
        AnalyticsService.shared.track(.onboardingSlideViewed, properties: [
            AnalyticsService.Property.stepIndex: "\(page)"
        ])
    }
}

// MARK: - Button style (subtle press)

private struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
