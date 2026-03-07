# Pattern Vault iOS — Testing & Approval Gates

Use this guide to test at each milestone. **Approve each milestone before the next set of tasks is implemented.**

---

## Supabase setup (auth + project URL)

Follow these steps once to get auth working and give the app your project URL and key.

### 1. Create or open a Supabase project

- Go to [supabase.com](https://supabase.com) and sign in.
- **New project:** Click **New project**, pick an organization, choose a name (e.g. `pattern-vault`), set a database password (save it somewhere), pick a region, then **Create new project**.
- **Existing project:** If you already have a project (e.g. for the Pattern Vault web app), open it from the dashboard.

### 2. Get your Project URL and anon key

- In the Supabase dashboard, open your project.
- In the left sidebar click **Project Settings** (gear icon at the bottom).
- Under **General**, find **Project URL**. It looks like:  
  `https://xxxxxxxxxxxx.supabase.co`  
  Copy this — this is your **SUPABASE_URL**.
- In the same **Project Settings** page, open the **API** section.
- Under **Project API keys**, find **anon** / **public**. Click **Reveal** and copy the key (long string).  
  This is your **SUPABASE_ANON_KEY**.  
  (The anon key is safe to use in the app; Row Level Security keeps data protected.)

### 3. Turn on Email auth

- In the left sidebar go to **Authentication** → **Providers**.
- Find **Email** and make sure it’s **Enabled**.
- For quick testing without email verification:
  - Expand **Email** and turn **OFF** “Confirm email”.
  - Then users can sign in right after sign-up.
- (Optional) Under **Authentication** → **URL Configuration**, set **Site URL** to e.g. `https://yourapp.com` for production; for local testing the default is fine.

### 4. Put the URL and key into the iOS app

You can do this in Xcode in one of two ways.

**Option A — Build Settings (simplest)**

1. Open **PatternVault.xcodeproj** in Xcode.
2. In the project navigator (left), click the blue **PatternVault** project.
3. Under **TARGETS**, select **PatternVault**.
4. Open the **Build Settings** tab.
5. In the search box type **SUPABASE**.
6. You’ll see **SUPABASE_ANON_KEY** and **SUPABASE_URL** (under “User-Defined” or “Custom”).
7. Double‑click the value for **SUPABASE_URL** and replace `https://placeholder.supabase.co` with your Project URL (e.g. `https://xxxxxxxxxxxx.supabase.co`). No quotes.
8. Double‑click **SUPABASE_ANON_KEY** and replace `placeholder-anon-key` with your anon key. No quotes.
9. Do this for both **Debug** and **Release** if they’re listed separately (or change once if there’s a single row).

**Option B — Config file (keeps secrets out of the project)**

1. In Finder, go to the **PatternVault** folder (same level as **PatternVault.xcodeproj**).
2. Open the **Config** folder. Duplicate **Config.xcconfig.example** and rename the copy to **Config.xcconfig**.
3. Open **Config.xcconfig** in a text editor. Replace the placeholders:
   - `SUPABASE_URL = https://your-project.supabase.co`  
     → your real Project URL (e.g. `https://xxxxxxxxxxxx.supabase.co`).
   - `SUPABASE_ANON_KEY = your-anon-key-here`  
     → your real anon key.
4. In Xcode, click the blue **PatternVault** project → select the **PatternVault** project (not the target) in the left column.
5. In the main editor, under **Configurations**, you’ll see **Debug** and **Release**. For each:
   - Click the arrow to expand.
   - Under **PatternVault** (the app target), set the configuration to **Config** (or the name of your config file). If **Config** doesn’t appear, add it: **File** → **New** → **File** → **Configuration Settings File**, name it **Config**, then in **Project** → **Info** → **Configurations** assign **Config** to Debug and Release for the PatternVault target.
6. So that **Config.xcconfig** is used: select the **PatternVault** project, go to **Info** tab, under **Configurations** set **Debug** and **Release** for the **PatternVault** target to **Config** (dropdown).  
   If you don’t have a “Config” option yet: add the **Config.xcconfig** file to the project (drag it into the project navigator; leave “Copy items” unchecked). Then in **Project** → **Info** → **Configurations**, for the **PatternVault** target set both Debug and Release to use **Config**.
7. Add **Config.xcconfig** to **.gitignore** so you don’t commit your real keys (e.g. add a line `Config/Config.xcconfig`).

**Check that the app gets the values**

- The app reads them via **Info.plist** (which gets `$(SUPABASE_URL)` and `$(SUPABASE_ANON_KEY)` from Build Settings or from the xcconfig). So after Option A or B, a clean build and run is enough.
- If you use Option B, make sure the **PatternVault** target’s **Build Settings** still show **SUPABASE_URL** and **SUPABASE_ANON_KEY** when you search (they can come from the xcconfig). If not, the project may need the xcconfig set as the target’s base configuration (see Xcode’s “Based on Configuration File” for the target).

**Quick reference**

| What        | Where in Supabase                         | Use in app        |
|------------|--------------------------------------------|-------------------|
| Project URL | Project Settings → General → Project URL   | `SUPABASE_URL`    |
| Anon key    | Project Settings → API → anon public key   | `SUPABASE_ANON_KEY` |
| Email auth  | Authentication → Providers → Email → Enable | (no value in app) |

### 5. Run the app

- Choose an iOS simulator (e.g. **iPhone 16**) or a device.
- Press **Run** (▶). The app should launch; sign up with an email and password to confirm auth is working.

---

## Milestone 1 — Auth & app shell (current)

**What’s included:** App launch, sign in / sign up with email, main tabs (Home, Patterns, Settings), sign out.

**How to test:**

1. Launch the app. You should see the **Sign In** screen (or Sign Up if you use “Create an account”).
2. Tap **Create an account** and sign up with an email and password (min 6 characters). You should land on the main tab bar (Home, Patterns, Settings).
3. Tap **Settings** → **Sign Out**. You should return to the Sign In screen.
4. Sign in again with the same email/password. You should be back on the main tabs.
5. Home shows “Get started”; Patterns shows “Your patterns will appear here.”

**Approve to continue:** Once this works for you, tell me you approve and I’ll implement **Milestone 2** (pattern list, add pattern, pattern detail, dashboard counts).

---

## Milestone 2 — Patterns (current)

**What's included:** Add pattern by URL, pattern list with search and status filter, pattern detail (edit, change status, delete), dashboard with counts and recent patterns.

**Before testing — create the database table:**

1. Go to Supabase Dashboard → **SQL Editor** (left sidebar).
2. Click **New query**.
3. Paste the contents of `supabase_migrations/001_create_patterns.sql` (in the project folder).
4. Click **Run**. You should see "Success. No rows returned."

**How to test:**

1. Build and run the app (Cmd+R).
2. Sign in (email or Google).
3. On the **Home** tab, you should see "No patterns yet."
4. Tap the **Patterns** tab → tap the **+** button (top right).
5. Paste a URL (e.g. `https://www.ravelry.com/patterns/library/cozy-cardigan`), add a title (e.g. "Cozy Cardigan"), pick a status, tap **Save**.
6. The pattern should appear in the Patterns list.
7. Tap the pattern → you should see the detail screen with link, status, and delete.
8. Change the status (e.g. to "In Progress") → it should update.
9. Go back to **Home** → you should see the counts and the pattern under "Recent."
10. Pull down to refresh on either tab.
11. Sign out and sign in again → your patterns should still be there.

**Approve to continue:** Once patterns work, tell me and I'll implement **Milestone 3** (project notes with four types + photos).

---

## Milestone 3 — Project Notes

**What's included:** Four note types (General, Yarn Info, Modifications, Progress Update), add/edit/delete notes on any pattern, optional photo attachment via Supabase Storage.

**Before testing — create the database table and storage:**

1. Go to Supabase Dashboard → **SQL Editor**.
2. Paste and run `supabase_migrations/002_create_project_notes.sql`.
3. (Optional) For photo support, run in SQL Editor:
   ```sql
   INSERT INTO storage.buckets (id, name, public) VALUES ('note-photos', 'note-photos', true);
   CREATE POLICY "Users can upload note photos" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'note-photos');
   CREATE POLICY "Public read access for note photos" ON storage.objects FOR SELECT TO public USING (bucket_id = 'note-photos');
   CREATE POLICY "Users can delete own note photos" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'note-photos');
   ```

**How to test:**

1. Build and run (Cmd+R). Sign in.
2. Navigate to an existing pattern's detail view.
3. You should see a **Notes (0)** section with a **+** button.
4. Tap **+** → the Add Note sheet appears.
5. Select **General** type, write "This would make a great gift", tap **Save**.
6. The note should appear in the Notes section with a blue icon.
7. Add a **Yarn Info** note: "Caron Simply Soft in Sage Green, 3 skeins".
8. Add a **Modifications** note: "Added 2 extra rows for length".
9. Add a **Progress Update** note: "Finished the back panel".
10. Verify each note shows the correct type icon/color and content preview.
11. Tap a note → detail view shows full content, timestamps.
12. Tap the **...** menu → **Edit** → change the content → **Save** → verify it updated.
13. Tap **...** → **Delete** → confirm → note is removed from list.
14. (Photo test) Add a note with a photo → verify photo preview shows in Add Note sheet → save → photo appears in note detail.
15. Pull to refresh → notes reload.
16. Go back, then return to the pattern → notes should still be there.
17. Sign out, sign in → notes persist.

**Edge case tests:**

- [ ] Try saving a note with empty content → Save button should be disabled
- [ ] Try saving a note with only whitespace → should be treated as empty
- [ ] Add a note with very long content (1000+ chars) → verify it saves and truncates in list view
- [ ] Delete a pattern that has notes → verify notes are cascade-deleted (check Supabase)
- [ ] View a pattern with 0 notes → empty state shows "No notes yet"
- [ ] Add 20+ notes to one pattern → verify scrolling works
- [ ] Pick a photo then cancel the sheet → verify no upload occurs
- [ ] View a note with a broken photo URL → should show "Photo unavailable" placeholder

---

## Milestone 4 — Tags & Filters

**What's included:** Built-in tag system with 18 tags across 4 categories (Craft Type, Difficulty, Project Type, Purpose). Tag picker on pattern detail, tag filter chips on pattern list.

**Before testing — create the database tables:**

1. Go to Supabase Dashboard → **SQL Editor**.
2. Paste and run `supabase_migrations/003_create_tags.sql`.
3. Verify in **Table Editor** that `tags` table has 18 rows and `pattern_tags` table exists.

**How to test:**

1. Build and run (Cmd+R). Sign in.
2. Navigate to a pattern's detail view.
3. You should see a **Tags** section with "Add Tags" button.
4. Tap the pencil icon or "Add Tags" → tag picker opens with categories.
5. Select: Crochet, Easy, Blanket, Gift Idea → tap **Save**.
6. Tags should appear as capsule chips on the pattern detail.
7. Go back to **Patterns** list → tag filter chips should appear below the status filter.
8. Tap **Crochet** chip → only patterns tagged "Crochet" should show.
9. Tap **Easy** chip too → patterns tagged with either should show.
10. Tap both chips again to deselect → all patterns show.
11. Combine status filter + tag filter + search → all three should work together.
12. Edit tags on a pattern → remove a tag → verify it's removed.
13. Delete a pattern with tags → verify `pattern_tags` rows are cleaned up.

**Edge case tests:**

- [ ] Pattern with 0 tags → shows "Add Tags" button
- [ ] Pattern with 10+ tags → verify all display and wrap correctly
- [ ] Filter by a tag no patterns have → empty list
- [ ] Filter by tag + status + search simultaneously → all compose correctly
- [ ] Rapidly toggle tags on/off → no race conditions
- [ ] Sign out, sign in → tags persist on patterns

---

## Milestone 5 — Share Extension

**What's included:** Share URLs from Safari, TikTok, YouTube, or any app directly into Pattern Vault. URL is pre-filled in the Add Pattern sheet.

**Prerequisites:**

1. In Xcode, ensure the **SaveToPatternVault** extension target is properly configured:
   - Bundle ID: `com.patternvault.app.SaveToPatternVault`
   - App Group: `group.com.patternvault.app` (enabled on both main app and extension targets)
2. Build and install both targets on a device or simulator.

**How to test:**

1. Open **Safari** on the device/simulator.
2. Navigate to a pattern URL (e.g. a Ravelry pattern page).
3. Tap the **Share** button → find **Save to Pattern Vault** in the share sheet.
4. Tap it → the app should open with the Add Pattern sheet, URL pre-filled.
5. Add a title, tap **Save** → pattern is saved.
6. Repeat with a **YouTube** video URL → verify platform detects as "YouTube".
7. Repeat with an **Etsy** listing URL → verify platform detects as "Etsy".

**Edge case tests:**

- [ ] Share a TikTok URL (uses redirect URLs) → verify URL extraction works
- [ ] Share plain text that isn't a URL → extension should close gracefully
- [ ] Share while not logged in → app should prompt login first
- [ ] Share while offline → appropriate error message
- [ ] Share a very long URL (500+ chars) → verify it's handled
- [ ] Cancel the share extension → verify no orphaned data
- [ ] Share from Instagram → verify URL is captured

---

## Milestone 6 — Polish (after approval)

**Planned:** Design system (colors, typography, spacing), empty state improvements, loading skeletons, error toasts, accessibility (VoiceOver, Dynamic Type), haptic feedback.

**Edge case tests to plan for:**

- [ ] VoiceOver enabled → all elements labeled
- [ ] Largest Dynamic Type → layout doesn't break
- [ ] No network → error states show
- [ ] Slow network → loading states appear
- [ ] iPhone SE (smallest device) → no layout overflow
- [ ] iPad → layout adapts
- [ ] Dark mode → all colors have dark variants
- [ ] Kill app mid-operation → no data corruption
- [ ] Rapidly tap buttons → no duplicate submissions
