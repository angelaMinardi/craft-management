# Corvid Craft — Complete Feature Testing Roadmap

Use this as a step-by-step walkthrough. Test on a real device where possible (camera, notifications, offline). Mark each item PASS / FAIL / PARTIAL and add notes.

---

## Prerequisites

- [ ] Fresh build from current branch (clean DerivedData if needed)
- [ ] Signed in to a test account with at least 3 saved patterns (1 Want to Make, 1 In Progress, 1 Completed)
- [ ] At least 1 pattern has a PDF attached
- [ ] At least 1 pattern has AI-parsed steps
- [ ] Ravelry OAuth configured (if testing Ravelry features)
- [ ] Premium subscription active (or use sandbox) for unlimited features

---

## Theme 1: Pattern Organization & Library Management

### 1.1 Multi-Source Import
- [ ] **URL import:** Patterns tab → Add → paste a blog URL → verify title, thumbnail, description auto-populate → Save
- [ ] **PDF import:** Add → attach a PDF from Files → verify it saves and is viewable
- [ ] **Share Extension:** Open Safari → navigate to a pattern page → tap Share → "Save to Corvid Craft" → verify pattern appears in library
- [ ] **Video URL:** Share a YouTube knitting tutorial URL → verify video_url is captured

### 1.2 Duplicate Detection
- [ ] Save a pattern by URL → try saving the same URL again → verify duplicate warning or prevention
- [ ] Save two patterns with different URLs but identical titles from the same site → verify DuplicatesListView catches them
- [ ] Settings → Duplicate detection → verify grouped duplicates display correctly

### 1.3 Visual Browsing
- [ ] Pattern list shows card grid with cover images (not just text)
- [ ] Cards show status badge (color + icon)
- [ ] Cards show craft type and difficulty chips
- [ ] Pull-to-refresh updates the list

### 1.4 Tags & Categories
- [ ] Open a pattern → Tags → verify 5 category sections (Craft Type, Difficulty, Project Type, Purpose, Other)
- [ ] Select multiple tags across categories → Save → verify tags appear on pattern detail
- [ ] Pattern list → verify tag filter pills appear → tap a tag → only matching patterns show
- [ ] Remove all tags → Save → verify clean state

### 1.5 Folders / Collections
- [ ] Open a pattern → "..." menu → "Move to folder..." → verify folder picker opens
- [ ] Tap "New folder..." → enter "Summer KAL" → verify folder is created
- [ ] Select "Summer KAL" → verify pattern is moved
- [ ] Open a second pattern → move to "Summer KAL"
- [ ] Pattern list → folder pills appear above status pills → tap "Summer KAL" → only 2 patterns show
- [ ] Tap "All" folder pill → all patterns show again
- [ ] Move a pattern to "No folder" → verify it leaves the collection

### 1.6 Ravelry Library Import
- [ ] Settings → Ravelry → Connect → complete OAuth flow
- [ ] Import my Ravelry library → verify patterns appear with deduplication
- [ ] Verify Ravelry favorites import
- [ ] Verify imported patterns have correct metadata (craft type, etc.)

### 1.7 Search
- [ ] Pattern list → type in search bar → results filter in real-time
- [ ] Search by partial title → verify match
- [ ] Search by description keyword → verify match
- [ ] Clear search → all patterns return
- [ ] Verify search is debounced (no lag on fast typing)

### 1.8 Status Filtering
- [ ] Status pills: "All", "Want to Make", "In Progress", "Done", "Frogged" all visible
- [ ] Tap each pill → correct patterns filter
- [ ] Filter sheet (funnel icon) → Status section shows all 5 options including Frogged
- [ ] Filter sheet → Difficulty section works (Beginner / Intermediate / Advanced)

---

## Theme 2: Working a Pattern — PDF & In-Session Experience

### 2.1 PDF Viewer
- [ ] Open a pattern with PDF → tap "View PDF" → PDF loads and displays
- [ ] Pinch to zoom → stays in place
- [ ] Scroll through pages → page indicator updates ("Page 2")
- [ ] Charts linked badge shows if chart highlights exist

