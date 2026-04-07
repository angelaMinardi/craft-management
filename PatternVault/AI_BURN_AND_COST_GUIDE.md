# Managing AI burn and cost outflow

Step-by-step guide to capping AI spend and avoiding runaway costs when free users spike before ad revenue (and subscriptions) catch up.

---

## 1. Know your numbers

- **AI cost per free user per month (max):** 5 analyses × ~$0.02–0.05 each → **~$0.10–0.25**. Use **$0.20** for a conservative budget.
- **Ad revenue per free user per month:** ~$0.05–0.15 depending on sessions and region. Use **$0.10** as a cautious estimate.
- **Gap:** You can be **~$0.10–0.15 in the red per free user per month** until ads (or subs) grow. A sudden 500 free users = **~$50–75/month** extra AI cost with limited ad offset at first.

The goal: cap and monitor so a surge of free users doesn’t hemorrhage money.

---

## 2. Set a monthly AI budget and “circuit breaker”

- **Fixed monthly cap:** e.g. **$50 or $75/month** for AI (Share Extension + main app “Analyze Steps”). This is separate from your $200 launch reserve; the reserve is the pool, the monthly cap is how fast you allow it to be spent.
- **Circuit breaker:** If AI spend in a calendar month exceeds that cap, **stop using the paid AI provider** for the rest of the month (see Step 5). Free users hit the “5 per month” limit naturally; the breaker stops *total* spend from blowing up if user count spikes.

Result: Even with a viral spike, your max AI burn is capped each month.

---

## 3. Track what you can’t see in the app

- **In the product you already have:**
  - Supabase `user_entitlements`: `ai_usage_this_month` (and `usage_month`) tell you **how many AI uses** each user has.
  - You don’t have **cost in dollars** in-app; that’s in the AI provider’s dashboard (Anthropic, Google, etc.).
- **What to do:**
  - **Weekly:** In Supabase SQL Editor, run:
    ```sql
    SELECT usage_month, SUM(ai_usage_this_month) AS total_ai_uses
    FROM user_entitlements
    WHERE usage_month = to_char(now(), 'YYYY-MM')
    GROUP BY usage_month;
    ```
  - **Weekly:** In your AI provider billing/usage dashboard, note **actual spend** for the current month.
  - **Simple spreadsheet:** Columns = Week, Total AI uses (from Supabase), AI spend (from provider), Free MAU (approx from auth or analytics), Ad revenue (from AdMob). One row per week so you see trend and “burn vs ad revenue”.

This gives you a repeatable process so you see spikes (users or uses) before they turn into a surprise bill.

---

## 4. Decide how to enforce the monthly cap (operationally)

- **Option A – Manual (no code):**
  - When your weekly check shows AI spend has reached e.g. 80% of your monthly cap, **stop or reduce** paid acquisition and focus on organic only.
  - When you hit 100% of cap, you **temporarily disable** AI (see Step 5) until next month.
  - You’ll need a way to “turn off” AI in production (feature flag, config, or commenting out the call and shipping an update).
- **Option B – Semi-automated (recommended when you have 5 minutes):**
  - Once per week, you run the Supabase query and check provider spend.
  - If `(total_ai_uses_this_month * your_cost_per_call)` > monthly cap, you flip a kill switch (see Step 5) and leave it off until the 1st.

No need to build real-time billing in the app; weekly checks + a simple kill switch are enough to prevent hemorrhage.

---

## 5. Kill switch (implemented)

The app reads a single flag from Supabase (`app_config.ai_enabled`). When you set it to `false`, AI is disabled in both the Share Extension and the main app (“Analyze Steps” wand). Saves still work; only the AI analysis is skipped.

### One-time setup

1. Run the migration that creates the table and row:
   - In **Supabase Dashboard → SQL Editor**, paste and run the contents of **`supabase_migrations/013_app_config.sql`**.
   - That creates `app_config` with one row: `id = 1`, `ai_enabled = true`.

### How to turn AI off (hit the kill switch)

1. Open **Supabase Dashboard** for your project.
2. Go to **Table Editor** and select the **`app_config`** table.
3. Find the row with **id = 1**.
4. Set **`ai_enabled`** to **`false`** (toggle off or edit to false).
5. Save.

Within about 10–15 minutes (or as soon as the user next opens the app or uses the Share Extension), all AI calls stop:
- **Share Extension:** Saves still work; metadata comes from page/PDF only (no AI analysis).
- **Main app:** “Analyze Steps” shows: “Step analysis is temporarily unavailable. Try again next month.”

No app release required. To turn AI back on, set **`ai_enabled`** back to **`true`** in the same table and save.

---

## 6. Protect the $200 launch reserve

- **Reserve = $120–150** (from your financial plan). Treat it as “max AI + acquisition” for the launch period.
- **Rule:** Don’t spend more than **$50–75 in a single month** from that reserve on AI. If you hit that in week 2, turn on the kill switch for the rest of the month (Step 5).
- **Ad revenue:** As soon as AdMob starts paying, put that revenue in a separate mental (or real) bucket: “ad revenue first pays for AI; what’s left goes to growth.” That way, a surge of free users is partly funded by their own ad views.

---

## 7. If free users spike before ads do

- **Immediate:**
  - Check AI provider usage and spend.
  - If spend is above your monthly cap (or will be at current run rate), enable the kill switch (Step 5).
  - Free tier still allows 5 AI uses per user per month; they’ll hit that limit and get the paywall. You’re just not allowing *unlimited* burn from a huge number of new users.
- **Short-term:**
  - Rely on **organic only** (no extra paid acquisition) until ad revenue + a few subs bring you back to a comfortable buffer.
  - Optionally, **temporarily lower** the free AI limit (e.g. 5 → 3) in code and in Supabase (e.g. `increment_ai_usage` logic) and in your app store description, then restore later. That’s a product decision; the kill switch is the fast lever.

---

## 8. Weekly checklist

1. Run the Supabase query for `usage_month` and `SUM(ai_usage_this_month)` for the current month.
2. Check AI provider billing for current-month spend.
3. If spend ≥ 80% of monthly cap → stop paid acquisition and plan to flip the kill switch at 100%.
4. If spend ≥ 100% of monthly cap → enable kill switch until next calendar month.
5. Log in your spreadsheet: AI uses, AI spend, free MAU (if you have it), ad revenue.
6. Once a month: compare ad revenue vs AI cost; adjust cap or limits if you’re consistently over.

---

## Summary

- **Cap monthly AI spend** (e.g. $50–75) and **enforce it with a kill switch** so a random surge of free users can’t hemorrhage money.
- **Track** AI uses (Supabase) and AI spend (provider) weekly; compare to ad revenue.
- **Reserve ($120–150)** is your guardrail; don’t blow it in one month.
- **Kill switch** = Supabase **Table Editor → app_config → set ai_enabled to false**. Disables paid AI in both Share Extension and main app; saves and the rest of the app keep working.
