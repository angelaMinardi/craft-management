# Pattern Vault Art and Branding Guide

This document defines the visual identity for Pattern Vault based on the current app implementation.
Use it to keep in-app UI, App Store assets, social content, and website visuals consistent.

## 1) Brand personality

Pattern Vault should feel:

- Warm and welcoming, never sterile.
- Craft-forward and handmade-adjacent, but still clean and modern.
- Encouraging and practical: "you can do this" energy.
- Calmly premium: polished details without luxury intimidation.

Voice cues for visual and copy decisions:

- Friendly, short, benefit-led language.
- Confidence without hype.
- Gentle delight through motion and mascot moments.

## 2) Core color system

These colors come from `Theme.swift` (UIKit values used for exact references).

| Token | RGB | Hex | Role |
|---|---:|---:|---|
| Warm Cream | 255, 248, 240 | `#FFF8F0` | Primary background and soft canvas |
| Soft Coral | 232, 131, 107 | `#E8836B` | Primary accent and CTA emphasis |
| Deep Plum | 74, 32, 64 | `#4A2040` | Primary text and high-contrast anchors |
| Sage Green | 168, 197, 160 | `#A8C5A0` | Success/completion and secondary positive accents |
| Dusty Blue | 143, 170, 189 | `#8FAABD` | Informational note accents and supportive UI |
| Honey | 232, 184, 75 | `#E8B84B` | Progress/in-progress status and premium highlights |

### Functional color mapping

- `wantToMake`: Soft Coral
- `inProgress`: Honey
- `completed`: Sage Green
- Inputs: Warm Cream at reduced opacity
- Card backgrounds: White
- Chips/tags: Coral tint fill with plum/coral text states

### Contrast guidance

- Default text should use Deep Plum on Warm Cream/white backgrounds.
- Avoid long body text in Soft Coral or Honey.
- For accessibility, keep body copy at high contrast (Deep Plum preferred).
- Use coral/honey as accents, not dense text blocks.

## 3) Background and surface language

### App backgrounds

- Default full-screen background: Warm Cream or `Theme.screenGradient`.
- Gradient direction should remain subtle (top to bottom), not dramatic.
- Backgrounds should support readability first; avoid visual noise.

### Cards and containers

- Prefer rounded cards with soft shadows or light outline strokes.
- Corner radius language:
  - Small: 8
  - Medium: 12
  - Large: 16
  - Pill: 100
- Card styles:
  - Standard content: `cardStyle()`
  - Prominent list/dashboard: `elevatedCardStyle()`
  - Structured/clean sections: `borderedCard()`
  - Accent callouts: `accentBorderedCard()`

## 4) Typography direction

Pattern Vault typography is rounded system-based to stay friendly and native.

- Use `.rounded` design fonts across headings, body, labels, and badges.
- Title styles should feel soft-bold, not condensed or overly geometric.
- Hierarchy pattern:
  - Large Title: screen hero moments
  - Title/Headline: section framing and actions
  - Body: primary reading
  - Caption/Captions2: metadata, badges, support text

### Type tone rules

- Prefer sentence case over all caps.
- Use all caps only for tiny utility tokens (for example: "NEW" badge).
- Keep microcopy concise; avoid paragraph-heavy screens.

## 5) Motion and interaction feel

Motion should communicate warmth and clarity, not spectacle.

- Preferred easing: spring/ease-out with short durations.
- Common movement: gentle entrance, slight scale tap feedback, subtle stagger.
- Tap states:
  - Primary buttons compress slightly on press.
  - Interactive surfaces should have immediate visual response.
- Keep animation amplitude low; avoid dramatic transitions in core flows.

## 6) Mascot and illustration direction

The crow mascot is a key identity element and should be used intentionally.

### Mascot principles

- Emotion role: encouragement, companionship, progress celebration.
- Placement role: empty states, onboarding hero, lightweight delight moments.
- Motion style: gentle bob/tilt/pulse, playful but not distracting.

### Usage guidance

- Use mascot when users may need reassurance (empty/loading/new feature).
- Pair mascot with actionable copy, not just decoration.
- Do not overuse mascot in dense data-entry screens.
- Maintain consistent art style, proportions, and expression language.

## 7) Component style patterns

### Buttons

- Primary CTA uses Soft Coral fill with white text and pill shape.
- Secondary actions should remain understated (text/plum tint/outlined).
- Avoid introducing new saturated CTA colors unless a semantic need exists.

### Status and badges

- Status badge = icon + short text + tinted capsule background.
- Keep badge labels short and scannable.
- Preserve current status color semantics across app and marketing visuals.

### Pattern card signature

Pattern cards are a signature element:

- Image-forward top section.
- Rounded container and soft depth.
- Deep Plum title text.
- Thin status color strip at bottom.

When creating mocks/marketing images, keep this structure recognizable.

## 8) Layout and spacing rhythm

Spacing tokens:

- XS: 4
- SM: 8
- MD: 12
- LG: 16
- XL: 24
- XXL: 32

Guidelines:

- Prefer breathable vertical spacing over dense stacking.
- Group related controls with consistent token jumps (e.g., 8 -> 12 -> 16).
- Leave room around mascot and hero cards so they can "breathe."

## 9) Marketing and social asset direction

### Visual composition

- Lead with Warm Cream backgrounds and Deep Plum text.
- Use Soft Coral for key highlights (buttons, underlines, key words).
- Include Sage Green/Honey as supporting accents, not dominant fields.

### Screenshot and promo style

- Favor real UI captures with subtle polish over fully abstract artwork.
- Keep overlays minimal: one headline, one key benefit, one CTA.
- Use rounded cards and pill shapes in supporting graphics.

### Iconography and symbols

- Prefer simple, rounded-feel SF Symbols or similarly soft icon sets.
- Keep stroke/weight visually balanced with rounded typography.

## 10) Do and don't

### Do

- Keep the warm + modern balance.
- Use Deep Plum for primary readability.
- Keep corners rounded and shadows subtle.
- Use mascot as emotional support at key user moments.
- Preserve color semantics for statuses.

### Don't

- Don't switch to stark white/black high-tech visual language.
- Don't use neon or highly saturated unrelated accent colors.
- Don't introduce sharp-cornered component systems.
- Don't create long dense text blocks in low-contrast colors.
- Don't over-animate core navigation and data-entry flows.

## 11) Asset creation checklist

Before publishing any new visual asset, verify:

- Color palette matches brand tokens above.
- Typography feels rounded/native and hierarchy is clear.
- CTA and status colors keep their semantic meaning.
- Mascot usage (if present) supports a user moment.
- Visual density is calm and readable on small screens.

---

If design tokens change in `Theme.swift`, update this document in the same PR so branding guidance stays aligned with implementation.