### 2.2 PDF Reading Bar
- [ ] PDF opens → honey-colored semi-transparent band visible
- [ ] Drag the bar up and down → follows smoothly with drag handle on right
- [ ] Navigate away from PDF → return → bar is at the same position (persisted)
- [ ] Different patterns → each has independent bar position
- [ ] Bar doesn't interfere with chart highlight thumbnails at bottom

### 2.3 PDF Caching (Offline)
- [ ] Open a PDF while online → close it
- [ ] Turn off WiFi → reopen the same PDF → verify it loads from cache
- [ ] Open a pattern whose PDF was never loaded → verify error message (not cached)

### 2.4 Chart Extraction & Grid Overlay
- [ ] Pattern with PDF → tap "Detect Charts" (wand) → charts are extracted
- [ ] Chart thumbnail appears at bottom of PDF viewer
- [ ] Tap a chart → workspace opens with grid overlay
- [ ] Row/column counters work (up/down arrows for rows, left/right for columns)
- [ ] Grid alignment editor → drag edges → grid adjusts accurately

### 2.5 Chart Annotations
- [ ] In chart workspace → add a Pin marker → verify it places on the chart
- [ ] Add a Note marker → enter text → verify it saves
- [ ] Add Increase / Decrease / Repeat / Caution markers → each shows correct icon
- [ ] Long-press a marker to edit or delete

### 2.6 Pattern Content View
- [ ] Pattern with text content → "View Pattern Content" → renders headings, bullets, tables, paragraphs
- [ ] Edit mode (pencil icon) → tap blocks to remove them → "Save Changes" → blocks removed
- [ ] Reading bar is NOT present on text content view (removed per design feedback)
- [ ] Abbreviations in text are underlined and tappable (see Theme 7 Glossary tests)

### 2.7 Per-Step Notes
- [ ] Pattern with parsed steps → navigate to a step → "Add step note" button visible
- [ ] Tap it → AddNoteView opens with "Note for Step X" header
- [ ] Write and save a note → note appears inline below that step
- [ ] Navigate to a different step → the note is NOT shown (only on its step)
- [ ] Navigate back → note is still there
- [ ] Add a second note to the same step → both appear

---

## Theme 3: Row Counting & Progress Tracking

### 3.1 Global Row Counter
- [ ] Open a pattern in progress → steps tab → row counter visible
- [ ] Up arrow increments row, down arrow decrements
- [ ] Counter display updates: "Row X / Y" with numeric transition
- [ ] Row persists after closing and reopening the pattern

### 3.2 Secondary Counters
- [ ] Tap "+ Add" → configure: title, reset after N, link mode, color
- [ ] Counter chip appears below global counter
- [ ] Tap chip → increments; resets at configured value
- [ ] Long-press chip → edit sheet opens
- [ ] Configure maxResets → counter deactivates when reached

### 3.3 Row Reminders / Alerts
- [ ] Long-press the "Row X / Y" label → context menu shows "Add row reminder..."
- [ ] Tap it → reminder sheet opens with number input
- [ ] Enter row 5 → tap Add → notification permission prompt (first time)
- [ ] Bell icon appears next to counter
- [ ] Tap bell → sheet shows current reminders with delete option
- [ ] Increment counter to row 5 → local notification fires
- [ ] Delete the reminder → bell icon disappears
- [ ] Reminder persists after app restart

### 3.4 Voice / Hands-Free Counting
- [ ] Floating toolbar → "Progress" (mic icon) → voice sheet opens
- [ ] Say "Row 10" → counter jumps to 10 with TTS confirmation
- [ ] Say "Round 5" → same behavior

### 3.5 Inline Counter in Current Tab
- [ ] Set a pattern as Current Project → Current tab
- [ ] Up/down arrow buttons visible in progress section
- [ ] Tap up → row increments without leaving the tab
- [ ] Tap down → row decrements
- [ ] Verify the counter matches what's shown in pattern detail

### 3.6 Widget & Live Activity
- [ ] Home screen → add Corvid Craft widget → verify it shows pattern stats
- [ ] Lock screen → Row Tracker widget shows current row
- [ ] Increment row in app → widget updates

---

## Theme 4: Yarn Stash Management

### 4.1 Yarn Stash CRUD
- [ ] Stash & Tools → Yarn Stash → Add → fill brand, color, weight, yardage, quantity → Save
- [ ] Item appears in list with summary line
- [ ] Tap item → edit → change values → Save → verify update
- [ ] Swipe to delete → confirm → item removed
- [ ] Pull-to-refresh works

