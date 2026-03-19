# Pattern Vault

Your personal craft pattern library for iOS — save patterns from Safari or any app, organize with tags and notes, and track progress.

## Docs Index

- `docs/SETUP.md` — environment, auth providers, Supabase migrations, and feature key setup
- `docs/TESTING.md` — canonical automated + manual regression checklist
- `docs/LAUNCH.md` — release readiness, launch day operations, and weekly post-launch checks
- `docs/ART_AND_BRANDING.md` — visual identity, color system, mascot usage, and marketing art direction
- `docs/MASCOT_ASSET_HANDOFF.md` — exact mascot file deliverables, naming, animation folders, and handoff checklist
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
