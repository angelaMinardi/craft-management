# Acquisition Campaign Taxonomy

Canonical naming and metadata schema for paid + ASO experiments.

## Purpose

- Align ad creative, store messaging, onboarding copy, and paywall framing.
- Preserve "best available attribution" discipline with confidence tiers.
- Enable channel-quality reporting, not just install volume.

## Required Fields

Every campaign and experiment record must define:

- `channel`: e.g., `meta`, `tiktok`, `appleSearchAds`, `organicAso`
- `campaignId`: unique internal ID, stable over lifecycle
- `campaignName`: human-readable title
- `adsetId`: platform adset/group identifier
- `creativeId`: unique creative asset identifier
- `creativeFamily`: `mascotHook` | `firstWinDemo` | `outcomeReel`
- `intentCluster`: `beginnerOrganizer` | `stashPlanner` | `saveFromWeb`
- `promiseAngle`: one sentence value promise shown in ad/store
- `ctaType`: `downloadNow` | `learnMore` | `joinWaitlist`
- `storeVariant`: mapped App Store metadata variant ID
- `onboardingVariant`: mapped onboarding copy variant ID
- `paywallVariant`: mapped paywall copy variant ID (or `none`)
- `attributionConfidence`: `high` | `medium` | `directional`
- `startDate`
- `endDate` (optional until closed)
- `owner`

## Naming Convention

Use this format for `campaignName`:

`{channel}_{intentCluster}_{creativeFamily}_{promiseAngleShort}_{yyyyww}`

Example:

`meta_beginnerOrganizer_firstWinDemo_neverLosePatterns_202611`

## Report Metrics (Minimum Set)

By campaign and by intent cluster:

- installs
- onboarding completion rate
- first meaningful action rate
- paywall view rate
- purchase conversion rate
- D7 retention
- CAC
- payback estimate
- complaint volume (support + store feedback tags)
- attribution confidence tier

## Confidence and Claim Rules

- Never claim deterministic source-to-user mapping unless confidence is `high` and source linkage is verified.
- If confidence is `medium` or `directional`, report directional lift language only.
- Every growth readout row must include a confidence note.

## Compliance Preflight (Required Before Launch)

If an experiment touches review prompts, subscription framing, urgency language, or discount presentation, complete this checklist first:

- App Store-safe review behavior (no incentivized or manipulative asks)
- Subscription framing is transparent and non-deceptive
- Any urgency/discount language is factual and time-bounded
- Legal copy remains consistent across `/privacy`, `/terms`, `/contact`
- Product pod sign-off recorded (Core/Growth/Extension-Web as applicable)

## Scope and Ownership

- Acquisition Pod: test design, taxonomy governance, readout cadence.
- Core/Growth/Extension-Web pods: implementation scope, technical feasibility, release timing.