### 4.2 Barcode Scanner
- [ ] Add yarn → tap barcode icon (viewfinder) next to brand field
- [ ] Camera opens with scan target overlay and "Point at yarn label barcode" text
- [ ] Scan a barcode (any EAN-13/UPC) → haptic feedback → barcode string captured
- [ ] Barcode displays in the Details section of the form
- [ ] Save → reopen → barcode value persists

### 4.3 New Stash Fields
- [ ] Add yarn → Details section shows "Dye lot" and "Fiber content" fields
- [ ] Enter values → Save → reopen → values persist
- [ ] Edit existing item → new fields are populated from saved data

### 4.4 Needle/Hook Inventory
- [ ] Stash & Tools → Tools → Add → select type (needle/hook), enter size → Save
- [ ] Item appears in list
- [ ] Edit and delete work correctly

### 4.5 Stash-to-Pattern Matching
- [ ] Tap a yarn stash item → "Find patterns" → shows vault patterns matching weight
- [ ] Shows Ravelry results (if API keys configured)
- [ ] Yardage comparison shows enough/short/leftover

### 4.6 Ravelry Stash Import
- [ ] Settings → Ravelry (connected) → Import includes stash items
- [ ] Imported yarn shows brand, color, weight from Ravelry

---

## Theme 5: Project Tracking & WIP Management

### 5.1 Pattern Status Lifecycle
- [ ] New pattern defaults to "Want to Make"
- [ ] Tap status → "In Progress" → status badge updates (honey color, hammer icon)
- [ ] Tap status → "Completed" → sage green, checkmark
- [ ] Tap status → "Frogged" → dusty blue, back-arrow icon
- [ ] Next action banner text updates for each status
- [ ] Status pills scroll horizontally without wrapping (4 statuses fit)

### 5.2 Frogged Status Specifics
- [ ] Frogged pattern does NOT appear in Current Project picker
- [ ] If pattern was set as Current Project → frog it → Current tab clears automatically
- [ ] Pattern list → Frogged pill → only frogged patterns show
- [ ] Filter sheet → Frogged option available and works
- [ ] Frogged status persists after sign out and sign back in

### 5.3 Multiple Makes
- [ ] Pattern detail → "Add make" → enter size name → Save
- [ ] Make pill appears → tap to switch between makes
- [ ] Each make has independent row counter state
- [ ] Each make has independent step progress

### 5.4 Project Notes
- [ ] Add Note → 4 types visible: "General", "Materials", "Mods", "Progress"
- [ ] Segmented picker text does NOT wrap (labels shortened)
- [ ] Each type saves correctly
- [ ] Note photos: add photo → displays inline → remove photo works
- [ ] Premium limit: free tier → hit 20 photo limit → paywall prompt appears
- [ ] Note row shows: type badge, content preview (2 lines), absolute timestamp, duration chip if applicable

### 5.5 Session Time Tracking
- [ ] Floating toolbar → tap "Log time" → sheet opens
- [ ] Session Timer section: tap "Start" → clock counts up
- [ ] Dismiss sheet (Cancel) → timer keeps running → toolbar shows elapsed time in red
- [ ] Reopen "Log time" → timer still running → tap "Stop" → timer pauses
- [ ] "Resume" resumes from where it stopped
- [ ] "Reset timer" clears elapsed time
- [ ] "Or log manually" section: hour/minute wheel pickers still work as fallback
- [ ] With timer at 3 minutes → add optional note → tap "Save"
- [ ] Progress note created: "Logged 3m" or "Logged 3m - [your note]"
- [ ] Note row shows green clock chip "3m"
- [ ] Note detail shows "Session: 3 min" in timestamps

### 5.6 Goals & Deadlines
- [ ] Current tab → "Goal" quick action → GoalSettingView opens
- [ ] Toggle "Set a target finish date" → date picker appears
- [ ] Set date 14 days out → footer shows "14 days from now"
- [ ] Step milestones: tap "Set date" next to steps → date assigned
- [ ] Adjust dates in the "Adjust Dates" section → date pickers work
- [ ] Remove a milestone with X button → removed from list
- [ ] Save → Current tab shows goal summary card:
  - Days remaining countdown
  - Next milestone name and date
  - Milestone progress bar (X/Y complete)
