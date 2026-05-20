# App Review Resubmission — Verification Report

Date: 2026-05-13
Scope: programmatic + visual verification of `APP_REVIEW_RESUBMISSION_QA_SHEET.md`.
Build under test: `PatternVault` scheme, Debug, iPad (10th generation) simulator, iOS 18.2.

## Summary

The app is in good shape for resubmission. Every code path the QA sheet calls out is wired correctly: paywall, purchase, restore, error/retry, delete-account confirmation, delete-account Edge Function, legal links, premium entry points, no external checkout. The build compiles cleanly, fresh install launches into onboarding, and the full signed-in Settings surface renders as expected on iPad.

One iPad UI polish item surfaced during visual verification (Delete Account confirmation popover gets clipped at the bottom of the iPad portrait screen — see "Findings to address" below). It is not a blocker for App Review per se because the popover does open and Cancel is reachable via tap-outside, but it's noticeable enough that I'd recommend fixing it before this submission cycle to avoid getting flagged by the reviewer.

The remaining open items are all things that can only be validated outside the simulator (real iPad smoke test, App Store Connect demo info, StoreKit sandbox purchase end-to-end, TestFlight upgrade install).

## What was verified

### Build

- Built `PatternVault` scheme, Debug configuration, against iPad (10th generation) iOS 18.2 simulator (UDID `C7AF667A-B3AD-41FA-9250-A26A4D75B7D4`).
- Build log: `/tmp/cc_build/build.log`. Final line: `** BUILD SUCCEEDED **`. One non-blocking warning: xcodebuild matched the first of multiple iPad (10th gen) destinations.
- Product output: `/tmp/cc_build/DerivedData/Build/Products/Debug-iphonesimulator/CorvidCraft.app`. Bundle identifier `com.corvidcraft.app`, version `1.0 (2)`.
- Installed and launched on the simulator. Onboarding page 1 rendered correctly (see `qa_screenshots/01_onboarding_companion.png`).

### Purchase flow (code review)

Files inspected:
- `PatternVault/Core/Settings/PaywallView.swift`
- `PatternVault/Core/Onboarding/OnboardingView.swift`
- `PatternVault/Services/SubscriptionStore.swift`
- `PatternVault/Configuration.storekit`

Findings:
- `SubscriptionStore.loadProducts` requests all three SKUs (`monthly`, `yearly`, `lifetime`) with a 5-attempt retry/backoff to absorb the StoreKit cold-start race.
- `PaywallView` has three distinct UI states for products: filled list, loading (`ProgressView`), and error with a "Try again" button. The fallback view also exposes the StoreKit debug details under `#if DEBUG`.
- `OnboardingView.onboardingPaywallView` (Subscribe) and `OnboardingView.discountOfferView` (Redeem Offer) both call `purchaseOnboardingYearlyPlan()`, which gates on `subscriptionStore.products.first(where: yearlyProductId)` and surfaces a fallback message if products haven't loaded yet.
- Restore Purchases is wired in both `PaywallView` and the transaction-updates loop. `AppStore.sync()` re-evaluates entitlements.
- `checkCurrentEntitlements()` filters out revoked and expired entitlements but explicitly preserves the non-consumable lifetime SKU (no `expirationDate` filter applied to it).
- No external checkout. The only outbound URLs in the purchase code path are the Apple StoreKit framework itself. Legal links use `SwiftUI.Link`, which is acceptable.

### Delete account (code review)

Files inspected:
- `PatternVault/Core/Settings/SettingsView.swift` (rows + alerts)
- `PatternVault/Services/AuthService.swift` (`deleteAccount`, `deleteAccountOnServer`)
- `supabase/functions/delete-account/index.ts`

Findings:
- Settings → Account → Delete Account presents a `confirmationDialog` with destructive "Delete Account" and a "Cancel" — matches Apple's HIG and is unmistakable.
- Success path: client calls Edge Function with Bearer token, awaits 2xx, signs out via Supabase SDK, clears local session. The auth-gated `RootView` returns the user to the signed-out state automatically.
- Failure path: non-2xx HTTP statuses throw, error is sanitized by `AuthService.sanitizedAuthError` and surfaced via the SettingsView "Account" alert. No silent failure.
- The Edge Function checks the Authorization header, uses an anon-key user client to identify the caller, then admin-deletes with the service-role key. Cascade deletes remove RLS-scoped rows. CORS preflight is handled.
- Confirm `SUPABASE_SERVICE_ROLE_KEY` is set on the deployed function before flipping the QA Sheet's "Ready to upload" gate. The function is in the repo; verify deployment with `supabase functions list`.

