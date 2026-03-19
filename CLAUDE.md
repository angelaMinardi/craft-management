# Pattern Vault

## Project Overview

Primary product is an iOS craft pattern organizer (Swift/SwiftUI + Supabase).  
Repo also includes a separate static marketing/legal site in `website/`.

## Structure

- `PatternVault/PatternVault/` — Main app source (Models, Core, Services, Repositories)
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
- Migrations are numbered: 001_create_patterns, 002_create_project_notes, 003_create_tags
- Trigger function `public.set_updated_at()` shared across tables
- Storage bucket `note-photos` for photo uploads

## Share Extension

- Target: `SaveToPatternVault` (not `ShareExtension`)
- Uses raw URLSession REST API — no Supabase SDK (memory limit ~120MB)
- AI analysis: uses Gemini 2.0 Flash only (`GEMINI_API_KEY` in Config/Info.plist).
- Pipeline: HTML fetch → WebContentExtractor → AIPatternAnalyzer → SupabaseExtensionClient.savePattern
- `max_tokens` for AI call: 4096 (to accommodate `cleaned_content` and 12+ JSON fields)
- Page text extraction limit: 10000 chars with smart truncation at paragraph breaks
- Fallback: when AI fails, raw `pageText` is saved as `cleanedContent`
- **Ravelry:** For `ravelry.com/patterns/...` URLs, RavelryPatternExtractor runs first: tries Ravelry API `pdf_url` (if RAVELRY_ACCESS_KEY/PERSONAL_KEY set), then scrapes page for PDF/download links, follows intermediate "Pattern Purchase" page to ravelrycache.com PDF. If no PDF found, falls back to WebContentExtractor with **Ravelry chrome filtered out** (nav/sidebar/footer); if saved content would be chrome-only, `source_content` is stored as nil. Main app hides Ravelry chrome in Pattern Content and steps (PatternStepParser.looksLikeRavelryChrome, PatternContentView effectiveContent). **Smart search (Find patterns):** Stash & Tools → Find patterns uses Ravelry pattern search API (RavelryPatternSearchService); same RAVELRY_ACCESS_KEY/PERSONAL_KEY. If keys are missing, the screen shows “Ravelry search not set up”.

## AI (pattern processing)

- **Provider:** Gemini 2.0 Flash only. Used in Share Extension (AIPatternAnalyzer) and main app (AIStepParserService). Cost-effective (~$0.10/M in, ~$0.40/M out), 1M context, `response_mime_type: application/json` for structured extraction. Free tier (rate-limited) for experimentation.
- **Config:** Set `GEMINI_API_KEY` in Config.xcconfig (from Config.xcconfig.example); never commit secrets.

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
- **AI step parsing (done):** Two modes: (1) At import time — AIPatternAnalyzer prompt includes `steps` field, saved as `parsed_steps` JSON column in DB. (2) On-demand in main app — “Analyze Steps” wand button calls AIStepParserService (Gemini 2.0 Flash) to parse existing patterns. Step priority chain: CustomStepLayout (user-edited) > AI parsed_steps > PatternStepParser (heuristic). Migration: 009_add_parsed_steps. New file: AIStepParserService.swift (main app Services).
- **Smart pattern search (done):** Stash & Tools → Find patterns. User enters or selects materials (yarn weight, needle/hook size, craft) from stash/tools or freeform; searches Ravelry via RavelryPatternSearchService; results can be opened in Safari or saved to vault (AddPatternView). Requires Ravelry API keys in Config.xcconfig for search; graceful message if not configured.
- **Ravelry account connect and import (done):** Settings → Ravelry. Users can connect their Ravelry account via OAuth 1.0a (RavelryOAuthService, OAuth1Signer, KeychainHelper). Tokens stored in Keychain per app user. After connecting, “Import my Ravelry library” fetches the user’s pattern library (RavelryUserService), dedupes by source_url, and adds patterns via PatternStore. Requires Ravelry OAuth app (consumer key/secret) from ravelry.com/pro/developer; redirect URI must be `patternvault://oauth/ravelry`. Config: RAVELRY_OAUTH_CONSUMER_KEY, RAVELRY_OAUTH_CONSUMER_SECRET.

## Gotchas

- Create `Config/Config.xcconfig` from `Config.xcconfig.example` (set `GEMINI_API_KEY` for AI pattern analysis, and optionally Supabase keys); file is gitignored. Required for main app AI step parsing and Share Extension. For Ravelry: RAVELRY_ACCESS_KEY/PERSONAL_KEY for PDF and Find patterns; RAVELRY_OAUTH_CONSUMER_KEY/RAVELRY_OAUTH_CONSUMER_SECRET for “Connect Ravelry” and import library (create an OAuth app at ravelry.com/pro/developer, redirect URI `patternvault://oauth/ravelry`).
- Git repo: `https://github.com/angelaMinardi/craft-management` — API keys use xcconfig variables (e.g. `$(GEMINI_API_KEY)`); never hardcode secrets in pbxproj.
- Share Extension and main app cannot share Swift files directly — types like `ExtractedContent` are defined in the extension target
- `pbxproj` edits: new files need PBXFileReference + PBXBuildFile + PBXGroup membership + PBXSourcesBuildPhase entry
- `craft-management/` directory is dead (abandoned web app) — ignore it
- Xcode can hang if DerivedData is corrupted: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Fresh Supabase projects need all migrations (001-009) run in order before app works. For existing DBs, run 009 in SQL Editor if `patterns.parsed_steps` is missing: `ALTER TABLE patterns ADD COLUMN parsed_steps TEXT;`
- sudo commands don't work from Claude Code (no tty for password)
- `launch.json` configs are empty — no dev server (iOS-only project, use Xcode)