- [ ] Overdue goal: set past date → shows "X days overdue" in red

### 5.7 Progress Photos & Sharing
- [ ] Floating toolbar → "Photo" button → photo picker opens
- [ ] Select a photo → haptic feedback → photo saves to pattern images
- [ ] Current tab → "Share" quick action → ProgressShareCardView opens
- [ ] Card shows: "Work in progress" label, pattern title, progress ring with %, row count, step count, craft type, crow mascot branding
- [ ] "Share Progress" button → iOS share sheet opens with rendered card image

---

## Theme 6: Chart Navigation

### 6.1 Chart Detection
- [ ] Pattern with PDF → "Detect Charts" wand button → AI runs
- [ ] Charts detected → thumbnails appear at bottom of PDF viewer
- [ ] Each thumbnail shows chart number badge

### 6.2 Chart Workspace
- [ ] Tap chart thumbnail → workspace opens
- [ ] Chart image displays with grid overlay
- [ ] Row counter: up/down arrows (chevrons, not +/-)
- [ ] Column counter: left/right arrows
- [ ] Counter values display "Row X/Y" and "Col X/Y"
- [ ] Grid highlight follows current row/column position

### 6.3 Grid Alignment Editor
- [ ] Open grid alignment → drag edges to reposition grid
- [ ] Inset sliders fine-tune left/top/right/bottom
- [ ] Grid cell count can be adjusted (rows/columns)
- [ ] Save → grid persists on next open

### 6.4 Chart Configuration
- [ ] Chart settings: worked flat vs. in-round toggle
- [ ] C2C (corner-to-corner) flag
- [ ] Sideways/rotated chart support
- [ ] Row/column overlay colors customizable
- [ ] Counter linking to secondary counters

### 6.5 Chart Annotations
- [ ] Place pin marker → shows at tapped position
- [ ] Place note → text entry → shows with note icon
- [ ] Place increase/decrease/repeat/caution markers → correct icons
- [ ] Edit/delete annotations via long press or tap

---

## Theme 7: AI Features

### 7.1 AI Step Parsing (On-Demand)
- [ ] Pattern with text content → Steps tab → "Analyze Steps" wand button
- [ ] Loading indicator shows during analysis
- [ ] Steps appear grouped by section (e.g., "Toe", "Heel Flap")
- [ ] Row numbers assigned correctly for explicitly numbered rows
- [ ] Sequential unnumbered instructions get auto-numbered (post-processing)
- [ ] Stitch counts extracted where present
- [ ] Step navigation: left/right chevrons or swipe to move between steps

### 7.2 AI Step Parsing (At Import)
- [ ] Save a new pattern via Share Extension → enrichment fires in background
- [ ] Pattern shows "Processing..." in list until enrichment completes
- [ ] After enrichment: metadata populated (craft type, difficulty, gauge, etc.)
- [ ] Steps parsed and available in pattern detail

### 7.3 AI Transparency
- [ ] Settings → Help → "How AI works in Corvid Craft" → sheet opens
- [ ] Three sections visible: "What the AI does", "Specific capabilities", "Technical note"
- [ ] Content explains: parsing (not generating), privacy, user control
- [ ] Done button dismisses
- [ ] Works in dark mode (no white-on-white text)

### 7.4 Abbreviation Glossary — Inline
- [ ] Open a pattern with parsed steps → instruction text shows underlined abbreviations
- [ ] Tap "k2tog" → glossary popover opens: "Knit 2 Together", description, "Knitting" badge, "Decreases" category
- [ ] Tap "sc" → shows "Single Crochet" with "Crochet" badge
- [ ] Tap an abbreviation NOT in glossary → opens Google search fallback
- [ ] Dismiss popover → returns to step view

