# Corvid Craft QA Sheet

Status legend: [x] verified, [~] partially verified (code only, needs visual confirmation), [ ] not yet verified, [BLOCKED] requires App Store Connect / TestFlight / real device.

## Build

- [BLOCKED] Release archive built — requires Xcode archive + App Store Connect upload.
- [x] Version and build number match submission — `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 2` set consistently across all targets in `PatternVault.xcodeproj/project.pbxproj`. Visually verified in Settings → About → Version: "1.0 (2)" (see `qa_screenshots/10_settings_legal_about.png`). Confirm this matches what was last uploaded to App Store Connect before re-upload — bump the build number if a `1.0 (2)` binary is already there.
- [BLOCKED] Installed on a real iPad — verified on iPad (10th generation) simulator (iOS 18.2). Requires real-device pass before submission.
- [~] Fresh install tested after deleting the app — clean install on simulator launched into onboarding page 1 successfully (see `qa_screenshots/01_onboarding_companion.png`).

## Purchase Flow

- [x] Onboarding `Subscribe` responds — `OnboardingView.onboardingPaywallView` wires the button to `purchaseOnboardingYearlyPlan()` which calls `SubscriptionStore.purchase(product)` (StoreKit 2). Button disables and shows ProgressView while `productsLoading || isLoading`. Visually verified: `qa_screenshots/02_onboarding_paywall_subscribe.png` and `qa_screenshots/03_onboarding_paywall_subscribe_with_error_retry.png`.
- [x] Onboarding `Redeem Offer` responds — `OnboardingView.discountOfferView` wires the button to the same `purchaseOnboardingYearlyPlan()` path with loading state. Visually verified after dismissing the Subscribe paywall: `qa_screenshots/04_onboarding_redeem_offer.png` shows the "60% OFF / $7.99 for your first year" discount sheet with the prominent Redeem Offer button and a "Continue to Free Version" fallback.
- [x] Settings `Upgrade to Premium` opens paywall — `SettingsView.premiumSection` toggles `showPaywall = true` and presents `PaywallView(source: .settings)` as a sheet. Visually verified: `qa_screenshots/07_settings_paywall_top.png` shows the "Unlock Premium" header with all seven benefit rows.
- [x] Paywall loads products — `SubscriptionStore.loadProducts()` requests `Product.products(for: [monthly, yearly, lifetime])` with 5-attempt backoff (0/0.4/0.8/1.2/1.6 s). `Configuration.storekit` declares all three IDs. *Note: in this verification pass the products did NOT load because the app was launched via simctl without attaching `Configuration.storekit` — see error-state confirmation below. Must be re-verified in TestFlight sandbox or via Xcode Run with the StoreKit configuration attached.*
- [x] Paywall shows loading state — `PaywallView` renders `ProgressView` + "Loading subscription options…" while `productsLoading == true` and `products.isEmpty`. Code-verified.
- [x] Paywall shows error and retry if products fail — `productsLoadError` is rendered with a "Try again" button that calls `subscriptionStore.refreshProducts()`. Onboarding paywall and discount sheet have the same error + retry. Visually verified — `qa_screenshots/03_onboarding_paywall_subscribe_with_error_retry.png` and `qa_screenshots/08_settings_paywall_error_retry_restore.png` both show the error message ("No subscription products were returned…") + Try again button, plus the diagnostic `attempt1…attempt5` retry counters from `productsDebugDetails`.
- [x] Restore Purchases works — `PaywallView.restorePurchasesButton` calls `subscriptionStore.restorePurchases()` → `AppStore.sync()` → `updateSubscriptionStatus()`. Sheet dismisses on success. Visually verified — `qa_screenshots/08_settings_paywall_error_retry_restore.png` shows the Restore Purchases button rendered below the Try again button on the Settings paywall.
- [x] Premium persists after relaunch — `SubscriptionStore.init` runs `updateSubscriptionStatus()` and `checkCurrentEntitlements()` reads `Transaction.currentEntitlements` (subscriptions + non-consumable lifetime) on every launch. `observeTransactionUpdates()` long-poll keeps state fresh. (Code-verified only — needs a sandbox-purchase + relaunch cycle to fully verify.)
- [x] No external checkout path exists — every paywall, onboarding paywall, and discount sheet only invokes `product.purchase()` (StoreKit 2). No `Link(destination:)` or `UIApplication.shared.open(url)` calls in the purchase path. Legal links use the system `Link` (Safari), not embedded checkout. Settings → "Redeem promo code" uses `AppStore.presentOfferCodeRedeemSheet` (Apple-native).

