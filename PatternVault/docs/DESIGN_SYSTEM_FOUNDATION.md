# Design System Foundation (Design Systems Pod)

This is the implementation-ready reference for shared UI foundations across iOS app surfaces and website surfaces.

It is optimized for:
- playful but productive expression
- emotional onboarding and retention moments
- simple, trustworthy monetization UX
- consistent execution across pods without one-off styles

## 1) Canonical Token Model + iOS/Web Parity

### Color tokens

| Semantic role | iOS token (`Theme.swift`) | Web token (`global.css`) | Notes |
|---|---|---|---|
| Page background | `Theme.warmCream` | `--warm-cream` | Canonical base canvas |
| Accent/Primary emphasis | `Theme.softCoral` | `--soft-coral` | Primary emotional accent |
| Primary text | `Theme.deepPlum` / `Theme.Semantic.textPrimary` | `--deep-plum` / `--text-primary` | Default high-contrast text |
| Positive/success | `Theme.sageGreen` / `Theme.Semantic.success` | `--sage-green` / `--state-success` | Progress and completion |
| Warning/progress | `Theme.honey` / `Theme.Semantic.warning` | `--honey` / `--state-warning` | In-progress + caution accents |
| Informational/support | `Theme.dustyBlue` / `Theme.Semantic.info` | `--dusty-blue` / `--state-info` | Neutral helper tone |
| Error (soft) | `Theme.Semantic.error` | `--state-error` | Friendly recovery, not alarming red |
| Surface base | `Theme.Semantic.surfaceBase` | `--card-bg` | Card-like surface |
| Surface subtle | `Theme.Semantic.surfaceSubtle` | `--surface-subtle` | Gentle callout/input background |
| Border subtle | `Theme.Semantic.borderSubtle` | `--card-border` | Low visual weight boundaries |
| Border standard | `Theme.Semantic.borderStandard` | `--border` | Primary stroke |
| Border strong | `Theme.Semantic.borderStrong` | `--border-strong` | Rare emphasis boundaries |

### Typography and spacing

- iOS rounded system family stays canonical (`Theme.Typography`).
- Web keeps rounded-feel system font stack with existing scale in `global.css`.
- Spacing parity anchors:
  - XS/SM/MD/LG/XL/XXL -> 4/8/12/16/24/32
- Radius parity anchors:
  - small/medium/large/pill -> 8/12/16/100 (web equivalents via root vars)

### Motion tokens

| Motion role | iOS token | Web token |
|---|---|---|
| Fast interaction | `Theme.Motion.quick` | `--duration-fast` |
| Standard transition | `Theme.Motion.standard` | `--duration-normal` |
| Expressive moment | `Theme.Motion.expressive` | `--duration-slow` |
| Stagger step | `Theme.Motion.staggerStep` | `--stagger-step` |

## 2) Reusable Component Contracts

Use these contracts instead of introducing one-off styles.

### Cards

- iOS:
  - `cardStyle()` for default surfaces
  - `elevatedCardStyle()` for hero/featured cards
  - `borderedCard()` for structured utility panels
  - `accentBorderedCard()` for selective emphasis
- Web:
  - `.pv-card`
  - `.pv-card-elevated`

### Buttons

- iOS:
  - `PrimaryButtonStyle()` for primary CTA
  - Press feedback: scale down to `Theme.Motion.pressScale`
- Web:
  - `.pv-button-primary`
  - hover darkens subtly
  - active state scales to 0.96
  - disabled reduces opacity + pointer affordance

### Empty states

- Must include:
  - one concise reassurance line
  - one clear next action
  - mascot in support mode (typically idle)
- iOS implementation uses `SpriteMascotView.idle()` or `TappableMascotView` where optional delight is appropriate.

### Callouts

- iOS:
  - `.calloutCard(kind:)` with `neutral/info/success/warning/error`
- Web:
  - `.pv-callout` + optional variant class
  - `.pv-callout-info`, `.pv-callout-success`, `.pv-callout-warning`, `.pv-callout-error`

### Banners

- iOS:
  - `.bannerSurface()` for inline banner modules
- Web:
  - `.pv-banner`

### Input surfaces

- iOS:
  - `.inputSurface(isFocused:hasError:)`
  - states:
    - default: standard border
    - focused: accent border
    - error: error border