### 7.5 Abbreviation Glossary — Standalone
- [ ] Stash & Tools → "Stitch Glossary" card → glossary opens
- [ ] Entries grouped by category (Basic Knitting, Cables, Decreases, etc.)
- [ ] Craft filter: tap "Knitting" → only knitting abbreviations show
- [ ] Craft filter: tap "Crochet" → only crochet abbreviations show
- [ ] Search bar: type "decrease" → filters to matching entries
- [ ] Search: type "k2tog" → finds by abbreviation
- [ ] Search: type "yarn over" → finds by full name
- [ ] Empty state: search for gibberish → mascot + "No abbreviations found"
- [ ] Count footer shows total entries (97+ abbreviations)

### 7.6 Repeat Handling
- [ ] Pattern with repeat instructions (e.g., "Repeat Rows 1-4 until...") → parsed as single instruction with repeat metadata
- [ ] Repeat step shows referenced row range and target info
- [ ] Active repeat creates secondary counter for cycle tracking

---

## Theme 8: Monetization & Pricing

### 8.1 Free Tier Limits
- [ ] Free account → verify 30 pattern limit → 31st pattern triggers paywall
- [ ] Free account → 5 AI analyses per month → 6th triggers limit message
- [ ] Free account → 20 note photos → 21st triggers upgrade prompt
- [ ] Ads display on free tier

### 8.2 Paywall
- [ ] Paywall shows feature list including "Your patterns stay yours — export anytime"
- [ ] Monthly and yearly subscription options displayed
- [ ] Prices visible before tapping (not hidden)
- [ ] GrowthOrchestrator: trigger a friction event → next paywall is suppressed

### 8.3 Premium Features
- [ ] Subscribe → ads disappear
- [ ] Pattern limit removed (can add 31+)
- [ ] AI analyses unlimited
- [ ] Note photos unlimited
- [ ] Row Tracker widget enabled

### 8.4 Trust Messaging
- [ ] Onboarding page 3 ("Your Stash & Goals") → "Your patterns are yours" card visible with lock shield icon
- [ ] Settings → About → "Your data: Private & exportable" row visible
- [ ] Paywall → last benefit row: "Your patterns stay yours — export anytime"

### 8.5 Data Export
- [ ] Settings → User Backup → Export → JSON file generated
- [ ] Share sheet appears → can save to Files, AirDrop, etc.
- [ ] Verify exported file contains all patterns with metadata

---

## Theme 9: Social & Community

### 9.1 Finished Project Share Card
- [ ] Complete a pattern → "..." menu → "Share finished project"
- [ ] Card generates with pattern title, yarn, needle size, notes, crow branding
- [ ] Share sheet opens with image

### 9.2 Progress Share Card
- [ ] Current tab → "Share" button → ProgressShareCardView opens
- [ ] Card shows: "Work in progress", title, progress ring %, row count, step count, craft type
- [ ] Crow mascot + "Corvid Craft" branding in corner
- [ ] "Share Progress" → iOS share sheet with rendered image

### 9.3 Ravelry Integration (Social)
- [ ] Pattern from Ravelry → source URL links to Ravelry page
- [ ] Open in Browser → Ravelry pattern page loads

---

## Theme 10: Accessibility

### 10.1 Dark Mode
- [ ] System Settings → Dark Mode → relaunch app
- [ ] All screens render correctly (no white-on-white or invisible text)
- [ ] Cards, backgrounds, and text have appropriate contrast
- [ ] AI Info sheet readable in dark mode

### 10.2 Reduce Motion
- [ ] System Settings → Reduce Motion ON
- [ ] App animations are disabled or minimal
- [ ] Counter pulse animation respects reduce motion
- [ ] Staggered entrance animations disabled

### 10.3 VoiceOver
- [ ] Enable VoiceOver → navigate through Pattern List
- [ ] Pattern cards read: title, status, craft type
- [ ] Row counter: accessible labels for increment/decrement
- [ ] Reading bar: "Reading bar, drag to mark your place"
- [ ] Glossary entries readable

### 10.4 Dynamic Type
- [ ] System Settings → increase text size to largest
- [ ] App text scales appropriately
- [ ] Cards don't overflow or clip
- [ ] Navigation still usable

---

## Theme 11: Data Portability & Trust

### 11.1 User Backup Export
- [ ] Settings → User Backup → Export → file generates
- [ ] File is a valid JSON with all pattern data
- [ ] Source URLs, PDF URLs, metadata all included

