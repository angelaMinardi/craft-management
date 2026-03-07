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
- `max_tokens` for AI call must accommodate 12+ JSON fields including `cleaned_content` (currently 2000, ideally 4096+)
- Page text extraction limit: 10000 chars with smart truncation at paragraph breaks
- Fallback: when AI fails, raw `pageText` is saved as `cleanedContent`

## Theme System (`Theme.swift`)
- Brand colors: warmCream, softCoral, deepPlum, sageGreen, dustyBlue, honey
- Typography: all `.rounded` design system fonts
- Card modifiers: `.cardStyle()`, `.borderedCard()`, `.accentBorderedCard()`
- Reusable components: `SectionHeaderView`, `StatusBadge`, `SpriteMascotView`
- Staggered entrance animation: `.staggeredAppear(index:)`
- PatternCardView is shared between DashboardView and PatternListView — changes ripple to both

## Milestones
- 1 (Auth): Complete
- 2 (Patterns CRUD): Complete
- 3 (Project Notes): Implemented, needs testing
- 4 (Tags & Filters): Implemented, needs testing
- 5 (Share Extension): Implemented with AI analysis, video/TikTok extraction, PDF support
- 6 (Polish): In progress — Dashboard, PatternCardView, Theme redesigned; PatternDetailView next

## Gotchas
- No git repository — project is not version-controlled (git commands will fail)
- Share Extension and main app cannot share Swift files directly — types like `ExtractedContent` are defined in the extension target
- `pbxproj` edits: new files need PBXFileReference + PBXBuildFile + PBXGroup membership + PBXSourcesBuildPhase entry
- `craft-management/` directory is dead (abandoned web app) — ignore it
- Xcode can hang if DerivedData is corrupted: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Fresh Supabase projects need all 3 migrations run in order before app works
- sudo commands don't work from Claude Code (no tty for password)
- `launch.json` configs are empty — no dev server (iOS-only project, use Xcode)
