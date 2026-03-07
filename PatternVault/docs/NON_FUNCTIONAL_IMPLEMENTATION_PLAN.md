# Plan: Implement Non-Functional UI Features

This document identifies UI that is currently placeholder or decorative and outlines how to make it functional.

---

## 1. Pattern Steps (Primary Gap)

**Current state:** Pattern detail shows a single "Step 1" block with a fixed 10% progress bar and the first line of `patternDescription` as the instruction. There is no multi-step support, no navigation, and no persisted progress.

**Root cause:** The `Pattern` model has no steps array or progress fields. Progress is not stored anywhere. `patternStepSection` uses `@State private var stepProgress: Double = 0.10` and `patternStepInstruction` is derived from the first line of description only.

**Implementation plan:**

### 1.1 Derive steps from existing content

- **Source of truth:** Use `pattern.sourceContent` (the same HTML-extracted text that `PatternContentView` already displays). No new DB columns for step text.
- **Parsing:** Introduce a shared or duplicated step parser that:
  - Splits content by double newlines (or by headings).
  - Detects step-like blocks: lines starting with "Step 1", "Step 2", "Round 1", "Row 1-10", or numbered lines "1.", "2." etc.
  - Returns an array of `(title: String, body: String)` (e.g. "Step 1" and the following paragraph).
- **Fallback:** If no step structure is found, treat the whole description (or first N paragraphs) as a single step so the UI still shows one block.

**Suggested location:** A small helper type or static methods, e.g. `PatternStepParser` in the main app target, or a `parseSteps(from sourceContent: String?) -> [PatternStep]` used by both `PatternContentView` (optional) and `PatternDetailView`. Model: `struct PatternStep { let title: String; let body: String }`.

### 1.2 Store progress (current step + optional rows)

- **Option A — App-only (simplest):** Store in `UserDefaults` (or App Group `UserDefaults`) keyed by pattern ID:
  - `current_step_index: Int` (0-based)
  - `rows_completed: Int?`, `total_rows: Int?` (optional, for row-based patterns)
  - No migration; works offline; survives app restart.
- **Option B — Supabase:** New table `pattern_progress (pattern_id, user_id, current_step_index, rows_completed, total_rows, updated_at)` with RLS. Sync across devices; requires migration and repository.

**Recommendation:** Start with **Option A**. Add a thin `PatternProgressStore` (or store in existing `PatternStore`) that reads/writes `UserDefaults` keyed by pattern ID. Later, add Option B and migrate.

### 1.3 Pattern detail UI changes

- **Data:** In `PatternDetailView`, compute `steps: [PatternStep]` from `PatternStepParser.parseSteps(current.sourceContent)` (with single-step fallback from `patternDescription`). Load/save progress via the progress store (by `current.id`).
- **Display:**
  - Show "Step N of M" (or "Step 1" when only one).
  - Show the current step’s title and body (replace current single `patternStepInstruction`).
  - Progress bar: `current_step_index / max(1, steps.count)` or, if row data exists, `rows_completed / total_rows`.
  - Prev/Next (or step picker) to change `current_step_index` and persist.
- **Optional:** "Update progress" control (e.g. rows completed / total rows) that updates the progress store and optionally creates a `progress_update` note.

### 1.4 Files to add or touch

- Add: `PatternStepParser` (or equivalent) to derive `[PatternStep]` from `sourceContent`.
- Add: Progress storage (e.g. `PatternProgressStore` + UserDefaults keys, or extension on `PatternStore`).
- Modify: `PatternDetailView` — replace placeholder `stepProgress` and single-step instruction with steps array, current index from progress store, step navigation, and progress bar from step or row data.

---

## 2. Continue Card Progress (Dashboard / Pattern List)

**Current state:** The "Continue [Pattern name]" card shows a hardcoded 1% (`continueProgressPercent: Double { 0.01 }`).

**Implementation plan:**

- **Source of progress:** Once pattern progress is stored (see §1.2), the continue card should use it:
  - For the in-progress pattern, read progress from the same store (step index / step count or rows_completed / total_rows).
  - Expose a way for `PatternListView` (and optionally `DashboardView`) to get progress for a given pattern ID (e.g. from `PatternProgressStore` or from `PatternStore` if progress is held there).
- **Fallback:** If you want the continue card to show something before full step implementation, derive a heuristic from the latest `progress_update` note for that pattern (e.g. parse "10 of 100 rows" or "50%" from note content) and use that for the bar. This requires loading notes for the in-progress pattern (e.g. in `PatternListView` or via a small helper that fetches progress notes and parses them).

**Files to touch:** `PatternListView` (and optionally `DashboardView`): replace `continueProgressPercent` with a value from the progress store or from parsed progress notes.

---

## 3. Floating Tool Palette (Lower Priority)

**Current state:** Decorative only; `allowsHitTesting(false)`. Labels like "Warm", "DUSTY BLUE", clock are not tappable.

**Implementation plan (optional):**

- Remove `allowsHitTesting(false)` and add real actions, e.g.:
  - "Log time" → present a simple time-log sheet and optionally create a `progress_update` note.
  - "Set yarn color" → store selected color name (e.g. in progress store or a note) and show it on the palette.
- Keep the same visual layout; only make the chips buttons and hook them to the new actions.

---

## 4. Dismiss Continue Card Persistence (Optional)

**Current state:** Tapping "X" on the continue card hides it for the session only (`dismissedContinuePatternId`); it reappears on next launch.

**Implementation plan (optional):**

- Persist dismissed IDs in `UserDefaults` (e.g. key `dismissed_continue_pattern_ids` as array of UUID strings). On appear, set `dismissedContinuePatternId` from this list (or use a set of IDs). When user taps X, add pattern ID to the list and save.
- Optional: add "Show again" in a menu or settings so users can clear the list.

---

## Suggested order of work

1. **Steps and progress (Section 1)**  
   - Implement step parser and `[PatternStep]` from `sourceContent`.  
   - Add progress storage (UserDefaults + `PatternProgressStore` or equivalent).  
   - Update `PatternDetailView`: show steps, current step, prev/next, and progress bar from stored progress.

2. **Continue card progress (Section 2)**  
   - Wire continue card to the same progress store (or to parsed progress_update notes as fallback).

3. **Optional (Sections 3 and 4)**  
   - Floating palette actions; persist dismissed continue card.

This order makes the steps feature fully functional first, then reuses the same progress data for the continue card so both areas stay in sync.