### 11.2 Offline Mode
- [ ] Load app with WiFi → visit several patterns (load notes, tags, PDFs)
- [ ] Turn off WiFi entirely
- [ ] Kill app → relaunch → sign-in succeeds (cached session)
- [ ] Pattern list loads from cache
- [ ] Pattern images display (if previously loaded)
- [ ] Open a pattern → notes load from cache
- [ ] Tags load from cache
- [ ] Open a previously-viewed PDF → loads from local cache
- [ ] Offline banner: "Offline — using cached data" appears in honey color at top
- [ ] Turn WiFi back on → banner dismisses
- [ ] Fresh data loads on next pull-to-refresh

### 11.3 Trust Messaging
- [ ] Fresh install → Onboarding page 3 → "Your patterns are yours" card with lock shield
- [ ] Settings → About → "Your data: Private & exportable"
- [ ] Paywall → "Your patterns stay yours — export anytime"

---

## Theme 12: Mascot & Gamification

### 12.1 Mascot Dashboard
- [ ] Home tab → mascot panel shows: hearts, streak, thread points
- [ ] Tap mascot → petting animation plays
- [ ] Pet cooldown: can't pet again for 12 seconds

### 12.2 Mascot Store
- [ ] Dashboard → Store → treats and decorations available
- [ ] Purchase a treat with thread points → inventory updates
- [ ] Drag treat onto mascot → feeding animation

### 12.3 Progress Milestones
- [ ] Progress a pattern to 25% completion → "Quarter of the way there!" celebration fires
- [ ] Continue to 50% → "Halfway point!" celebration
- [ ] Continue to 75% → "Almost there!" celebration
- [ ] Complete pattern → "You finished!" celebration
- [ ] Each milestone awards thread points
- [ ] Milestones are one-time (don't re-fire on same pattern)

### 12.4 Achievements
- [ ] Settings → Celebrations → view unlocked milestones
- [ ] "first_pattern", "vault_10", "stash_started", "toolbox_ready", "first_note" all trackable
- [ ] Progress milestones (progress_25/50/75/100) appear in list after being unlocked

---

## Theme 13: Onboarding & Tutorials

### 13.1 Onboarding Flow
- [ ] Fresh install → 5-page onboarding
- [ ] Page 0: Name your companion
- [ ] Page 1: Notifications permission
- [ ] Page 2: Craft selection (knitting, crochet, etc.)
- [ ] Page 3: Stash & Goals + "Your patterns are yours" trust card
- [ ] Page 4: Summary + "Finalize"

### 13.2 App Tutorial
- [ ] Settings → Help → "Show app tutorial" → tutorial overlay starts
- [ ] Tutorial walks through main screens with anchored highlights
- [ ] Can be skipped

### 13.3 Widget Onboarding
- [ ] First use of widget features triggers widget onboarding sheet

---

## Cross-Cutting Concerns

### C.1 Performance
- [ ] Pattern list with 30+ patterns → scrolls smoothly
- [ ] Search debounce: no lag when typing fast
- [ ] AI parsing completes within reasonable time (< 30 seconds)
- [ ] Image loading: thumbnails load progressively, no blank cards

### C.2 Error Handling
- [ ] Network error during pattern save → error message shown
- [ ] AI parsing fails → error message with retry option
- [ ] Invalid URL paste → appropriate feedback
- [ ] Supabase down → cached data displays, operations queue gracefully

### C.3 Memory & Storage
- [ ] App does not crash on low memory devices
- [ ] PDF cache respects 500MB limit
- [ ] Image cache respects 200MB limit with LRU eviction
- [ ] No excessive battery drain from timers or network polling

---

## Final Score Revalidation

After completing all tests, rescore each theme 1-10 based on actual behavior:

| Theme | Pre-Test Score | Post-Test Score | Notes |
|---|---|---|---|
| 1. Pattern Organization | 8 | | |
| 2. PDF/In-Session | 7 | | |
| 3. Row Counting | 8 | | |
| 4. Stash Management | 5 | | |
| 5. WIP Tracking | 8 | | |
| 6. Chart Navigation | 7 | | |
| 7. AI Features | 7 | | |
| 8. Monetization | 6 | | |
| 9. Social | 5 | | |
| 10. Accessibility | 6 | | |
| 11. Data Portability | 5 | | |
| **Overall** | **6.9** | | |