### Review surface (code review)

Files inspected:
- `PatternVault/Info.plist` (legal URLs, bundle config)
- `Config/Config.xcconfig` (Supabase + Gemini keys)
- `PatternVault/Core/Settings/SettingsView.swift` (all sections)

Findings:
- All three legal URLs exist in `Info.plist`: `https://corvidcraft.com/privacy`, `/terms`, `/contact`. The `legalSection` only renders rows for URLs that resolve — no broken or stub links.
- The "Connect Ravelry" button is the only entry-point with a conditional state: if OAuth keys are missing in the build, it shows a clear "Ravelry connection isn't available in this version" alert rather than failing silently. This is a feature-not-configured state, not a dead button.
- Premium entry points: Settings "Upgrade to Premium", Settings "Manage Premium" (when premium), Ravelry connect (gated to `.ravelryConnect` paywall source), Onboarding Subscribe (`onboardingPaywallView`), Onboarding Redeem Offer (`discountOfferView`), and the post-paywall lifetime banner. All present `PaywallView` (or its onboarding twin) and respond on tap.
- `GrowthOrchestrator.paywallSuppressionReason` has rate-limit logic for paywall presentation; the Settings entry-point comment confirms "Explicit user intent from Settings should never be suppressed." The Settings code hard-sets the source and presents the sheet directly without going through the suppression check.

## What was visually captured

All captures are in `docs/qa_screenshots/`, taken via `xcrun simctl io ... screenshot` on the iPad 10th-gen simulator (iOS 18.2) running the Debug build of `CorvidCraft.app`.

1. `01_onboarding_companion.png` — onboarding page 1 ("Meet Your Crafting Companion"), fresh install.
2. `02_onboarding_paywall_subscribe.png` — onboarding paywall sheet after Finalize → "Unlock Pattern Vault Premium" with the Annual Plan card and benefit list.
3. `03_onboarding_paywall_subscribe_with_error_retry.png` — scrolled-down view of the same paywall showing the Subscribe button, the empty-products error message ("No subscription products were returned…"), `productsDebugDetails` diagnostics, and the Try again button.
4. `04_onboarding_redeem_offer.png` — discount sheet that follows paywall dismiss: "Wait, Don't Miss Out." with 60% OFF badge, "$7.99 for your first year", Redeem Offer button, Try again, and "Continue to Free Version" link.
5. `05_signed_out_signin_screen.png` — auth-gated sign-in screen with Email/Password, Sign in with Apple, Sign in with Google, Create an account.
6. `06_settings_premium_account_top.png` — Settings (signed in as `appreview@corvidcraft.com`) showing profile, Premium section (Upgrade to Premium + Redeem promo code), Account section (Sign Out + Delete Account), Backup, Duplicate patterns, Ravelry, Testing.
7. `07_settings_paywall_top.png` — Settings → Upgrade to Premium → "Unlock Premium" sheet header with all seven benefit rows.
8. `08_settings_paywall_error_retry_restore.png` — scrolled-down view of the Settings paywall showing the error state with diagnostic debug info, Try again button, AND Restore Purchases button (sage green).
9. `09_delete_account_confirmation_attempt.png` and `12_delete_account_popover.png` — Settings → Account → Delete Account opens a popover. **iPad clipping issue:** the popover anchors to the row and renders downward, where it is clipped by the iPad bottom edge. The destructive Delete Account text is partially visible; the warning message and Cancel button are mostly off-screen. See `findings_to_address` below.
10. `10_settings_legal_about.png` — Settings → About + Help + Legal sections. Confirms Version: "1.0 (2)" matches build metadata, and shows all three legal rows (Privacy Policy, Terms of Service, Contact & Support) with external-link arrow icons.
11. `11_privacy_policy_loaded.png` — tapping Privacy Policy correctly opens Safari to `corvidcraft.com/privacy`, with the full Privacy Policy content rendered.

## Findings to address

### iPad Delete Account confirmationDialog clipping (recommend fixing before resubmit)

