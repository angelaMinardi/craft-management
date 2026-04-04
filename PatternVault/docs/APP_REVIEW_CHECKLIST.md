# App Review Checklist (Pattern Vault)

Use this before every TestFlight/App Store submission to reduce rejection risk.
This checklist is aligned to the App Review Guidelines structure (Safety, Performance, Business, Design, Legal) and adapted to Pattern Vault's actual features.

Last reviewed against Apple guidelines update: 2026-02-06.

## Submission Readiness (Before You Submit)

- App build is release-candidate quality (no known crashers, no placeholder flows).
- All app metadata in App Store Connect is accurate and current:
  - Description
  - Screenshots/previews
  - Privacy nutrition labels
  - Age rating answers
  - Category and keywords
- Support URL, Privacy URL, and Terms URL resolve and match current legal text.
- Contact information is valid and monitored.
- Backend services are live during review:
  - Supabase project online
  - Required migrations applied through latest (`013_app_config.sql`)
  - Auth and storage policies verified
- App Review notes include:
  - Demo account credentials (or clear demo mode instructions)
  - Non-obvious feature explanations (Share Extension, AI parsing, Ravelry connect/import)
  - Any region/config conditional behavior
  - Optional SDK behavior (AdMob/Firebase) and when active
  - Use `docs/APP_REVIEW_NOTES_TEMPLATE.md` and fill all placeholders

## 1) Safety

### 1.1 Content Safety

- No offensive, discriminatory, sexual, violent, or exploitative content in seed/demo data.
- Marketing and in-app copy avoid harmful/reckless framing.

### 1.2 User-Generated Content Scope

- Confirm app does **not** expose public social feeds/chat/UGC communities requiring moderation stack.
- If any new UGC feature is added, include moderation controls before submission:
  - Filtering
  - Reporting
  - Blocking
  - Published contact path

### 1.5 Developer Information

- In-app support entry point is easy to find.
- Support URL includes a working contact channel.

### 1.6 Data Security

- Secrets are not hardcoded (`Config.xcconfig` only, not committed).
- Keychain/App Group/session handling verified for extension flows.
- No debug logging of tokens, personal data, or raw secrets in release build.

## 2) Performance

### 2.1 App Completeness

- Core flows work on-device (not simulator-only):
  - Sign up/sign in/sign out
  - Pattern CRUD
  - Notes + photo attachments
  - Share Extension URL/PDF save
  - AI step parsing (or graceful disabled messaging if kill switch off)
  - Ravelry connect/import (when configured)
- No placeholder UI text, dead buttons, or unfinished screens.
- All URLs in app and metadata are functional.

### 2.3 Accurate Metadata

- App metadata describes real functionality only (no future-only claims as present features).
- Screenshots show real in-app experience, not splash/login-only sequences.
- "What's New" lists meaningful feature changes for each release.
- Age rating aligns with actual content exposure risk.

### 2.4 Hardware/Resource Behavior

- App does not overheat device, aggressively drain battery, or run unrelated background work.
- Widgets/extensions are related to app functionality and not ad surfaces.

### 2.5 Platform/API Compliance

- Public Apple APIs only; no private API usage.
- Microphone/speech usage (voice row counter) has clear, accurate purpose strings.
- App extensions remain within extension guidelines and app-scoped purpose.
- Ads are in main app only (not in widgets/extensions/App Clips).

## 3) Business

### 3.1 Payments and Monetization

- Digital feature unlocks use in-app purchase/subscription where required.
- Subscription value proposition is clear in-app and in metadata.
- Free vs premium boundaries are transparent and non-deceptive.
- App does not force ratings/downloads/reviews for core functionality.

### 3.2 Business Integrity

- No misleading pricing, fake urgency, or manipulative paywall language.
- No chart/rating manipulation or incentivized review behavior.

## 4) Design

### 4.2 Minimum Functionality

- App delivers clear native utility beyond a wrapped website.
- Offline/error states are handled gracefully and legibly.
- Key user journeys are coherent without hidden prerequisites.

### 4.4 Extensions

- Share Extension behavior is clearly disclosed and testable by App Review.
- Extension does not include unrelated advertising/IAP behavior.

### 4.8 Login Services

- If third-party login methods are offered, Sign in with Apple parity requirements are satisfied.
- Account creation/sign-in choices are not misleading.

## 5) Legal & Privacy

### 5.1 Privacy Policy and Data Handling

- Privacy Policy link exists in App Store Connect and in-app.
- Policy explicitly covers:
  - Data collected
  - Uses of data
  - Third-party sharing/SDKs
  - Retention/deletion process
  - Contact method
- Terms and Privacy pages reflect current implementation (Gemini, optional AdMob/Firebase, etc.).
- In-app account deletion works end-to-end (Settings -> Account -> Delete Account).
- App Tracking Transparency is implemented if/when tracking is performed.
- Permission prompts are data-minimized and clearly justified.

### 5.2 Intellectual Property

- Rights confirmed for all icons, mascot art, screenshots, videos, and imported content usage.
- No Apple endorsement implication in copy or visuals.

## Pattern Vault Release Evidence Pack (attach/use in Review Notes)

- Demo account and password (or demo mode steps)
- Test matrix summary (device + iOS versions + key flows)
- Notes for conditional configs:
  - Ravelry keys present/missing behavior
  - AI kill switch behavior (`app_config.ai_enabled`)
  - AdMob/Firebase enabled vs disabled behavior
  - Account deletion function deployed and reachable (`delete-account`)
- Known limitations disclosed with mitigation/workaround
- Contact path for reviewer questions

## Fast Go/No-Go Gate

Ship only if all are true:

- No P0/P1 bugs in auth, save/import, purchase, or data-loss paths
- Metadata matches shipped binary behavior
- Legal URLs and policy text are current
- Reviewer can fully access app and test premium/locked flows
- Team can respond to App Review questions within 24 hours

