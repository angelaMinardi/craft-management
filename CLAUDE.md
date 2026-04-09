# Pattern Vault

## Project Overview

Primary product is an iOS craft pattern organizer (Swift/SwiftUI + Supabase).  
Repo also includes a separate static marketing/legal site in `website/`.

## Structure

- `PatternVault/PatternVault/` — Main app source (Models, Core/*, Services, Repositories)
  - `Core/Pattern/` — Pattern CRUD, detail, list, steps, charts, PDF viewer
  - `Core/Dashboard/` — Home dashboard
  - `Core/Tools/` — Yarn stash, needles/hooks
  - `Core/ProjectNotes/` — Project notes
  - `Core/Tags/` — Tag management
  - `Core/Discovery/` — Pattern search, duplicates
  - `Core/Settings/` — Settings, paywall
  - `Core/Onboarding/` — Onboarding, tutorials, widget onboarding
  - `Core/Mascot/` — Mascot views, story, animations
  - `Core/Rewards/` — Achievements, celebrations, daily rewards
  - `Core/Shared/` — Tab bar, layout helpers, web view, ads
- `PatternVault/SaveToPatternVault/` — iOS Share Extension (target: SaveToPatternVault)
- `PatternVault/supabase_migrations/` — SQL migrations (run manually in Supabase SQL Editor)
- `PatternVault/PatternVault.xcodeproj/` — Xcode project

## Architecture

- MVVM: Models → Repositories (Supabase queries) → Stores (@ObservableObject) → Views (SwiftUI)
- `SupabaseManager.client` singleton for all DB access
- Auth via `AuthService` as `@EnvironmentObject`
- User ID passed explicitly to repository/store methods (from `auth.currentUserId`)
- Repository insert/update payloads use inner `Encodable` structs with snake_case keys

## Code Patterns

- All repositories and stores are `@MainActor`
- Models use `CodingKeys` mapping camelCase ↔ snake_case
- Views get `store` as `@ObservedObject`, create child stores with `@StateObject`
- Use `.task {}` for initial data load, `.refreshable {}` for pull-to-refresh
- Supabase config loaded from Info.plist via Build Settings or xcconfig (never hardcoded)

## Database

- Backend: Supabase (PostgreSQL + Auth + Storage)
- All tables have RLS policies scoping data to `auth.uid() = user_id`
- Migrations are numbered and must run in order: 001_create_patterns, 002_create_project_notes, 003_create_tags, 004_add_pattern_metadata, 005_create_pattern_images, 006_add_pattern_pdf_and_metadata, 007_pattern_pdfs_bucket, 008_create_pattern_yarn_links, 009_add_parsed_steps, 010_crafter_features, 011_tools_craft_agnostic, 012_user_entitlements, 013_app_config, 018_add_enrichment_status
- Trigger function `public.set_updated_at()` shared across tables
- Storage bucket `note-photos` for photo uploads

## Share Extension

- Target: `SaveToPatternVault` (not `ShareExtension`)
- Uses raw URLSession REST API — no Supabase SDK (memory limit ~120MB)
- **Fast save + server enrichment:** Extension saves pattern with basic metadata (OG tags, page text, PDF text) immediately. AI analysis runs server-side via `enrich-pattern` Edge Function. Pattern shows "Processing…" in list/detail until enrichment completes.
- Pipeline: HTML fetch → WebContentExtractor → SupabaseExtensionClient.savePattern (enrichment_status=pending) → fire-and-forget enrich-pattern Edge Function
- Enrichment Edge Function (supabase/functions/enrich-pattern): reads pattern's source_content, calls Gemini 2.5 Flash, updates metadata/steps/cleaned_content, sets enrichment_status to complete/failed. Requires `GEMINI_API_KEY` secret.
- Page text extraction limit: 10000 chars with smart truncation at paragraph breaks
- Fallback: when enrichment is skipped (AI limit/kill switch), raw `pageText` is saved as `source_content` with enrichment_status defaulting to 'complete'
- **Ravelry:** For `ravelry.com/patterns/...` URLs, RavelryPatternExtractor runs first: tries Ravelry API `pdf_url` (if RAVELRY_ACCESS_KEY/PERSONAL_KEY set), then scrapes page for PDF/download links, follows intermediate "Pattern Purchase" page to ravelrycache.com PDF. If no PDF found, falls back to WebContentExtractor with **Ravelry chrome filtered out** (nav/sidebar/footer); if saved content would be chrome-only, `source_content` is stored as nil. Main app hides Ravelry chrome in Pattern Content and steps (PatternStepParser.looksLikeRavelryChrome, PatternContentView effectiveContent). **Smart search (Find patterns):** Stash & Tools → Find patterns uses Ravelry pattern search API (RavelryPatternSearchService); same RAVELRY_ACCESS_KEY/PERSONAL_KEY. If keys are missing, the screen shows “Ravelry search not set up”.

## AI (pattern processing)

- **Provider:** Gemini 2.5 Flash only. Used in Share Extension (AIPatternAnalyzer) and main app (AIStepParserService). Cost-effective (~$0.10/M in, ~$0.40/M out), 1M context, `response_mime_type: application/json` for structured extraction. Free tier (rate-limited) for experimentation.
- **Config:** Set `GEMINI_API_KEY` in Config.xcconfig (from Config.xcconfig.example); never commit secrets.
- **Gemini API gotchas:** (1) `thinkingBudget: 0` required for small JSON responses — thinking tokens consume the output budget and truncate responses. (2) Use `x_min/y_min/x_max/y_max` coordinates, not "insets from edge" — the model returns coordinates from origin regardless of prompt wording. (3) Spatial precision ceiling is ~85-90% for bounding boxes; pixel-level analysis needed for the last mile.

## Theme System (`Theme.swift`)

- Brand colors: warmCream, softCoral, deepPlum, sageGreen, dustyBlue, honey
- Typography: all `.rounded` design system fonts
- Card modifiers: `.cardStyle()`, `.borderedCard()`, `.accentBorderedCard()`
- Reusable components: `SectionHeaderView`, `StatusBadge`, `SpriteMascotView`
- Staggered entrance animation: `.staggeredAppear(index:)`
- PatternCardView is shared between DashboardView and PatternListView — changes ripple to both

## Design checklist (app-wide consistency)

- Primary screens: use `Theme.screenGradient` or `Theme.warmCream` for background
- Primary actions: use `PrimaryButtonStyle()` or sage green filled buttons
- Empty/error states: use `SpriteMascotView` (idle, pouty, walking) plus Theme.Typography and brand colors
- Cards: use `.cardStyle()`, `.borderedCard()`, or `.accentBorderedCard()` as appropriate
- Share Extension: keep `ShareViewController` brand colors in sync with Theme.swift UIKit section (see comment in that file)

## Milestones

- 1 (Auth): Complete
- 2 (Patterns CRUD): Complete
- 3 (Project Notes): Complete
- 4 (Tags & Filters): Complete
- 5 (Share Extension): Complete (AI analysis, video/TikTok extraction, PDF, Ravelry)
- 6 (Polish): Complete — Dashboard, PatternCardView, Theme, PatternDetailView (empty states with mascot, Edit Steps, custom layout)

## Implemented (features)

- **Hands-free row counting (done):** VoiceRowService; tap Row in pattern detail, say row/round number; updates progress + note, speaks confirmation.
- **AI step parsing (done):** Two modes: (1) At import time — AIPatternAnalyzer prompt includes `steps` field, saved as `parsed_steps` JSON column in DB. (2) On-demand in main app — “Analyze Steps” wand button calls AIStepParserService (Gemini 2.5 Flash) to parse existing patterns. Step priority chain: CustomStepLayout (user-edited) > AI parsed_steps > PatternStepParser (heuristic). Migration: 009_add_parsed_steps. New file: AIStepParserService.swift (main app Services).
- **Smart pattern search (done):** Stash & Tools → Find patterns. User enters or selects materials (yarn weight, needle/hook size, craft) from stash/tools or freeform; searches Ravelry via RavelryPatternSearchService; results can be opened in Safari or saved to vault (AddPatternView). Requires Ravelry API keys in Config.xcconfig for search; graceful message if not configured.
- **Ravelry account connect and import (done):** Settings → Ravelry. Users can connect their Ravelry account via OAuth 2.0 authorization code flow (RavelryOAuthService, KeychainHelper). Tokens stored in Keychain per app user. After connecting, “Import my Ravelry library” fetches the user’s pattern library (RavelryUserService), dedupes by source_url, and adds patterns via PatternStore. Requires a Ravelry OAuth app configured with redirect URI `patternvault://oauth/ravelry`. Config: `RAVELRY_OAUTH2_CLIENT_ID`, `RAVELRY_OAUTH2_CLIENT_SECRET`.

## Gotchas

- Create `Config/Config.xcconfig` from `Config.xcconfig.example` (set `GEMINI_API_KEY` for AI pattern analysis, and optionally Supabase keys); file is gitignored. Required for main app AI step parsing and Share Extension. For Ravelry: `RAVELRY_ACCESS_KEY`/`RAVELRY_PERSONAL_KEY` for PDF and Find patterns; `RAVELRY_OAUTH2_CLIENT_ID`/`RAVELRY_OAUTH2_CLIENT_SECRET` for “Connect Ravelry” and import library (OAuth app redirect URI: `patternvault://oauth/ravelry`).
- Git repo: `https://github.com/angelaMinardi/craft-management` — API keys use xcconfig variables (e.g. `$(GEMINI_API_KEY)`); never hardcode secrets in pbxproj.
- Share Extension and main app cannot share Swift files directly — types like `ExtractedContent` are defined in the extension target
- `pbxproj` edits: new files need PBXFileReference + PBXBuildFile + PBXGroup membership + PBXSourcesBuildPhase entry. IDs must be unique — reusing IDs from other entries causes "Cannot find type in scope" errors. Always `grep` the pbxproj for candidate IDs before adding.
- `ChartHighlight` grid inset clamp is 0.85 (was 0.45). The sum constraint (<0.9 on opposite sides) is in PatternStore.
- `createChartHighlights` is `async` — all call sites must use `await`. It runs AI second-pass grid detection via `ChartGridDetector`.
- `@ViewBuilder` functions: `if/else` variable assignments (not returning Views) cause "Type '()' cannot conform to 'View'" — extract to helper methods.
- `craft-management/` directory is dead (abandoned web app) — ignore it
- Xcode can hang if DerivedData is corrupted: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Fresh Supabase projects need all migrations (001-013) run in order before app works. For existing DBs missing newer columns/tables, run the missing migration files in order from `PatternVault/supabase_migrations/`.
- sudo commands don't work from Claude Code (no tty for password)
- `launch.json` configs are empty — no dev server (iOS-only project, use Xcode)

## Chart Extraction Pipeline

Two-pass AI detection: (1) Full-page Gemini pass detects charts, returns chart_crop + grid_boundary + rows/cols. (2) Focused second-pass (`ChartGridDetector`) sends cropped chart image to Gemini for precise grid cell boundary (x_min/y_min/x_max/y_max). Falls back to first-pass values, then formula heuristic.

Key files: `ChartGridDetector.swift` (AI second-pass), `PatternStore.swift:createChartHighlights` (async, priority chain), `GridAlignmentEditor.swift` (lasso + drag handles), `ChartHighlighterOverlayView.swift` (grid overlay rendering), `ChartHighlight.swift` (model, inset clamp 0.85).

Storage: File-based in `Application Support/ChartHighlights/` — JSON metadata + PNG image + drawing data as separate files per highlight. Auto-migrates from legacy UserDefaults on first launch.

