# Corvid Craft Roadmap

Canonical roadmap for what is shipped now, what is next, and what is later.
Keep this updated when feature status changes.

## Shipped now

- Auth (email, Apple, Google via Supabase)
- Pattern CRUD with status tracking (Want to Make / In Progress / Completed)
- Search and filtering (text, tags, status, source)
- Project notes (general, yarn info, modifications, progress) with photo attachments
- Share Extension (`SaveToPatternVault`) with URL/PDF import and Gemini-powered extraction
- AI step parsing (import-time + on-demand) with kill switch (`app_config.ai_enabled`)
- Ravelry integrations:
  - Pattern PDF lookup in share extension (`RAVELRY_ACCESS_KEY` / `RAVELRY_PERSONAL_KEY`)
  - Find patterns search from stash/tools
  - Connect Ravelry + import library (OAuth2)
- Stash and tools inventory:
  - Yarn stash
  - Needle and hook inventory
  - Stash-to-pattern matching flow
- Hands-free row counting (voice row/round updates in pattern detail)
- Freemium controls (usage limits, entitlement table, paywall paths)
- Widget support and app group sync

## Next (active priorities)

- Strengthen documentation quality and consistency as a release gate
- Launch-readiness hardening:
  - final legal copy
  - App Store metadata/screenshots
  - full manual regression pass on release candidate
- Reliability/quality:
  - expand automated tests for high-risk parsing/import flows
  - reduce edge-case extraction failures for shared links
- Monetization tuning:
  - monitor AI cost vs ad/subscription revenue
  - tune free-tier limits based on real usage

## Later (candidate roadmap)

- Pattern collections (user-defined grouped lists)
- Richer link previews and content normalization
- Better offline access strategy for saved pattern data
- Backup/export improvements
- Advanced premium organization features (as validated by usage)

## Out of scope / legacy

- Supabase Edge Function YouTube transcript + Claude pipeline is legacy/optional.
- Canonical AI path is Gemini in app + extension.
