# Premium Paywall — Testing Checklist

**Date:** 2026-03-20
**Branch:** Current working branch
**Prereqs:** Run migration `012_user_entitlements.sql` if not already applied. StoreKit config (`Configuration.storekit`) is wired into the scheme automatically.

---

## 0. BEFORE TESTING: Add Widget Target in Xcode (Required)

The widget source files exist (`PatternVaultWidget/`) but the **Xcode target is missing from the project**. You must add it once in the Xcode GUI:

1. Open `PatternVault.xcodeproj` in Xcode
2. **File → New → Target → Widget Extension**
3. Name it **PatternVaultWidgetExtension**, team = your dev team
4. **Uncheck** "Include Live Activity" and "Include Configuration App Intent" (we already have these files)
5. Xcode will create a new folder — **delete the auto-generated files** it creates
6. Instead, add the **existing files** from `PatternVaultWidget/` to the new target:
   - `PatternVaultWidgetBundle.swift`
   - `PatternVaultWidget.swift`
   - `RowTrackerWidget.swift`
   - `AppIntent.swift`
   - `PatternVaultWidgetLiveActivity.swift`
   - `Assets.xcassets`
   - `Info.plist`
7. In the widget target's **Signing & Capabilities**:
   - Add **App Groups** → `group.com.corvidcraft.app`
8. In the **main app target** (PatternVault):
   - **General → Frameworks, Libraries, and Embedded Content** → verify the widget extension is embedded
9. Build both targets to verify

**Why this matters:** Without the target, widgets won't appear on the device at all. All the data sync code is ready — it just needs the target wired up.

---

## 1. StoreKit Configuration (Simulator)

- [ ] Run app in Simulator from Xcode
- [ ] Go to **Settings → Upgrade to Premium**
- [ ] Verify two products load: **Premium Monthly ($2.99)** and **Premium Yearly ($19.99)**
- [ ] Verify yearly shows "Best value — save 44%" description
- [ ] Tap Monthly → simulate purchase → verify "You're a Premium member" state appears
- [ ] Dismiss paywall, relaunch app → verify premium persists (StoreKit sandbox retains transactions)
- [ ] Test **Restore Purchases** button (should find the sandbox transaction)

### StoreKit Error Simulation
- [ ] In Xcode: Debug → StoreKit → Enable "Fail Transactions" → try purchasing → verify error message appears
- [ ] Disable "Fail Transactions" after testing

---

## 2. Multiple Makes (Premium Gate)

### Free user (before purchasing):
- [ ] Open any pattern → scroll to makes section
- [ ] Verify "Add make" button shows **lock icon** (🔒) and muted color
- [ ] Tap "Add make" → verify **paywall sheet** opens (not AddPatternMakeView)
- [ ] The default make (first make) should still work normally for free users

### Premium user (after purchasing):
- [ ] Open any pattern → "Add make" button shows **plus icon** in sage green
- [ ] Tap "Add make" → verify AddPatternMakeView opens normally
- [ ] Create a second make → verify it appears in the makes carousel
- [ ] Switch between makes → verify progress tracks independently

---

## 3. Stash Matching (Premium Gate)

### Free user:
- [ ] Go to **Stash tab → open a yarn stash item → tap ⋯ menu**
- [ ] Verify "Match patterns" shows **lock icon**
- [ ] Tap "Match patterns" → verify **paywall sheet** opens
- [ ] Other menu items (Edit, Remove) should work normally

### Premium user:
- [ ] Same flow → "Match patterns" shows magnifying glass icon
- [ ] Tap → verify **StashMatchPatternsView** opens with yarn matching

---

## 4. Row Tracker Widget (Premium Gate)

> **Requires widget target to be added first (see Section 0)**