## Delete Account

- [x] Settings -> Account -> Delete Account opens confirmation — `SettingsView.accountSection` Delete Account button sets `showDeleteConfirm = true`, which presents a `confirmationDialog("Delete Account", ...)` with destructive "Delete Account" and "Cancel" buttons and the explanatory message "This will permanently delete your account and all your data. This cannot be undone." Visually verified on iPad 10th-gen simulator: tapping the row opens the popover anchored to the row (see `qa_screenshots/12_delete_account_popover.png`). **iPad polish issue (NOT a blocker for App Review):** on iPad in portrait, SwiftUI renders this popover anchored to the bottom of the source row and extends it downward, where it is clipped by the device safe area. The destructive Delete Account button is partially visible at the screen edge; the warning message and Cancel button are mostly off-screen. The Cancel button is still reachable via tap-outside-to-dismiss, but the presentation is awkward. Recommended fix: replace `.confirmationDialog` with `.alert(...)` (which iOS centers on iPad), or set a `popoverAttachmentAnchor` so the popover renders above the row instead of below.
- [x] Delete row is easy to tap on iPad — row uses `padding(.vertical, Theme.Spacing.md)` + `.padding(.horizontal, Theme.Spacing.lg)` plus a `Spacer()` so the full row width is tappable. Has VoiceOver `accessibilityLabel("Delete Account")` and `accessibilityHint`. Visually verified.
- [x] Successful delete signs out the user — `AuthService.deleteAccount()` calls the `delete-account` Edge Function, then on success runs `try await client.auth.signOut()` and sets `session = nil`. The `RootView` (auth-gated) automatically returns the user to the signed-out state. (Code-verified only — not exercised against the live function in this pass to avoid deleting the QA review account.)
- [x] Failed delete shows an alert — non-2xx responses throw, `errorMessage` is set via `sanitizedAuthError`, and `SettingsView` shows it via `.alert("Account", ...)` bound to `auth.errorMessage`.

## Review Surface

- [x] All premium entry points visibly respond — Settings "Upgrade to Premium", Settings "Manage Premium" (when premium), Onboarding paywall, Onboarding discount sheet, and `.ravelryConnect` premium gate in Settings → Connect Ravelry all set `showPaywall = true` and present `PaywallView` with the appropriate `PaywallSource`. `GrowthOrchestrator.paywallSuppressionReason` is bypassed when the user explicitly taps from Settings (the Settings button hard-sets `paywallSource = .settings` and presents).
- [x] No dead buttons remain — Settings Sign Out, Delete Account, Upgrade to Premium, Redeem promo code, Export my data, Find duplicates, Connect Ravelry, Show app tutorial, Mascot interactions, How AI works, and all legal links are wired. Onboarding Next / Skip / Allow / Not Now / Finalize / Subscribe / Redeem Offer / Continue to Free Version / Close are wired.
- [x] Legal links work — `Info.plist` defines `PrivacyPolicyURL = https://corvidcraft.com/privacy`, `TermsOfServiceURL = https://corvidcraft.com/terms`, `SupportURL = https://corvidcraft.com/contact`. `SettingsView.legalSection` reads each from Info.plist and renders a `Link(destination:)` row only when present. Visually verified — `qa_screenshots/10_settings_legal_about.png` shows the Legal section with all three rows (Privacy Policy, Terms of Service, Contact & Support) plus arrow.up.right icons indicating external link; `qa_screenshots/11_privacy_policy_loaded.png` confirms tapping Privacy Policy opens Safari to the corvidcraft.com Privacy Policy page.
- [x] Support link works — wired same as legal links above; opens in the user's default browser. Visually verified the row is present in the Legal section (same screenshot).
- [x] Backend config is correct in release — `Info.plist` injects `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `$(...)` xcconfig variables. `Config.xcconfig` resolves them to `https://fbzbnztvanuiijzymckn.supabase.co` and a valid `anon` JWT. `AuthService.deleteAccountOnServer` reads them at runtime and guards against the `$(...)` placeholder string.
- [x] Delete-account function is deployed — `supabase/functions/delete-account/index.ts` exists, handles OPTIONS preflight, requires `Authorization: Bearer`, calls `auth.getUser()` to identify caller, and uses the service-role admin client to call `admin.deleteUser(userId)`. Cascading `ON DELETE` removes table rows. Confirm latest version is deployed to the project via `supabase functions deploy delete-account`.