- Web:
  - `.pv-input-surface`
  - focus via `:focus-visible`
  - error via `[aria-invalid="true"]`

### Paywall modules

- iOS:
  - `.paywallModule()` for quiet premium containers
- Web:
  - `.pv-paywall-module`
- Rules:
  - calm gradient + simple copy hierarchy
  - no fake urgency language
  - no interruptive animation

## 3) Growth Moment Pattern Library (4 Moments)

Each moment is reusable across app and website narratives.

### A) Emotional peak

- Intent: mark meaningful progress and reinforce competence.
- Trigger examples:
  - first successful import
  - first completion status change
  - first streak milestone
- Composition:
  - compact celebratory headline
  - mascot: one-shot `jumping`
  - primary CTA: continue momentum
  - optional secondary: share or save win
- Frequency:
  - max once per milestone type per session

### B) Purpose explainer

- Intent: explain why a setup action is worth doing now.
- Trigger examples:
  - onboarding step before sync/organization action
  - first encounter with advanced tool
- Composition:
  - short value sentence
  - one “how this helps” line
  - mascot: educational/support pose (`idle` or `knitting`)
  - CTA pair: continue / not now
- Frequency:
  - show at first encounter and after major feature changes only

### C) Soft nudge

- Intent: gently invite re-engagement or premium discovery.
- Trigger examples:
  - user completes useful free action and pauses
  - user hits soft threshold
- Composition:
  - neutral tone line, no pressure
  - benefit-led CTA
  - optional fallback action to dismiss
  - mascot: support mode, no celebration frame
- Frequency:
  - max one nudge per user action cluster
  - cooldown before re-showing

### D) Shareable win

- Intent: package progress into a proud, repeatable moment.
- Trigger examples:
  - completed project
  - “X rows done” milestone
- Composition:
  - visual badge/card
  - concise stat line
  - mascot celebration optional
  - share CTA + continue CTA
- Frequency:
  - only on genuine wins
  - no synthetic “share now” pressure

## 4) Mascot Placement + Motion Governance

### Placement matrix

| Context | Primary mascot mode | Purpose |
|---|---|---|
| Celebration | `jumping` (one-shot) | reward and encouragement |
| Education | `idle` or `knitting` | guidance and companionship |
| Support/empty state | `idle` | reassurance |
| Loading | `walking` | indicate active progress |
| Error recovery | `pouty` + action copy | empathy + next step |

### Motion guardrails

- Core durations:
  - quick: ~0.2s
  - standard: ~0.35s
  - expressive: ~0.6s
- Max simultaneous animated emphasis elements: 2.
- Avoid loop-heavy scenes with more than one continuously looping mascot.
- Avoid autoplay celebration loops on every visit.
- Respect reduced-motion preferences on web and iOS where applicable.

## 5) Do / Don’t (Color + Mascot)

### Do

- Use semantic tokens, not ad-hoc colors.
- Keep Deep Plum as primary readable text color.
- Use coral as focused emphasis, not all-purpose decoration.
- Pair mascot with actionable copy.
- Prefer one clear emotional cue per surface.

### Don’t

- Don’t introduce unrelated neon or saturated accent colors.
- Don’t put mascot in dense forms, legal pages, or high-cognitive tasks.
- Don’t stack multiple animated accents that compete for attention.
- Don’t use manipulative urgency or forced-review tone in premium/review moments.
- Don’t invert status color meanings between app and web.

## 6) Team QA Rubric (Pre-Merge)

Use this checklist for redesigned surfaces:

- Uses approved tokens and component contracts (no one-off visual primitives).
- Includes one of the four growth moments only when trigger is valid.
- Mascot placement matches context matrix and does not distract from primary task.
- Motion follows duration and frequency guardrails.
- Premium modules remain quiet, clear, and dismissible.
- Review ask behavior only appears at genuine positive milestones (no gating).
- Web legal routes remain stable and accessible:
  - `/privacy`
  - `/terms`
  - `/contact`
- Patterns remain App Store-safe (no incentivized review language, no deceptive monetization).

## 7) Handoff Notes To Other Pods

- Product/Growth pods should consume this doc first, then implement with:
  - iOS tokens/components in `Theme.swift`
  - web utilities/components in `website/src/styles/global.css`
- Any new visual primitive must be added to this design foundation before use in feature surfaces.
