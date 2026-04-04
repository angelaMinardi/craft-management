# Artist Asset Integration QA and Final Revision Guide

Run this checklist before importing art into iOS app, share extension, and website surfaces.

## 1) Intake Validation

- Delivery package includes source files and exports.
- Folder structure matches agreed package spec.
- All filenames follow required naming convention.
- Asset index CSV is completed and up to date.

Reference template:
- `PatternVault/docs/ARTIST_ASSET_INDEX_TEMPLATE.csv`

## 2) File Format and Technical QA

- PNG exports have transparent backgrounds where expected.
- No matte fringe or compression artifacts.
- Color space is sRGB.
- Frame sequences are continuous (`frame_000` onward).
- All frames in each animation set share identical dimensions.

## 3) iOS and Share Extension Performance Budgets

- Animation frame dimensions are within agreed ranges.
- No individual frame is unexpectedly oversized.
- Total asset payload does not create memory pressure in share extension.
- Heavy decorative assets have smaller fallback variants.

## 4) UI Fit and Readability QA

- Mascot expressions are readable at small mobile sizes.
- Text-safe zones are respected for onboarding and web hero crops.
- Illustrations do not reduce contrast under headline/body text.
- Visual density is calm; no clutter around primary CTAs.

## 5) Moment-by-Moment Placement QA

Verify each category in real UI contexts:

- Onboarding bond scene
- First-win prompt scene
- Purpose-framing scene
- Celebration overlays
- Empty and recovery states
- Share-card frames
- Website hero and how-it-works illustrations

Pass criteria:

- The asset supports the intended emotion.
- The next action remains clear.
- The illustration does not compete with core UI controls.

## 6) Accessibility QA

- Contrast remains acceptable with text overlays.
- Meaning is not dependent on color alone.
- Key states remain understandable without animation.

## 7) Cross-Surface Consistency QA

- Mascot proportions and facial landmarks stay consistent.
- Palette usage matches brand tokens.
- Tone remains supportive across app, extension, and web.

## 8) Revision Round Rules

Use one structured revision round for production blockers only.

Allowed revision reasons:

- readability issues
- technical import issues
- style drift from locked direction
- missing required variants

Not allowed in this pass:

- net-new concepts that change style direction
- scope expansion beyond approved shot lists

## 9) Final Signoff Checklist

Signoff requires explicit approvals from:

- Product/Design lead
- Design Systems pod
- Core pod representative
- Extension/Web pod representative

Final signoff packet includes:

- completed asset index
- QA checklist outcomes
- revision notes and resolutions
- approved production package version tag