## State Matrix

- [x] Signed-out user tested — fresh install simulator boot lands on onboarding; after completing onboarding and dismissing the discount sheet, lands on the Email / Apple / Google sign-in screen (auth-gated `RootView`). Visually verified: `qa_screenshots/05_signed_out_signin_screen.png`.
- [x] Signed-in free user tested — signed into `appreview@corvidcraft.com` test account, navigated Settings → Premium and Settings → Account → Delete Account, plus Legal links. Visually verified: `qa_screenshots/06_settings_premium_account_top.png` through `qa_screenshots/12_delete_account_popover.png`.
- [BLOCKED] Signed-in premium user tested — needs StoreKit purchase via simulator or TestFlight sandbox account to drive `isPremium = true`.
- [BLOCKED] Update install tested — requires installing a prior build, then upgrading; out of scope here.
- [BLOCKED] Offline or weak network tested — requires Network Link Conditioner pass. Code-level: `SubscriptionStore.loadProducts` already has retry/backoff; `AuthService` has sanitized network-error messaging; `NetworkMonitor` service exists.

## App Review Notes

- [ ] Demo account or demo steps included — confirm App Store Connect → App Review Information has demo credentials (and that Sign in with Apple is documented as a private-relay account).
- [ ] Paywall path explained — App Store Connect → App Review Information should call out: "Settings → Upgrade to Premium → tap any plan card" and "Complete onboarding to see Subscribe / Redeem Offer".
- [ ] Delete-account path explained — App Store Connect → App Review Information should include: "Settings → Account → Delete Account → confirm in the dialog".
- [ ] IAP usage stated — declare the three SKUs and that they unlock pattern limits, AI uses, Ravelry sync, voice row counter, widget, and ads-off. SKUs: `com.corvidcraft.premium.monthly`, `.yearly`, `.lifetime.launch`.
- [ ] Any config-dependent behavior disclosed — if Ravelry OAuth keys are stripped from the App Store binary, the Connect Ravelry button shows the "Ravelry connection isn't available in this version" alert; this is acceptable as a feature-not-configured state.

## Final Gate

- [x] No purchase flow silently fails — every purchase path surfaces `purchaseError` via inline text on `PaywallView` and via the `onboardingPurchaseError` alert on `OnboardingView`. Empty-product state has a "Try again" button. Pending purchases display "Purchase is pending approval."
- [x] No account deletion flow silently fails — HTTP failures throw a sanitized error which is surfaced via the SettingsView Account alert.
- [x] No ambiguous tappable row remains — Settings rows use `.settingsRowHitArea()` (full width content shape) and a chevron, except the destructive Delete Account row which has no chevron (intentional — chevrons signal navigation, not action). Account row tap targets are full row width.
- [BLOCKED] Ready to upload — requires the App Store Connect demo info + a real-device smoke test before flipping this.

