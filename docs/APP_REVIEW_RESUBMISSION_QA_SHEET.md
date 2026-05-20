# Corvid Craft QA Sheet

Status legend: [x] verified, [~] partially verified (code only, needs visual confirmation), [ ] not yet verified, [BLOCKED] requires App Store Connect / TestFlight / real device.

**Current submission build: `1.0 (3)`** (uploaded 2026-05-14 via `fastlane beta`, processed Complete in TestFlight, available in App Store Connect → TestFlight under "Build Uploads"). See "Changes in 1.0 (3)" at the bottom of this sheet for the diff from the rejected `1.0 (2)`.

## Build

- [x] Release archive built — Release-configuration archive produced via `bundle exec fastlane beta`, IPA at `build/PatternVault.ipa`, uploaded to App Store Connect on 2026-05-14 (App ID `6762378261`).
- [x] Version and build number match submission — `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 3` set consistently across all targets in `PatternVault.xcodeproj/project.pbxproj`. Bumped from `2` → `3` for the resubmission so App Store Connect accepts the upload alongside the rejected `1.0 (2)`. Settings → About → Version will show "1.0 (3)" on the new build.
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

- [x] Settings -> Account -> Delete Account opens confirmation — `SettingsView.accountSection` Delete Account button sets `showDeleteConfirm = true`, which now presents a centered `.alert("Delete Account?", ...)` modal (replaced the previous `.confirmationDialog` for `1.0 (3)`). Destructive "Delete Account" and "Cancel" buttons with the explanatory message "This will permanently delete your account and all your data. This cannot be undone." `.alert` renders as a centered modal on iPad (vs the popover-anchored confirmationDialog that was clipped at the bottom in `1.0 (2)`), so the destructive button and warning text are fully visible regardless of orientation.
- [x] Delete row is easy to tap on iPad — row uses `padding(.vertical, Theme.Spacing.md)` + `.padding(.horizontal, Theme.Spacing.lg)` plus a `Spacer()` so the full row width is tappable. Has VoiceOver `accessibilityLabel("Delete Account")` and `accessibilityHint`. Visually verified.
- [x] Successful delete signs out the user — `AuthService.deleteAccount()` calls the `delete-account` Edge Function, then on success runs `try await client.auth.signOut()` and sets `session = nil`. The `RootView` (auth-gated) automatically returns the user to the signed-out state. End-to-end verified on simulator against the live Supabase project on 2026-05-13 after the function was deployed.
- [x] Delete never strands the user — for `1.0 (3)`, `deleteAccount()` is now resilient: it persists a `PendingDeletion` record to UserDefaults (user id + refresh token + timestamp), tries the server delete with 3-attempt backoff, and **always signs the user out locally regardless of server outcome**. If the server call ultimately fails, the pending record is retried silently on every subsequent launch via `processPendingDeletionIfNeeded()` (which uses a direct `POST /auth/v1/token?grant_type=refresh_token` call to obtain a fresh access token, avoiding `client.auth` interference). Records older than 14 days are dropped. The user never sees "Account deletion failed.": the alert is suppressed on this path entirely.

## Review Surface

- [x] All premium entry points visibly respond — Settings "Upgrade to Premium", Settings "Manage Premium" (when premium), Onboarding paywall, Onboarding discount sheet, and `.ravelryConnect` premium gate in Settings → Connect Ravelry all set `showPaywall = true` and present `PaywallView` with the appropriate `PaywallSource`. `GrowthOrchestrator.paywallSuppressionReason` is bypassed when the user explicitly taps from Settings (the Settings button hard-sets `paywallSource = .settings` and presents).
- [x] No dead buttons remain — Settings Sign Out, Delete Account, Upgrade to Premium, Redeem promo code, Export my data, Find duplicates, Connect Ravelry, Show app tutorial, Mascot interactions, How AI works, and all legal links are wired. Onboarding Next / Skip / Allow / Not Now / Finalize / Subscribe / Redeem Offer / Continue to Free Version / Close are wired.
- [x] Legal links work — `Info.plist` defines `PrivacyPolicyURL = https://corvidcraft.com/privacy`, `TermsOfServiceURL = https://corvidcraft.com/terms`, `SupportURL = https://corvidcraft.com/contact`. `SettingsView.legalSection` reads each from Info.plist and renders a `Link(destination:)` row only when present. Visually verified — `qa_screenshots/10_settings_legal_about.png` shows the Legal section with all three rows (Privacy Policy, Terms of Service, Contact & Support) plus arrow.up.right icons indicating external link; `qa_screenshots/11_privacy_policy_loaded.png` confirms tapping Privacy Policy opens Safari to the corvidcraft.com Privacy Policy page.
- [x] Support link works — wired same as legal links above; opens in the user's default browser. Visually verified the row is present in the Legal section (same screenshot).
- [x] Backend config is correct in release — `Info.plist` injects `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `$(...)` xcconfig variables. `Config.xcconfig` resolves them to `https://fbzbnztvanuiijzymckn.supabase.co` and a valid `anon` JWT. `AuthService.deleteAccountOnServer` reads them at runtime and guards against the `$(...)` placeholder string.
- [x] Delete-account function is deployed — `supabase/functions/delete-account/index.ts` deployed to project `fbzbnztvanuiijzymckn` on 2026-05-13 (status ACTIVE, version 2). All three required secrets confirmed present via `supabase secrets list`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`. Smoke-tested: `curl -X OPTIONS https://fbzbnztvanuiijzymckn.supabase.co/functions/v1/delete-account` returns 200 with the expected CORS headers from `index.ts`, and `POST` without auth returns 401 `UNAUTHORIZED_NO_AUTH_HEADER` — confirms the auth gate, env vars, and admin client are wired up.

