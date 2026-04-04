# Purrl — Competitive Analysis

*Last updated: 2026-03-25*

## Branding
- **Name:** Purrl (cat pun)
- **Mascot:** Pink/colorful cat character (top of screen)
- **Visual style:** Soft pinks, whites, navy/deep blue text, rounded cards — similar warm aesthetic to Pattern Vault but pinker

## Navigation (Bottom Tab Bar)
| Tab | Icon | Notes |
|-----|------|-------|
| Counter | Clock/timer icon | First tab (default for new users) |
| Projects | Yarn ball icon | Main project management |
| Archive | Books/shelves icon | Completed/stored projects |
| Profile | Person icon | User settings |

**Comparison to Pattern Vault:** PV uses a different tab structure. Purrl separates Counter as its own top-level tab, suggesting row counting is a primary use case they prioritize. Archive as a separate tab (vs. filtering) is notable.

---

## Flow 1: First-Time User Onboarding

**Screen:** "Let's start your first project!"

Three entry paths presented as cards:

1. **Upload a Pattern** (PDF icon, pink badge: "Recommended for you")
   - "Upload a PDF and we'll organize all the instructions for you"
   - AI-powered PDF parsing is the primary recommended path

2. **Import from Ravelry** (cloud download icon, pink badge: "Recommended for you")
   - "Pull in projects from your Ravelry queue"
   - Imports from Ravelry queue (not just library)

3. **Start from Scratch** (pencil icon, no badge)
   - "Just a name and you're knitting in seconds"
   - Quick-start manual entry

- **Skip option:** "I'll do this later" link at bottom

**Takeaway:** Purrl leads with PDF upload as the #1 path, signaling their AI parsing is a core differentiator. Ravelry import is also prominently featured.

---

## Flow 2: Projects Screen (Main Hub)

**Top section — Tool Cards** (horizontal scroll):
- **Project Visualizer** — "Test different color palettes and patterns" (pink gradient card, palette icon)
- **Gauge Calculator** — "Adjust stitch counts for your gauge" (blue/teal gradient card, calculator icon)
- (Appears to scroll right for more tools)

**Active Projects section** (yarn ball emoji):
- Shows in-progress projects
- Loading state: "Untangling the notation..." with spinner and "This can take up to a minute" + Cancel button
- This confirms AI processing happens async after project creation

**Up Next section:**
- Queue/planning area with "+" button to add
- Empty state shows clipboard icon: "Your plan is empty!"
- Separate "+" FAB (pink, bottom-right) for quick-add

**Takeaway:** Purrl has dedicated tool cards (Visualizer, Gauge Calculator) that Pattern Vault lacks. The "Up Next" queue is a planning feature for organizing what to work on next.

---

## Flow 3: New Project (Upload PDF)

**Modal presentation** with three tabs at top:
| Tab | Icon | Description |
|-----|------|-------------|
| Type It | Pencil | Manual text entry |
| Upload PDF | Document | PDF upload + AI parse |
| Ravelry | Ravelry logo | Import from Ravelry |

**Form fields (Upload PDF tab):**
- **Project Name** (required) — pre-filled from AI: "Skull Sampler Socks"
- **Total Rows** (Optional)
- **Size** (Optional)
- **Notes** (Optional)
- **Pattern Link** (Optional)

**Instructions section:**
- AI-parsed instructions displayed as cards below the form
- Each instruction card shows:
  - Row range label: "rows 0-0:" (start-end format)
  - Instruction text
  - **Reorder controls** (up/down chevrons on left)
  - **Delete button** (orange X on right)
  - Disclosure chevron (expandable)

---

## Flow 4: Parsed Instructions Detail

AI successfully parsed a sock pattern into discrete steps:

| # | Row Range | Instruction |
|---|-----------|-------------|
| 1 | rows 0-0 | Using Judy's Magic Cast On and C1, CO 14 (16, 18) sts... |
| 2 | rows 0-0 | Knit one round, being sure to k the sts on N2 tbl... |
| 3 | rows 1-1 | Rnd 1 (increase): *K1, kfb, k to last 2 sts on N1... |
| 4 | rows 2-2 | Rnd 2: K all sts. |
| 5 | rows 0-0 | Repeat Rnds 1 & 2 until you have 28 (32, 36) sts... |
| 6 | rows 0-0 | Knit 4 more rounds in stockinette stitch with C1. |
| 7 | rows 0-0 | Repeat Cuff Rnd 1 for 10 rounds total... |
| 8 | rows 0-0 | Bind off using a stretchy method. |
| 9 | rows 0-0 | Weave in ends. Block sock if desired. |
| 10 | rows 0-0 | Repeat entire pattern for second sock. |

**Observations:**
- Row ranges are mostly "0-0" — AI couldn't assign specific row numbers to most steps (only steps 3 and 4 got real ranges)
- Each step is individually reorderable and deletable
- Steps are displayed pre-creation so user can review/edit before saving

