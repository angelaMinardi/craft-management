# Corvid Craft

Your personal craft pattern library for iOS — save patterns from Safari or any app, organize with tags and notes, and track progress.

## Docs Index

- `docs/SETUP.md` — environment, auth providers, Supabase migrations, and feature key setup
- `docs/TESTING.md` — canonical automated + manual regression checklist
- `docs/LAUNCH.md` — release readiness, launch day operations, and weekly post-launch checks
- `docs/APP_REVIEW_CHECKLIST.md` — Apple App Review pre-submit checklist tailored to Corvid Craft
- `docs/APP_REVIEW_NOTES_TEMPLATE.md` — copy/paste App Store Connect Notes for Review template
- `docs/ROADMAP.md` — shipped features, near-term roadmap, and future directions
- `docs/ACQUISITION_KEYWORD_MAP.md` — intent-cluster keyword strategy tied to onboarding and first-session wins
- `docs/ACQUISITION_MASTER_INDEX.md` — role-based reading paths and canonical source-of-truth map for acquisition docs
- `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md` — paid/ASO taxonomy, attribution confidence rules, and compliance preflight gate
- `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md` — ICE/RICE-prioritized experiment registry with stop-loss guardrails
- `docs/ACQUISITION_CREATIVE_BRIEFS.md` — creative family templates mapped to in-app moments and first-win workflows
- `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md` — confidence-tiered weekly scorecard for channel-quality decisions
- `docs/ACQUISITION_CROSS_POD_HANDOFFS.md` — ownership boundaries and checklist for Acquisition -> product pod handoffs
- `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md` — source-of-truth matrix for ad/store/onboarding/paywall/web message continuity
- `docs/ACQUISITION_WEEKLY_OPERATING_RHYTHM.md` — weekly execution cadence, governance, and stop-loss operations
- `docs/ACQUISITION_POD_KICKOFF_PACKET.md` — first-two-weeks startup packet with owners, cadence, and definition of done
- `docs/ART_AND_BRANDING.md` — visual identity, color system, mascot usage, and marketing art direction
- `docs/MASCOT_ASSET_HANDOFF.md` — exact mascot file deliverables, naming, animation folders, and handoff checklist
- `docs/ARTIST_CREATIVE_BRIEF.md` — artist kickoff brief with emotional arc, brand guardrails, and prioritized scope
- `docs/ARTIST_STYLE_FRAME_REVIEW.md` — scoring rubric and direction-lock process for initial style frames
- `docs/ARTIST_CORE_ASSET_PRODUCTION_SPEC.md` — production spec for mascot expression kit and onboarding scene pack
- `docs/ARTIST_GROWTH_WEB_ASSET_SHOTLIST.md` — growth, recovery, share-card, and website illustration shot list
- `docs/ARTIST_ASSET_INDEX_TEMPLATE.csv` — tracking template for asset naming, states, exports, and ownership
- `docs/ARTIST_INTEGRATION_QA.md` — import validation, UI-fit checks, performance budgets, and final signoff process
- `DEPLOY_EDGE_FUNCTION.md` — legacy/optional YouTube transcript edge-function deployment path

## Build

1. Open `PatternVault.xcodeproj` in Xcode.
2. **Config:** Copy `Config/Config.xcconfig.example` to `Config/Config.xcconfig`. Set:
   - `SUPABASE_URL` — your Supabase project URL
   - `SUPABASE_ANON_KEY` — your Supabase anon/public key
   - `GEMINI_API_KEY` (for AI analysis features)
   - Optionally: `RAVELRY_ACCESS_KEY` / `RAVELRY_PERSONAL_KEY` (for Ravelry PDF in Share Extension and Find Patterns)
3. Do **not** commit `Config/Config.xcconfig` (it is gitignored).
4. Build and run (⌘R). Use an iOS Simulator or a device.

## Tests

Run unit tests in Xcode: **Product → Test** (⌘U). All tests should pass.

From the command line:

```bash
xcodebuild test -scheme PatternVault -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PatternVaultTests
```

## Before release (TestFlight / App Store)

- **Legal:** In `PatternVault/Info.plist`, replace placeholder URLs with your real links:
  - `PrivacyPolicyURL` (required for account-based apps)
  - `TermsOfServiceURL`, `SupportURL` (Support URL is often required)
- **Config:** Ensure `Config/Config.xcconfig` has production Supabase and optional API keys. Confirm Share Extension and Widget targets receive the same variables.
- **Version & build:** Set `CFBundleShortVersionString` and `CFBundleVersion` for the release.
- **App icon:** Verify `PatternVault/Assets.xcassets/AppIcon.appiconset` has all required sizes (Xcode can generate from a single 1024×1024 image).
- **Manual testing:** Complete the checklist in `docs/TESTING.md`.
- **Supabase:** Run required migrations in `supabase_migrations/` through latest and verify RLS.

See `docs/SETUP.md` and `docs/LAUNCH.md` for full release setup and launch guidance.