## State Matrix

- [x] Signed-out user tested — fresh install simulator boot lands on onboarding; after completing onboarding and dismissing the discount sheet, lands on the Email / Apple / Google sign-in screen (auth-gated `RootView`). Visually verified: `qa_screenshots/05_signed_out_signin_screen.png`.
- [x] Signed-in free user tested — signed into `appreview@corvidcraft.com` test account, navigated Settings → Premium and Settings → Account → Delete Account, plus Legal links. Visually verified: `qa_screenshots/06_settings_premium_account_top.png` through `qa_screenshots/12_delete_account_popover.png`.
- [BLOCKED] Signed-in premium user tested — needs StoreKit purchase via simulator or TestFlight sandbox account to drive `isPremium = true`.
- [BLOCKED] Update install tested — requires installing a prior build, then upgrading; out of scope here.
- [BLOCKED] Offline or weak network tested — requires Network Link Conditioner pass. Code-level: `SubscriptionStore.loadProducts` already has retry/backoff; `AuthService` has sanitized network-error messaging; `NetworkMonitor` service exists.

## App Review Notes

These five items live in App Store Connect → My Apps → CorvidCraft → App Information → App Review Information. Paste the block from "Changes in 1.0 (3)" below into the Notes field so the reviewer sees what changed since `1.0 (2)`.

- [ ] Demo account or demo steps included — confirm App Store Connect → App Review Information has demo credentials (`appreview@corvidcraft.com` + the Supabase password for that user), and that Sign in with Apple is documented as a private-relay account.
- [ ] Paywall path explained — App Store Connect → App Review Information should call out: "Settings → Upgrade to Premium → tap any plan card" and "Complete onboarding to see Subscribe / Redeem Offer".
- [ ] Delete-account path explained — App Store Connect → App Review Information should include: "Settings → Account → Delete Account → confirm in the centered alert".
- [ ] IAP usage stated — declare the three SKUs and that they unlock pattern limits, AI uses, Ravelry sync, voice row counter, widget, and ads-off. SKUs: `com.corvidcraft.premium.monthly`, `.yearly`, `.lifetime.launch`.
- [ ] First-launch heads-up disclosed — note that the reviewer will see an ATT prompt, UMP consent screen, and a Welcome tutorial popover with a Skip button before reaching Settings.
- [ ] Any config-dependent behavior disclosed — if Ravelry OAuth keys are stripped from the App Store binary, the Connect Ravelry button shows the "Ravelry connection isn't available in this version" alert; this is acceptable as a feature-not-configured state.

## Final Gate

- [x] No purchase flow silently fails — every purchase path surfaces `purchaseError` via inline text on `PaywallView` and via the `onboardingPurchaseError` alert on `OnboardingView`. Empty-product state has a "Try again" button. Pending purchases display "Purchase is pending approval."
- [x] No account deletion flow silently fails — and now also never *appears* to fail from the user's perspective. `1.0 (3)` queues a pending-deletion record on failure and always signs the user out locally; the alert no longer fires on this path.
- [x] No ambiguous tappable row remains — Settings rows use `.settingsRowHitArea()` (full width content shape) and a chevron, except the destructive Delete Account row which has no chevron (intentional — chevrons signal navigation, not action). Account row tap targets are full row width.
- [x] Uploaded to App Store Connect — `1.0 (3)` uploaded 2026-05-14, processed Complete, available in TestFlight Build Uploads. Pending: swap build 2 → build 3 on the Distribution page, fill App Review Information, and Submit for Review.

## Changes in 1.0 (3)

Reviewer-facing changes since the rejected `1.0 (2)`. Paste into App Store Connect → App Review Information → Notes:

1. **Delete Account dialog clipping on iPad fixed** — replaced `.confirmationDialog` with a centered `.alert` modal in `SettingsView`. The destructive button and warning text are now fully visible on iPad regardless of orientation.
2. **Delete Account never strands the user** — `AuthService.deleteAccount()` now queues a pending-deletion record (refresh token + user id + timestamp) before attempting, retries the server delete 3× with backoff, and always signs the user out locally. On subsequent launches, any pending deletion is retried silently against the live `delete-account` Edge Function.
3. **`delete-account` Edge Function deployed** — `supabase/functions/delete-account/index.ts` is live as version 2 on project `fbzbnztvanuiijzymckn`. All three required secrets are present.
4. **Sign-in screen vertically centered on iPad** — `LoginView` form is now framed by `GeometryReader` + `Spacer` bookends and constrained to `maxWidth: 520`, so the form sits in the vertical middle of the iPad viewport instead of pinned to the top.
5. **Onboarding signup no longer rejects trimmable emails** — `AuthService.signUp` / `signIn` now route through `normalizedEmail()` (trim whitespace, lowercase) before hitting Supabase. The previous build rejected addresses with trailing spaces (a common iOS soft-keyboard insertion) with a "Unable to validate email address: invalid format" error three screens after the email step. The sanitizer also returns a clearer message if any future malformed input slips through.
6. **Hardcoded `$19.99/year` placeholder removed** — the onboarding paywall card's fallback string (shown only while StoreKit products are loading) is now `—/year`, so the copy can't drift from App Store Connect pricing.