**Manual add section** (bottom of instructions):
- **Start** and **End** text fields (for row range)
- **Instruction** text field
- **"+ Add Instruction"** button (outlined, light blue)
- **Cancel** / **Create** buttons (Create is pink/filled)

---

## Flow 5: Counter Tab (Dedicated Row Counter)

**Top area:**
- Purrl mascot (large, centered) + "Purrl" branding
- **"WORKING ON" dropdown** — shows current project name ("Skull Sampler Socks") with chevron to switch projects
- **"Hide Counter"** toggle button (collapsible)

**Counter widget:**
- Large card with dark plum border, pink background
- **"CURRENT ROW"** label + huge row number display (starts at 0)
- **Minus button** (sage green circle) and **Plus button** (pink circle) — large, thumb-friendly tap targets
- Three utility icons below counter:
  - **Repeat/sync icon** (left) — likely repeat section or reset
  - **Refresh/redo icon** (center) — likely undo last count
  - **Band-aid/stitch marker icon** (right) — likely stitch fix or lifeline marker

**Current Instruction card** (below counter):
- Knitting needles icon + "CURRENT INSTRUCTION" header
- Checkbox circle (top-right) — mark step complete
- Full instruction text displayed
- **Yarn color callout:** "C1 (dark purple)" — AI extracted yarn color references from the pattern
- **Section tag:** "Toe 1" — AI identified pattern section names
- **Step pagination:** "Step 1 of 6" with left/right arrows to navigate between steps

**Sections area:**
- **"Sections"** header with **"Edit"** button
- Section list: "1 Main Section" with pink numbered badge, "ACTIVE" status tag, chevron for drill-down
- Implies patterns can have multiple sections (e.g., Toe, Heel, Leg, Cuff)

**Notes area:**
- Inline "Add notes..." text field for per-project notes

**Progress Pics area** (partially visible):
- "Progress Pics" header with "+" button to add photos
- Photo journaling feature for documenting WIP

**Key Takeaways:**
- The counter is deeply integrated with parsed instructions — as you advance rows, it shows the current instruction
- AI extracts **yarn colors** and **section names** from the pattern, not just row text
- Step navigation (1 of 6) lets you page through instructions while counting
- Sections are a first-class concept with active/inactive state
- Progress photos are built into the counter flow, encouraging documentation while crafting

---

## Key Capabilities Summary

| Feature | Purrl | Pattern Vault |
|---------|-------|---------------|
| AI PDF parsing | Yes - Primary feature | Yes - Via Share Extension + Gemini |
| Row counter | Yes - Dedicated tab | Yes - In pattern detail |
| Ravelry import | Yes - Queue import | Yes - Library import + OAuth |
| Project Visualizer | Yes - Color palette tool | No |
| Gauge Calculator | Yes - Built-in tool | No |
| Up Next queue | Yes - Planning feature | No |
| Archive section | Yes - Separate tab | No (status-based) |
| Mascot | Yes - Cat ("Purrl") | Yes - Crow |
| Manual step editing | Yes - Before creation | Yes - After creation |
| Voice row counting | Not visible | Yes |
| Share Extension | Not visible | Yes |
| Step reordering | Yes - Up/down arrows | Yes |
| Yarn color extraction | Yes - AI extracts colors from text | No |
| Section detection | Yes - AI identifies pattern sections | No (flat step list) |
| Progress photos | Yes - Built into counter flow | No |
| Counter + instruction sync | Yes - Counter shows current step | Yes (row counter in detail) |
| Step pagination | Yes - "Step 1 of 6" navigation | Yes (scrollable list) |
| Project switcher in counter | Yes - Dropdown in counter tab | No (navigate to project first) |

## Notable UX Differences

1. **Counter as first-class tab** — Purrl treats row counting as a primary activity, not buried in pattern detail. Quick project switcher dropdown means you never leave the counter to change projects.
2. **AI extracts more than just steps** — Purrl's AI identifies yarn colors (e.g., "C1 (dark purple)") and section names (e.g., "Toe 1") from pattern text, creating a richer structured representation.
3. **Tool cards** — Purrl bundles utility tools (visualizer, gauge calc) prominently on the Projects screen.
4. **Up Next queue** — Project planning/prioritization feature PV doesn't have.
5. **Pre-creation editing** — Users review and edit AI-parsed steps before saving (PV does post-save editing).
6. **Three input modes in one modal** — Type It / Upload PDF / Ravelry as tabs in the same creation flow (PV separates these).
7. **Archive as navigation concept** — Separate tab for completed projects vs. PV's status filtering approach.
8. **Progress photos** — Built directly into the counter/project view for documenting WIP.
9. **Section-aware navigation** — Patterns are organized into named sections (Toe, Heel, etc.) with active/inactive status, not just a flat step list.