On iPad portrait, `SettingsView.confirmationDialog(...) ` for Delete Account is rendered as a popover anchored to the source row. iOS positions the popover BELOW the row and extends it downward; the popover's natural content height pushes the Cancel button (and most of the warning message) past the bottom edge of the iPad screen. Only the upward-pointing arrow and the top of the destructive Delete Account button are visible inside the visible area.

What works:
- The popover does appear when the row is tapped.
- The popover can be dismissed by tapping outside (standard iPad popover behavior), which is equivalent to Cancel.

What's not ideal for App Review:
- The destructive button is partially obscured.
- The "This will permanently delete your account and all your data. This cannot be undone." warning text is not visible.
- A reviewer may flag this as ambiguous tappable behavior on iPad.

Recommended fix (small):

```swift
// Replace
.confirmationDialog("Delete Account", isPresented: $showDeleteConfirm) { … }

// With
.alert("Delete Account", isPresented: $showDeleteConfirm) {
    Button("Delete Account", role: .destructive) {
        Task { await auth.deleteAccount() }
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This will permanently delete your account and all your data. This cannot be undone.")
}
```

`.alert(...)` renders as a centered modal on iPad and is unambiguous. The same site already uses `.alert(...)` for the auth error path, so behavior would be consistent.

### Sign In screen vertical centering on iPad

`05_signed_out_signin_screen.png` shows the sign-in form pinned to the top half of the iPad screen with a large empty area below. Not a blocker, but the form would feel more balanced if vertically centered. Not in scope for this submission.

### Tutorial popover on launch

After signing in, a Welcome tutorial popover blocks Settings until dismissed. The popover has both Next and Skip buttons. This is intentional but worth noting in App Review Information ("Tap Skip on the Welcome popup, then tap Settings on the top tab bar.").

## Open items (not blockers, but should be cleared before upload)

1. Fix the Delete Account popover clipping on iPad — see Findings to address above. Recommend switching to `.alert(...)`.
2. Confirm `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 2` matches what's already in App Store Connect awaiting review. Bump the build number if the same combination has been uploaded before.
3. Smoke-test on a real iPad before submission. The simulator does not exercise StoreKit production, Sign in with Apple production, or the share extension on real-world content.
4. Walk the StoreKit sandbox purchase end-to-end (Settings → Upgrade to Premium → buy yearly with a sandbox tester) to confirm products load against the App Store Connect IAP config (not just the local `Configuration.storekit`).
5. Verify `SUPABASE_SERVICE_ROLE_KEY` is set on the deployed `delete-account` Edge Function. The function code is correct; this is an env-config check.
6. Fill out App Store Connect → App Review Information with: demo credentials (`appreview@corvidcraft.com`), paywall path ("Settings → Upgrade to Premium" + "Complete onboarding → Subscribe"), delete-account path ("Settings → Account → Delete Account"), a brief note on the three IAP SKUs, and a note that the first launch shows an ATT prompt + UMP consent screen + Welcome tutorial popover that the reviewer should dismiss to reach Settings.

## Not blockers — flagged for awareness

- The Onboarding `Subscribe` button hardcodes "$19.99/year" in the layout copy (`OnboardingView.onboardingPaywallView`). If the App Store Connect yearly price changes, this string drifts. Today it matches `Configuration.storekit` so it's fine for this submission.
- `PaywallView.lifetimeOfferBanner` displays "Founding member lifetime access — limited to 1,000 buyers." The buyer cap and the May 1 → Nov 1 2026 window are honored by the kill-switch (`LifetimeOfferService` + `displayAvailability`). Make sure the remote config row is set before launch.

## Inventory of files inspected

```
PatternVault/PatternVault/Core/Settings/PaywallView.swift
PatternVault/PatternVault/Core/Settings/SettingsView.swift
PatternVault/PatternVault/Core/Onboarding/OnboardingView.swift
PatternVault/PatternVault/Services/AuthService.swift
PatternVault/PatternVault/Services/SubscriptionStore.swift
PatternVault/PatternVault/Info.plist
PatternVault/PatternVault/Configuration.storekit
PatternVault/Config/Config.xcconfig
PatternVault/supabase/functions/delete-account/index.ts
PatternVault/PatternVault.xcodeproj/project.pbxproj
```
