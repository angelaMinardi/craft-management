# Documentation Changelog (2026-03-19)

This changelog records the documentation alignment pass to match implemented features and current roadmap direction.

## Updated

### `docs/SETUP.md`
- Fixed Ravelry OAuth variable names to match implementation:
  - from `RAVELRY_OAUTH_CONSUMER_KEY` / `RAVELRY_OAUTH_CONSUMER_SECRET`
  - to `RAVELRY_OAUTH2_CLIENT_ID` / `RAVELRY_OAUTH2_CLIENT_SECRET`

### `../CLAUDE.md`
- Corrected Ravelry auth flow description from OAuth 1.0a language to OAuth 2.0 authorization code flow.
- Removed stale references to consumer key/secret naming and aligned with OAuth2 client ID/secret keys.

### `README.md`
- Added `docs/ROADMAP.md` to the docs index as the canonical roadmap reference.
- Added acquisition execution docs to the index:
  - `docs/ACQUISITION_KEYWORD_MAP.md`
  - `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`
  - `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`
  - `docs/ACQUISITION_CREATIVE_BRIEFS.md`
  - `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
  - `docs/ACQUISITION_CROSS_POD_HANDOFFS.md`
  - `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md`
  - `docs/ACQUISITION_WEEKLY_OPERATING_RHYTHM.md`
  - `docs/ACQUISITION_POD_KICKOFF_PACKET.md`
  - `docs/ACQUISITION_MASTER_INDEX.md`

### `DEPLOY_EDGE_FUNCTION.md`
- Added explicit warning that this file is legacy/optional and not canonical AI architecture guidance.
- Updated one stale line that implied Anthropic key usage in normal extension flow; clarified Gemini/fallback behavior.

### `../PRODUCT_DESCRIPTION.md`
- Updated supplies/inventory section from “Future” to current capability language.
- Removed “eventually” wording for stash usage in audience section.
- Replaced overly absolute privacy/advertising statement with accurate conditional wording aligned to optional AdMob/Firebase usage.
- Split feature status into:
  - **Shipped Features** (share extension, widgets, Ravelry import, AI step parsing, supplies workflows, freemium)
  - **Future Possibilities** (collections, richer previews, offline strategy improvements, export improvements, advanced premium org features)

### `../website/src/pages/privacy.md`
- Replaced generator-template boilerplate with product-specific policy language.
- Clarified collected data categories to match implemented app features.
- Added AI processing language aligned to Gemini-based features.
- Clarified that AdMob/Firebase use can be configuration-dependent and linked Gemini terms.
- Updated effective date to `2026-03-19`.

### `../website/src/pages/terms.md`
- Replaced generator-template boilerplate with app-specific terms structure.
- Added clearer sections for use of service, third-party services, connectivity requirements, AI feature caveats, and disclaimers.
- Clarified optional third-party integrations and linked Gemini terms.
- Updated effective date to `2026-03-19`.

## Added

### `docs/ROADMAP.md`
- New canonical roadmap doc with four sections:
  - Shipped now
  - Next (active priorities)
  - Later (candidate roadmap)
  - Out of scope / legacy

### `docs/APP_REVIEW_CHECKLIST.md`
- Added a Pattern Vault-specific Apple App Review checklist mapped to:
  - Before You Submit readiness
  - Safety, Performance, Business, Design, and Legal sections
  - Review-notes evidence pack requirements
  - Fast go/no-go release gate

### `docs/APP_REVIEW_NOTES_TEMPLATE.md`
- Added a copy/paste App Store Connect "Notes for Review" template.
- Includes reviewer access, non-obvious feature notes, and account deletion callout for 5.1.1(v).

### `docs/ACQUISITION_KEYWORD_MAP.md`
- Added intent-segmented ASO keyword map across three acquisition clusters.
- Mapped each cluster to emotional hook, first in-app win, and store line candidates.
- Added attribution confidence-tier language to avoid deterministic over-claims.

### `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`
- Added canonical paid/ASO taxonomy schema for channel-quality reporting.
- Added confidence/claim rules and naming convention for campaign records.
- Added compliance preflight checklist for review/subscription-adjacent experiments.
- Clarified acquisition vs product pod ownership boundaries.

### `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`
- Added experiment registry template with required fields, owner tracking, and decision logs.
- Added ICE/RICE prioritization requirement and concurrent experiment cap guidance.
- Added default stop-loss thresholds and rollback/escalation rule.

### `docs/ACQUISITION_CREATIVE_BRIEFS.md`
- Added creative brief templates for `mascotHook`, `firstWinDemo`, and `outcomeReel` families.
- Mapped each family to first-session emotional arc and in-app first-win moments.
- Added post-launch review checklist to connect creative performance back to product copy sync.

### `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
- Added a standardized weekly scorecard linking channel -> activation -> conversion -> retention.
- Added explicit attribution confidence notes and stop-loss/compliance review section.
- Added pod-specific recommendation sections reflecting implementation ownership boundaries.

