# Acquisition Message Sync Matrix

Single source of truth for messaging continuity across:
- paid creative
- App Store metadata
- in-app onboarding
- in-app paywall
- website

Use this matrix to prevent promise drift and keep acquisition aligned with product reality.

## Rules

- No message launches without continuity mapping across all applicable surfaces.
- Do not claim deterministic source-to-user attribution when confidence is below `high`.
- Any row touching reviews/subscriptions must pass compliance preflight before launch.
- Acquisition recommends changes; Core/Growth/Extension-Web decide implementation and release timing.

## Matrix Columns

| messageId | intentCluster | creativeFamily | adHook | storeLine | onboardingLine | paywallLine | websiteLine | legalTouchpoint | confidenceTier | status | owner |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MSG-001 | beginnerOrganizer | mascotHook | Too many saved pattern tabs? | Save every pattern in one private vault. | Keep your next project in view. | Upgrade for unlimited pattern organization. | Your craft library, in your pocket. | privacy/terms transparency unchanged | medium | draft | Acquisition |
| MSG-002 | saveFromWeb | firstWinDemo | Save from anywhere in two taps. | Save from Ravelry, Etsy, TikTok, YouTube, and blogs. | Spot a pattern you love, then save it fast. | Unlock advanced import and AI helpers. | Save patterns from anywhere else. | no additional legal updates needed | high | active | Acquisition + Extension-Web |

## Continuity QA Checklist

For each `active` message row:

- [ ] Ad hook and store line describe the same user promise.
- [ ] Onboarding line gives the same first-session expectation.
- [ ] Paywall line does not over-promise and remains transparent.
- [ ] Website line matches live app/store reality.
- [ ] Legal touchpoints remain accurate for freemium, ads, AI, and data usage.
- [ ] Confidence tier documented and reflected in reporting language.

## Compliance Preflight Addendum

Required when changing:
- review prompt copy/timing
- subscription framing
- urgency or discount language

Checklist:
- [ ] App Store-safe pattern confirmed
- [ ] No manipulative or incentivized review mechanics
- [ ] Subscription terms clear and factual
- [ ] Urgency/discount claims verifiable and time-bounded
- [ ] `/privacy`, `/terms`, `/contact` remain consistent

## Weekly Update Workflow

1. Add or update message rows based on weekly readout winners.
2. Mark proposed status as `draft`.
3. Run continuity QA + compliance preflight.
4. Move to `active` only after product pod sign-off.
5. Archive stale rows as `deprecated` with rationale.

