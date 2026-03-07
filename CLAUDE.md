# Pattern Vault

## Project Overview
iOS-only craft pattern organizer (Swift/SwiftUI + Supabase). No web app.

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
- AI analysis via Claude Haiku (`claude-haiku-4-5-20251001`) with API key from Info.plist
- Pipeline: HTML fetch → WebContentExtractor → AIPatternAnalyzer → SupabaseExtensionClient.savePattern
- `max_tokens` for AI call: 4096 (to accommodate `cleaned_content` and 12+ JSON fields)
- Page text extraction limit: 10000 chars with smart truncation at paragraph breaks
- Fallback: when AI fails, raw `pageText` is saved as `cleanedContent`
- **Ravelry:** For `ravelry.com/patterns/...` URLs, RavelryPatternExtractor runs first: tries Ravelry API `pdf_url` (if RAVELRY_ACCESS_KEY/PERSONAL_KEY set), then scrapes page for PDF/download links, follows intermediate "Pattern Purchase" page to ravelrycache.com PDF. If no PDF found, falls back to WebContentExtractor with **Ravelry chrome filtered out** (nav/sidebar/footer); if saved content would be chrome-only, `source_content` is stored as nil. Main app hides Ravelry chrome in Pattern Content and steps (PatternStepParser.looksLikeRavelryChrome, PatternContentView effectiveContent).

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
- **Hands-free row counting (done):** User speaks to the app (e.g. “row 12”) while working on a pattern; app uses speech recognition to capture the row/round number and updates progress (current row or progress_update note) so tracking is hands-free. Likely: Speech framework (SFSpeechRecognizer), tap-to-talk or short listening; map spoken numbers to pattern steps (PatternStepParser / existing progress model); optional spoken confirmation (“Got it, row 12”). Implemented: VoiceRowService; tap Row in pattern detail, say row/round number; updates progress + note, speaks confirmation.

## Gotchas
- Git repo: `https://github.com/angelaMinardi/craft-management` — API keys use `$(ANTHROPIC_API_KEY)` xcconfig variable (never hardcode secrets in pbxproj)
- Share Extension and main app cannot share Swift files directly — types like `ExtractedContent` are defined in the extension target
- `pbxproj` edits: new files need PBXFileReference + PBXBuildFile + PBXGroup membership + PBXSourcesBuildPhase entry
- `craft-management/` directory is dead (abandoned web app) — ignore it
- Xcode can hang if DerivedData is corrupted: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Fresh Supabase projects need all 3 migrations run in order before app works
- sudo commands don't work from Claude Code (no tty for password)
- `launch.json` configs are empty — no dev server (iOS-only project, use Xcode)
