# Corvid Craft Testing Guide

This is the canonical testing doc for manual checks and automated tests.

## 1) Automated tests

Run unit tests in Xcode:
- Product > Test (`Cmd+U`)

Run from CLI:

```bash
cd PatternVault
xcodebuild test -scheme PatternVault -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PatternVaultTests
```

Core coverage includes:
- Pattern parsing and decoding
- Content block parsing and reassembly
- Step parsing (heuristic and edge cases)
- Source platform URL classification

## 2) Manual regression checklist

### Auth

- Sign up, sign in, sign out.
- Session persists across relaunch.
- OAuth callbacks return to app successfully (if enabled).
- Delete Account removes account and user data (test with throwaway account).

### Patterns

- Add/edit/delete pattern.
- Search and filter by status/tag.
- Dashboard counts and recent patterns update correctly.

### Notes

- Add/edit/delete each note type.
- Photo attachment upload and display.
- Empty content validation works.

### Steps and content

- Step priority works: custom layout > AI parsed steps > heuristic parser.
- Analyze Steps behavior works when AI is enabled.
- Content editor remove/reassemble behavior works.

### Share extension

- Share URL from Safari.
- Test Ravelry, YouTube/TikTok, and a generic web URL.
- Validate fallback behavior when extraction fails.

### Visibility and contrast

- Run checks in all three modes: Light, Dark, and Accessibility > Increase Contrast.
- Save extension (`Save to Corvid Craft`):
  - Confirm title and description text are readable on warm cream surfaces.
  - Confirm section headers, metadata labels, and loading text remain readable while loading.
  - Confirm tag chip labels and remove icons are clearly visible.
  - Confirm segmented control selected/unselected labels are readable.
- Pattern detail:
  - Confirm hero platform pill text is readable over both light and dark thumbnail images.
- Chart/PDF surfaces:
  - Confirm chart thumbnail borders are visible on both light and dark source imagery.
  - Confirm chart editor handles and annotation markers remain visible against varied backgrounds.
- Regression note:
  - Any newly added white text on blur/material or photo backgrounds must include a guaranteed-contrast backing (solid fill or dark scrim).

### Widget and app group sync

- Widget shows expected values for empty and non-empty states.
- Continue/progress values refresh after app data changes.

### Monetization and gating

- Free-tier limits enforce correctly.
- Paywall appears at expected entry points.
- Premium entitlement removes ad and feature gates appropriately.

## 3) Pre-release gates

- All unit tests pass on release branch.
- Manual regression checklist completed.
- Visibility and contrast checklist completed in Light/Dark/Increase Contrast.
- Supabase migrations are applied in production and verified.
- Config values are set for release (no placeholders).
- Legal URLs in app Info settings resolve.

## 4) Notes

- Keep one source of truth here; avoid creating separate "testing plan" and "testing evaluation" docs unless needed for a specific release audit.
