# Corvid Craft App Store Resubmission Checklist

Use this before reuploading Corvid Craft for App Store review. It is written against the rejection received on May 12, 2026:

- Guideline 2.1(a) Performance: App Completeness
- Guideline 3.1.1 Business: Payments - In-App Purchase

## 1. Build And Install

- Build the release archive you intend to submit.
- Install the archived build on a real iPad.
- Test a fresh install after deleting the app and its related data.
- Confirm the build number and version match the App Store Connect submission.

## 2. Purchase Flow

- Verify the onboarding `Subscribe` button responds immediately.
- Verify the onboarding `Redeem Offer` button responds immediately.
- Verify the Settings `Upgrade to Premium` and `Manage Premium` entry point opens the paywall.
- Verify the paywall loads products on a real device.
- Verify the paywall shows loading, error, and retry states if products fail to load.
- Verify the purchase buttons do not silently no-op if products are still loading.
- Verify restore purchases works.
- Verify premium state persists after relaunch.
- Verify no external checkout or non-IAP purchase path is visible anywhere in the app.
- Verify App Store Connect has the expected IAP products configured and attached to the app version.

## 3. Delete Account Flow

- Verify Settings -> Account -> Delete Account opens the confirmation dialog.
- Verify the full row is easy to tap on iPad.
- Verify a successful delete removes the user account and signs the user out.
- Verify a failed delete shows a visible error alert.
- Verify the delete-account edge function is deployed and reachable in production or review.

## 4. Completeness Checks

- Verify every premium entry point opens a visible response on iPad.
- Verify no button looks tappable but does nothing.
- Verify all legal links open correctly.
- Verify support/contact links work.
- Verify the app does not depend on simulator-only behavior.
- Verify backend config values in the release build are correct.
- Verify any feature that depends on remote config has a visible fallback state.

## 5. Device And State Matrix

- Free user, signed out
- Free user, signed in
- Premium user, signed in
- Fresh install
- Update over previous version
- Offline or poor network
- Review device class: iPad

## 6. Review Notes

- Include demo account credentials or explicit demo instructions.
- Tell App Review exactly where to find the paywall.
- Tell App Review exactly where to test delete account.
- State that premium purchase is handled with In-App Purchase.
- Mention any backend-dependent behavior that may be temporarily unavailable.

## 7. Go Or No-Go

- Go only if all purchase, delete-account, and legal/contact paths work on a real iPad in a release build.
- No-go if any purchase button, delete button, or premium entry point is silent or ambiguous.

