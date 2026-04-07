# Pattern Vault Setup

Use this as the single setup checklist for local development, auth providers, and Supabase.

## 1) Local project setup

1. Open `PatternVault.xcodeproj` in Xcode.
2. Copy `Config/Config.xcconfig.example` to `Config/Config.xcconfig`.
3. Set at least:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `GEMINI_API_KEY` (required for AI analysis features)
4. Optional keys:
   - `RAVELRY_ACCESS_KEY` / `RAVELRY_PERSONAL_KEY` (Ravelry PDF + Find Patterns)
   - `RAVELRY_OAUTH2_CLIENT_ID` / `RAVELRY_OAUTH2_CLIENT_SECRET` (Connect Ravelry + library import)
   - Ad IDs and Firebase plist if using ads/analytics
5. Do not commit `Config/Config.xcconfig` (already gitignored).

## 2) Supabase project setup

### Auth

- Enable Email auth in Supabase Authentication > Providers.
- For quick local testing, optionally disable "Confirm email".
- Add redirect URL for app OAuth:
  - `patternvault://auth/callback` or the scheme currently configured in app Info settings.

### Database

Run migrations in `supabase_migrations/` in order (`001` through latest).

Current migrations in this repo (run in order):
- `001_create_patterns.sql`
- `002_create_project_notes.sql`
- `003_create_tags.sql`
- `004_add_pattern_metadata.sql`
- `005_create_pattern_images.sql`
- `006_add_pattern_pdf_and_metadata.sql`
- `007_pattern_pdfs_bucket.sql`
- `008_create_pattern_yarn_links.sql`
- `009_add_parsed_steps.sql`
- `010_crafter_features.sql`
- `011_tools_craft_agnostic.sql`
- `012_user_entitlements.sql`
- `013_app_config.sql`

### Storage

Create and verify `note-photos` bucket policies if not already set by your migration flow.

## 3) Apple and Google auth provider setup

### Apple

- Xcode target capability: Sign in with Apple.
- Supabase Apple provider enabled.
- Bundle ID matches Apple Client ID / app identifier.

### Google

- Create a Google OAuth Web client.
- Add Supabase callback URL in Google Cloud:
  - `https://<PROJECT_REF>.supabase.co/auth/v1/callback`
- Paste Web Client ID/Secret into Supabase Google provider settings.

## 4) Ravelry setup (optional)

### Personal API keys

Used for:
- Ravelry PDF lookup in share extension
- Find Patterns search

Set:
- `RAVELRY_ACCESS_KEY`
- `RAVELRY_PERSONAL_KEY`

### OAuth app

Used for:
- Settings > Connect Ravelry
- Import my Ravelry library

Set:
- `RAVELRY_OAUTH2_CLIENT_ID`
- `RAVELRY_OAUTH2_CLIENT_SECRET`

Recommended redirect URI:
- `patternvault://oauth/ravelry`

## 5) Quick smoke test

1. Launch app and sign up/sign in.
2. Add one pattern manually.
3. Add one note with a photo.
4. Run one AI step analysis (Gemini).
5. Open Settings and verify key feature sections load without config errors.

## 6) Edge Functions (required and optional)

Required for account deletion:

- `delete-account` (self-service in-app account + data deletion)

Optional legacy path:

- `extract-pattern-from-video` (legacy YouTube transcript pipeline)

Deploy from `PatternVault/`:

```bash
supabase functions deploy delete-account
supabase functions deploy extract-pattern-from-video
```

Notes:

- `delete-account` requires a signed-in user JWT and uses service-role admin deletion server-side.
- User-owned table rows are removed by existing `ON DELETE CASCADE` foreign keys.

## 7) Related docs

- `PatternVault/README.md`
- `PatternVault/docs/TESTING.md`
- `PatternVault/docs/LAUNCH.md`
- `PatternVault/DEPLOY_EDGE_FUNCTION.md` (legacy/optional edge function path)