### `docs/ACQUISITION_CROSS_POD_HANDOFFS.md`
- Added formal handoff model from Acquisition recommendations to Core/Growth/Extension-Web execution.
- Added required payload schema, pod-specific checklists, and compliance preflight gate.
- Added escalation sequence for stop-loss breaches and weekly operating cadence.

### `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md`
- Added source-of-truth continuity matrix spanning ad, store, onboarding, paywall, and website messaging.
- Added continuity QA checklist and compliance preflight addendum for review/subscription-adjacent changes.
- Added workflow for weekly message row updates and status transitions (`draft` -> `active` -> `deprecated`).

### `docs/ACQUISITION_WEEKLY_OPERATING_RHYTHM.md`
- Added structured Monday-Friday operating cadence for readout, prioritization, handoff, and launch prep.
- Added experiment governance standards (ICE/RICE, concurrency cap, stop-loss enforcement).
- Added attribution language rules and monthly deep-review checkpoint.

### `docs/ACQUISITION_POD_KICKOFF_PACKET.md`
- Added an operational fast-start packet for the first two weeks of Acquisition Pod execution.
- Added owner roster template, weekly meeting cadence, and week-by-week startup checklist.
- Added definition-of-done criteria for the first weekly readout and explicit preflight/guardrail triggers.

### `docs/ACQUISITION_MASTER_INDEX.md`
- Added a role-based index to help each pod function find the minimum required docs quickly.
- Defined canonical sources for confidence/compliance rules and stop-loss thresholds to reduce duplication drift.
- Added maintenance rules to keep weekly artifacts and ownership links consistent.

### Consolidation updates
- Updated `docs/ACQUISITION_WEEKLY_OPERATING_RHYTHM.md` to reference canonical stop-loss and confidence rule sources instead of re-defining them.
- Updated `docs/ACQUISITION_CROSS_POD_HANDOFFS.md` to point to canonical compliance and threshold definitions.
- Updated `docs/ACQUISITION_POD_KICKOFF_PACKET.md` to reference canonical threshold and confidence/compliance sources.

### `../supabase/functions/delete-account/index.ts`
- Added a new authenticated Edge Function for self-service account deletion.
- Function verifies user JWT, then deletes the auth user via admin API; user-owned data is removed by cascade FKs.

### `../PatternVault/Services/AuthService.swift`
- Updated `deleteAccount()` to call the new `delete-account` function before signing out.
- This replaces prior sign-out-only behavior and enables real on-demand account/data deletion.

### `docs/SETUP.md`, `docs/LAUNCH.md`, `docs/TESTING.md`, `README.md`
- Added deployment/testing/gating references for account deletion and App Review notes template.

## Why this pass

- Eliminate setup-breaking config drift
- Reduce ambiguity about what is already shipped vs planned
- Keep legacy paths clearly marked so they are not mistaken for default architecture
- Keep product/marketing/legal messaging closer to real runtime behavior
- Create a repeatable, team-usable pre-submit process for App Review compliance