### Free user:
- [ ] Add the **Row Tracker** widget to lock screen (accessoryRectangular)
- [ ] Verify widget shows: "Row Tracker" title + "Upgrade to Premium to track rows from your lock screen."
- [ ] Add the **accessoryInline** variant → verify it shows "Row Tracker · Premium"
- [ ] Verify the **Home Screen widget** (PatternVaultWidget) still works — shows counts or "Continue" pattern (this is free for all users)

### Premium user:
- [ ] Row Tracker widget shows active pattern name, row count, +/- buttons
- [ ] Tap +1 on lock screen → verify row increments
- [ ] Tap -1 → verify row decrements (minimum 0)
- [ ] Open app → verify row count synced from widget (sync-back on foreground)
- [ ] Update rows in pattern detail → verify widget updates

### Widget data flow verification:
- [ ] Open a pattern, set row progress → background the app → check widget updated
- [ ] Use widget +/- buttons → re-open app → verify progress synced back
- [ ] Home screen widget shows "Continue [pattern name]" with progress bar when patterns are in progress

---

## 5. Ad Banner (Already Gated — Verify)

- [ ] Free user: verify ad banner appears at bottom of tab bar
- [ ] Premium user: verify ad banner is **hidden**

---

## 6. Existing Free Tier Limits (Regression)

- [ ] **Pattern limit (30):** Add patterns until near limit → verify warning banner appears in PatternListView
- [ ] **AI limit (5/month):** Use AI step analysis → verify it counts down (check Settings or paywall prompt after limit)
- [ ] **Note photo limit (20):** Add note with photo → verify limit message when exceeded
- [ ] **Share Extension:** Save from Safari → verify entitlement cache works (AI skipped if free limit reached, pattern limit enforced)

---

## 7. PaywallView Content

- [ ] Verify benefit list (in order):
  1. Unlimited patterns
  2. Project mode & multiple makes per pattern
  3. Stash matching & yardage calculator
  4. Row Tracker lock screen widget ← **NEW**
  5. Unlimited AI analyses per month
  6. Unlimited note photos
  7. Ad-free experience
- [ ] Verify **no mention of YouTube imports** (removed — feature has no UI)
- [ ] Verify "already premium" text mentions Row Tracker widget
- [ ] Verify Settings free tier summary says: "Free: 30 patterns, 5 AI/month, 20 note photos; includes ads."

---

## 8. GrowthOrchestrator Suppression

- [ ] Dismiss paywall twice in one day → third attempt should be suppressed (daily cap = 2)
- [ ] Verify paywall doesn't show within 2 hours of a friction event (auth failure, purchase cancel, etc.)
- [ ] Verify Settings "Upgrade to Premium" always works (goes through `canShowPaywall`)

---

## 9. Edge Cases

- [ ] Kill and relaunch app as free user → verify gates still enforced (not just in-memory)
- [ ] Purchase premium → kill app → relaunch → verify premium state persists
- [ ] Background/foreground cycle → verify widget data updates on `scenePhase` change
- [ ] Free user with existing multiple makes (created before gate) → verify existing makes still visible and switchable, just can't add new ones

---

## Files Changed

| File | Change |
|------|--------|
| `PatternDetailView.swift` | Premium gate on "Add make" button + patternTitle passed to setRows for widget sync |
| `YarnStashListView.swift` | Premium gate on "Match patterns" menu item + paywall sheet |
| `WidgetDataService.swift` | Row Tracker data gated behind `entitlement_is_premium` App Group flag |
| `RowTrackerWidget.swift` | Added `isPremium` to entry + upgrade message for free users |
| `PatternProgressStore.swift` | `setRows()` now syncs to Row Tracker widget via WidgetDataService |
| `MainTabView.swift` | Added `syncWidgetData()` (home widget) + `syncBackFromRowTrackerWidget()` (sync-back from lock screen +/-) |
| `PaywallView.swift` | Added Row Tracker benefit, removed YouTube, fixed SF Symbol |
| `SettingsView.swift` | Removed YouTube from free tier summary |
| `Configuration.storekit` | **NEW** — StoreKit config for local testing (monthly $2.99, yearly $19.99) |
