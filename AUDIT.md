# Corvid Craft — Security & Readiness Audit

**Date:** 2026-06-24
**Version audited:** v1.0 (build 9), `main`
**Surfaces:** iOS app · Supabase backend · App Store readiness · website + legal
**Method:** Static code review + **live verification** against the production Supabase project (`fbzbnztvanuiijzymckn`) via RLS/policy/function dumps and the Supabase security advisor, git-history secret scan, and live fetches of the legal pages.
**Lens:** launch-blockers first. No code was changed in this pass.

> Severity: **P0** = security / data-leak / launch-blocker · **P1** = rejection risk or correctness · **P2** = reliability / architecture · **P3** = accessibility / hardening · **P4** = legal / website / polish.

---

## Executive summary

The app is well-built in most respects — secrets are *not* committed, core tables have correct RLS, auth uses Keychain + PKCE + nonce, account deletion is robust, and the paid-feature gate is correctly driven by StoreKit (so it is **not** bypassable via the database). The issues that matter cluster on the **backend storage and entitlement layer**, where several policies are more permissive than intended.

Two findings should be fixed **before any wider release**: user content (note photos, pattern PDFs) is stored in **public, listable storage buckets**, and the **AI/YouTube cost controls are trivially bypassable** because the entitlement row is client-writable and the usage RPCs are anon-callable.

| Severity | Count | Headlines |
|---|---|---|
| **P0** | 2 | Public storage buckets expose user content; AI/usage cost-controls bypassable |
| **P1** | 4 | Edge-function SSRF; bare WKWebView; unauthenticated web parser (cost abuse); over-exposed `SECURITY DEFINER` functions |
| **P2** | 6 | God-object view; chart-pipeline state; concurrency safety; cache hygiene; thin tests; RLS-enabled-no-policy tables |
| **P3** | 5 | No Dynamic Type; VoiceOver gaps; color-only info; leaked-password protection off; misc DB hardening |
| **P4** | 4 | Privacy-policy gaps (GDPR/CCPA, sub-processors, Ravelry); terms gaps; contact mismatch; site config |

**Corrected during verification (not issues):** missing photo-library permission string (app uses out-of-process `PhotosPicker` — none needed); broken privacy URL (`corvidcraft.com/privacy` is live and correct); "007 PDF leak unfixed" (writes *were* hardened in 015–017 — the remaining issue is the bucket being public, below); DEBUG AI bypass (correctly gated to simulator only).

---

## Remediation status (2026-06-24)

**Applied to production & verified** (migrations `033`, `035`, `036`; confirmed via advisor + grant dump):
- **P0-1 (listing):** dropped the broad public `SELECT` policies on `pattern-pdfs`, `pattern-images`, `note-photos` — buckets can no longer be enumerated. *(Buckets are still public-by-URL; see "Still open" for the optional private-bucket upgrade.)*
- **P0-2 / P1-4:** usage RPCs now assert `auth.uid() = p_user_id`; `anon`/`PUBLIC` `EXECUTE` revoked on every `SECURITY DEFINER` function; dead lifetime functions locked to `service_role`; `count_notes_with_photo` scoped to the caller; `set_updated_at` search_path pinned. Advisor `0028` (anon-executable) fully cleared.
- **`set_premium` RPC (migration `037`):** added so the app can set premium without writing the column directly.
- **Post-review fix (migration `038`, 2026-06-27):** `set_premium` had picked up an explicit `anon` EXECUTE grant from Supabase default privileges on creation (037's `REVOKE FROM public` didn't remove it). Not exploitable (the function `RAISE`s when `auth.uid()` is null) but revoked for least privilege; advisor re-confirmed no anon-executable functions remain.
- **P1-1 (SSRF):** ✅ deployed — `enrich-pattern` **v7**, SSRF guard live, `verify_jwt` now `true`.
- **P1-3 (parser abuse):** ✅ deployed & verified — origin guard returns 403 to non-site callers; `GEMINI_API_KEY` configured as a **separate restricted key**; parser functional.
- **P4-1/P4-2 (legal):** ✅ deployed — sub-processor table, GDPR/CCPA rights, in-app deletion, terms account-deletion/subscription sections; support contact standardized to `support@corvidcraft.com`.

**Fixed in code — pending the next app build:**
- **P0-2 (column lock):** migration `034` + app change (`EntitlementRepository.setPremium` → `set_premium` RPC). ⚠️ Apply `034` **with** the next app build — applying it sooner breaks premium for the shipped build 9.
- **P1-2 (WebView):** replaced bare `WKWebView` with `SFSafariViewController` (`SafariView`). Ships with next build.

**Still open (deliberately deferred):**
- **P0-1 (optional upgrade):** make `note-photos`/`pattern-pdfs` *private* with signed URLs — breaking; needs coordinated app + Share Extension changes.
- **P3-4:** enable Leaked Password Protection (Supabase Auth dashboard toggle — not code).
- **P2 / P3:** god-object decomposition, chart-pipeline state machine, concurrency/cache/test work, Dynamic Type & VoiceOver — multi-day efforts, not launch-blocking.
- **P4-3/P4-4:** standardize the public support contact; confirm CI `TEST_HOST` isn't a dead host.

---

## P0 — Security & data-leak (launch-blocking)

### P0-1 · User content lives in public, listable storage buckets
**Surface:** Supabase Storage · **Location:** `storage.buckets` (`note-photos`, `pattern-pdfs`, `pattern-images`); migrations `007`, `015–019`

**Evidence (live):** All three buckets have `public = true`. The advisor (`lint 0025 public_bucket_allows_listing`) flags all three for having a broad `SELECT` policy for the `public` role on `storage.objects` (e.g. `Pattern PDFs read` → `qual: (bucket_id = 'pattern-pdfs')`, `roles: {public}`). A public bucket serves every object by URL **without authentication**, and the broad `SELECT` policy additionally allows the storage **list** API to enumerate object keys.

**Impact:** Note photos are personal project photos; pattern PDFs are frequently *paid/copyrighted* third-party patterns the user uploaded. Both are anonymously downloadable by URL and enumerable by key (`<userId>/<patternId>/pattern.pdf`). This is a user-privacy exposure and a potential copyright-liability exposure.

**Fix:**
- Make `note-photos` and `pattern-pdfs` **private** buckets; serve them through short-TTL signed URLs (`createSignedUrl`). The Share Extension upload path already namespaces by `userId`, so only the read path changes.
- If `pattern-images` must stay public for sharing, **drop the broad `SELECT` policy** so the bucket can't be listed (public buckets serve by URL without any `SELECT` policy).

### P0-2 · AI / YouTube cost-controls are bypassable (client-writable entitlement + anon RPCs)
**Surface:** Supabase RLS + RPC · iOS `EntitlementRepository`
**Location:** `user_entitlements` UPDATE policy; [EntitlementRepository.swift:75](PatternVault/PatternVault/Repositories/EntitlementRepository.swift:75); `increment_ai_usage` / `increment_youtube_imports`

**Evidence (live):**
- `user_entitlements` UPDATE policy is `roles: {public}, qual: (auth.uid() = user_id), with_check: null` — **no column restriction**. The app writes premium status with a *direct table update* (`setPremium` → `.from("user_entitlements").update(SetPremiumPayload(is_premium:…))`), so the column is client-controlled.
- `increment_ai_usage(p_user_id uuid)` and `increment_youtube_imports(p_user_id uuid)` are `SECURITY DEFINER`, take the user id **as a parameter with no `auth.uid()` check**, and (advisors `0028`/`0029`) are `EXECUTE`-able by **`anon`** and `authenticated`.

**Impact:** A signed-in user can `PATCH /rest/v1/user_entitlements?user_id=eq.<self>` to set `ai_usage_this_month = 0` / `youtube_imports_this_month = 0` (unlimited AI parses & YouTube imports despite the free caps) or `is_premium = true` (server RPCs then grant premium caps). Separately, **anyone** can call `increment_ai_usage(<victim_uuid>)` to exhaust another user's monthly AI quota. All of this drives real Gemini/Claude API spend.

**Scope note (verified):** This does **not** unlock the StoreKit-gated paid features (unlimited patterns, ad-free, widgets, voice counter) — `isPremium` is derived only from `Transaction.currentEntitlements` ([SubscriptionStore.swift:157](PatternVault/PatternVault/Services/SubscriptionStore.swift:157), `:372`) and is never read back from the DB. The exposure is **metered-cost abuse**, not free premium.

**Fix:**
- Prevent client writes to `is_premium` and the usage columns: revoke direct `UPDATE` on those columns (route everything through `SECURITY DEFINER` RPCs), or add a trigger/`with_check` that rejects client changes to them.
- Make the usage RPCs derive the user from `auth.uid()` internally (as `increment_youtube_imports_for_current_user()` already does) and **revoke `EXECUTE` from `anon`**.
- For real integrity, validate `is_premium` server-side against StoreKit (App Store Server API / signed `JWSTransaction`) instead of trusting the client.

---

## P1 — Rejection risk & correctness

### P1-1 · SSRF in `enrich-pattern` via user-controlled `source_url`
**Surface:** Edge Function · **Location:** [enrich-pattern/index.ts:38](PatternVault/supabase/functions/enrich-pattern/index.ts:38) (`fetchWebPageText`), called at `:411`

`fetchWebPageText` does `redirect: "follow"` and blocks only `file://`. `source_url` is fully user-controlled, and the fetched body flows into Gemini → `cleaned_content`, which the user can read back. A user can point `source_url` at internal/link-local/metadata addresses and exfiltrate the response. **Fix:** resolve the host and reject private/loopback/link-local/metadata ranges before fetching; restrict to `http(s)`; cap and re-validate redirects.

### P1-2 · In-app WebView loads untrusted URLs in a bare `WKWebView`
**Surface:** iOS · **Location:** [InAppWebView.swift:12](PatternVault/PatternVault/Core/Shared/InAppWebView.swift:12)

`WKWebView()` with default config (JS enabled, shared process) renders external pattern/Ravelry URLs. **Fix:** prefer `SFSafariViewController` for external links (process isolation, visible browser chrome, no app-context confusion), or at minimum a hardened `WKWebViewConfiguration`.

### P1-3 · Website `/api/parse` has no auth and no rate limiting (cost abuse)
**Surface:** Website · **Location:** [parse.ts:184](website/api/parse.ts:184)

The public Vercel function accepts 15 MB PDFs / 60k chars and calls Gemini with **no authentication, no rate limiting, and no origin restriction** — anyone can `curl` it in a loop and bill the `GEMINI_API_KEY`. (Secret handling itself is fine: server-side env var, `Cache-Control: no-store`, content not persisted — the "parsed in memory, never stored" claim holds.) **Fix:** add a rate limit (per-IP, e.g. Vercel KV/Upstash), a simple origin/turnstile check, and a daily spend cap/alert.

### P1-4 · `SECURITY DEFINER` functions over-exposed to `anon`
**Surface:** Backend · **Location:** advisors `0028`/`0029`

Beyond the usage RPCs (P0-2), these are anon-executable: `get_or_create_usage(p_user_id)` (anyone can **read/create any user's entitlement row**, including `is_premium` — cross-user info leak), `count_notes_with_photo(p_user_id)` (leaks any user's photo-note count), `record_lifetime_purchase()` / `expire_lifetime_offer_if_past_end_date()` (anyone can mutate `app_config` lifetime counters). **Fix:** revoke `EXECUTE` from `anon` on all of these; switch the user-scoped ones to `auth.uid()` internally; the lifetime functions should be service-role only.

---

## P2 — Reliability, concurrency & architecture
*(Identified in code review; fix post-launch. Locations are representative, not exhaustive.)*

- **P2-1 · God-object view.** [PatternDetailView.swift](PatternVault/PatternVault/Core/Pattern/PatternDetailView.swift) is ~3,320 LOC handling detail, edit, notes, tags, images, PDF, chart editor, repeats, progress and celebrations with scattered `@State`. High regression risk; extract step-editor / grid-editor / progress into child views. (Also large: `PatternListView`, `SettingsView`, `OnboardingView`, `MainTabView`.)
- **P2-2 · Chart-extraction state.** `PatternStore.triggerPendingChartExtractions` + `ChartGridDetector` + `ChartHighlightStore` track `chartExtractionInFlight` vs `chartExtractionFailed` as separate sets; re-import mints a new UUID and orphans prior highlights (re-extracts each launch — see CLAUDE.md). Consolidate into one state machine.
- **P2-3 · Concurrency safety.** Force-unwraps in async paths (`[0]!`, `.first!`) and ~150 `try?` swallows; most are benign (`Task.sleep`) but file-I/O and JSON-decode failures lose data silently (e.g. `ChartHighlightStore.load`, `PatternListCacheService`). Triage and log/propagate the critical ones; verify non-`@MainActor` services are genuinely stateless.
- **P2-4 · Cache hygiene.** Pattern-list / PDF / image caches have no TTL or eviction → unbounded disk growth and stale-forever-when-offline. Add TTL + LRU.
- **P2-5 · Thin tests.** ~873 LOC tests vs ~35k LOC app; repositories, stores, and the enrichment/chart pipelines are untested. Start with `EntitlementRepository` limits, the enrichment state machine, and repository CRUD.
- **P2-6 · RLS-enabled-no-policy tables.** Advisor: `mascot_poll_votes` and `waitlist_signups` have RLS on with **no policies** → all client access blocked. Fine **if** only edge functions (service role) write them — confirm the website/app never writes via anon (it would silently fail). Also review **prompt-injection** blast radius: web/PDF content reaches Gemini in 4 places; schema-constrained, so impact is poisoned field values, not code exec — add output sanity checks on `title`/`summary`.

---

## P3 — Accessibility & hardening

- **P3-1 · No Dynamic Type.** `Theme.Typography` uses fixed `.rounded` sizes; zero `dynamicTypeSize` usage. Largest a11y gap — adopt scalable fonts.
- **P3-2 · VoiceOver coverage.** ~102 labels exist but interactive charts (`InteractiveChartGridView`), the voice counter, and `PatternCardView` are thin. Audit navigation + unlabeled controls.
- **P3-3 · Color-only information.** Status badges, craft colors, yarn colors — add text/shape fallbacks.
- **P3-4 · Leaked-password protection disabled.** Advisor `auth_leaked_password_protection` — one-click enable (HaveIBeenPwned check) in Auth settings.
- **P3-5 · DB hardening.** `set_updated_at` has a mutable `search_path` (advisor `0011`); set `search_path = ''`. Duplicate migration numbers `014_add_parsed_rows` / `014_add_project_note_duration_minutes` risk a skip on fresh setups — renumber. `UIUserInterfaceStyle = Light` locks out dark mode (note as deliberate vs. gap).

---

## P4 — Website & legal

- **P4-1 · Privacy policy gaps.** [privacy.md](website/src/pages/privacy.md): no GDPR/CCPA data-subject-rights section; no formal sub-processor list (Supabase isn't named; AdMob/Firebase/Gemini are); says delete data via email but the **app has self-serve account deletion** — mention it; **Ravelry** OAuth data-sharing is undisclosed; the website parser tool isn't mentioned.
- **P4-2 · Terms gaps.** [terms.md](website/src/pages/terms.md): no explicit account-termination/data-deletion procedure. AI and liability disclaimers are present and adequate.
- **P4-3 · Contact mismatch.** Policy contact is `r.minardi.angela@gmail.com`, while Info.plist `SupportURL` is `corvidcraft.com/contact` and the dev account is `angem456@gmail.com`. Pick one support identity.
- **P4-4 · Site config.** `astro.config.mjs` sets no `site` (no canonical/sitemap). Minor SEO. Also: CI `TEST_HOST` was pointed at `CorvidCraft.app`, which **refuses connection** — the live site is `corvidcraft.com`; verify CI isn't testing a dead host.

---

## Launch-blocker checklist

- [ ] **P0-1** Make `note-photos` + `pattern-pdfs` private; signed URLs. Remove broad `SELECT` on `pattern-images`.
- [ ] **P0-2** Lock `is_premium`/usage columns from client writes; `auth.uid()`-scope the usage RPCs; revoke `anon` `EXECUTE`.
- [ ] **P1-1** Block private-range/redirect SSRF in `enrich-pattern`.
- [ ] **P1-3** Rate-limit + spend-cap the website `/api/parse`.
- [ ] **P1-4** Revoke `anon` `EXECUTE` on the remaining `SECURITY DEFINER` functions.
- [ ] **P4-1** Add GDPR/CCPA rights + sub-processor list + Ravelry disclosure to the privacy policy.

---

## Appendix — verified strengths

- **Secrets are clean:** `Config.xcconfig` / `.env` are untracked and absent from git history; no key prefixes (`AIzaSy`, `sk-ant-api03`) in history; `.gitignore` rules are correct.
- **Core RLS is correct:** every user table (`patterns`, `project_notes`, `tags`, `yarn_stash`, `needle_hook_inventory`, `pattern_*`, `collections`, …) scopes to `auth.uid() = user_id`.
- **Auth done well:** Keychain token storage (`AfterFirstUnlockThisDeviceOnly`, App-Group shared), Ravelry OAuth with PKCE + state CSRF check, Apple Sign-In SHA-256 nonce, email-enumeration-safe password reset.
- **Account deletion** is robust (persistent queue, exponential backoff, 14-day TTL, edge function with service role) — satisfies Apple's requirement.
- **Paid features are not DB-bypassable:** `isPremium` comes from StoreKit, not the DB.
- **Privacy manifest present**, ATT correctly gated (`requestTrackingAuthorizationIfNeeded`), `PhotosPicker` avoids broad photo-library permission, HTTPS-only (no ATS exceptions), `ITSAppUsesNonExemptEncryption = false`, legal pages live at `corvidcraft.com`.

---

## Codex pass (2026-06-27)

### Validation performed

- Built main app scheme `PatternVault` for iOS Simulator (`CorvidCraft` target): **passed**.
- Built share-extension scheme `SaveToPatternVault` (`SaveToCorvidCraft` embedded in `CorvidCraft.app`): **passed**.
- Ran `PatternVault` scheme tests (`CorvidCraftTests`): **95 tests passed, 0 failures**.
- Fixed stale test module imports from `@testable import PatternVault` to `@testable import CorvidCraft` across `PatternVault/PatternVaultTests/*.swift`; representative line: `PatternVault/PatternVaultTests/PatternStepParserTests.swift:7`.

### P0 — Security & data-leak

- **P0-1 · Private storage bucket upgrade remains intentionally deferred.** I did **not** flip `note-photos` / `pattern-pdfs` to private in code because it requires a coordinated production migration, signed URL reads in the main app, signed URL reads in `SaveToPatternVault`'s raw `URLSession` client, and a backout plan. Recommended sequence: (1) add SDK/raw-REST signed URL helpers and migrate all image/PDF views to fetch signed URLs; (2) ship an app build that supports signed URLs while buckets remain public; (3) run a migration that sets `storage.buckets.public = false` for `note-photos` and `pattern-pdfs` and keeps owner-scoped storage policies; (4) smoke-test note photo loads, PDF viewer loads, share-extension uploads, offline cached content, and account deletion cleanup; (5) monitor storage 403/404s. Apple risk: Guideline 5.1.1 privacy if user photos/PDFs remain public-by-URL.
- **P0-2 · Entitlement column lock remains deploy-coupled.** No production DB changes were made. Keep the existing plan: ship the app code using `set_premium`, then manually apply `PatternVault/supabase_migrations/034_lock_entitlement_columns.sql` with that build. Applying it before the app build risks breaking build 9 premium writes.

### P1 — Rejection risk & correctness

- **P1 · StoreKit disclosure improved (Guideline 3.1.2).** Added visible auto-renewal disclosure plus Terms/Privacy links to the paywall at `PatternVault/PatternVault/Core/Settings/PaywallView.swift:202`. Existing Restore Purchases remains at `PatternVault/PatternVault/Core/Settings/PaywallView.swift:187`; intro-offer copy still gates yearly display on eligibility.
- **P1 · Release ad-unit configuration hardened (Guideline 2.1 / ATT 5.1.2).** Replaced hardcoded native/banner test IDs with Info.plist-backed accessors and DEBUG-only test fallback at `PatternVault/PatternVault/Services/AdService.swift:35`; added `GADNativeAdUnitID` to `PatternVault/PatternVault/Info.plist:100`; native ad loading now no-ops if no release ad unit is configured at `PatternVault/PatternVault/Core/Shared/NativeAdCardView.swift:142`. Before upload, set real `GAD_APPLICATION_ID`, `GAD_BANNER_AD_UNIT_ID`, and `GAD_NATIVE_AD_UNIT_ID` in the untracked release xcconfig.
- **P1 · ATT/ads review.** ATT is requested via `AdService.requestTrackingAuthorizationIfNeeded()` and ad eligibility is still controlled by `AdService.canShowAds`; I found no non-ad feature gated by ATT. Confirm on-device that no Google ad request is sent before UMP/ATT flow completes in the release build.

### P2 — Reliability, concurrency & architecture

- **P2-3 · Silent chart persistence failures reduced.** Replaced silent chart-highlight JSON read/decode/write swallows with `NSLog` diagnostics and atomic JSON writes at `PatternVault/PatternVault/Services/ChartHighlightStore.swift:241` and `PatternVault/PatternVault/Services/ChartHighlightStore.swift:298`.
- **P2-4 · Cache TTL/eviction added.** Pattern list cache now stores a dated envelope, expires after 24h, migrates legacy cache files, and logs decode/write errors at `PatternVault/PatternVault/Services/PatternListCacheService.swift:13`. Generic offline JSON cache now has the same 24h TTL and logging at `PatternVault/PatternVault/Services/OfflineCacheService.swift:13`. PDF cache now has a 30-day TTL layered on its existing 500 MB LRU cap at `PatternVault/PatternVault/Services/PDFCacheService.swift:14`. Image cache now has a 30-day TTL layered on its existing 200 MB LRU cap at `PatternVault/PatternVault/Services/ImageCacheService.swift:28`.
- **P2-1/P2-2 · Large PatternDetailView and chart extraction state machine remain deferred.** I did not decompose the ~3,300-line view or redesign `PatternStore` / `ChartGridDetector` / `ChartHighlightStore` state in this pass because those are high-regression, multi-day refactors. Recommended next PR: extract read-only sections first (PDF card, notes card, chart card, progress header), then introduce a single `ChartExtractionState` model (`idle`, `queued`, `extracting`, `failed(error/date)`, `complete(highlightIds)`) and make re-import cleanup delete superseded highlights by source URL/content hash.
- **P2-5 · Test coverage partially unblocked.** The existing test target now builds/runs under the renamed `CorvidCraft` module. Still missing: repository tests with mocked Supabase client seams, entitlement-limit tests, and enrichment/chart pipeline state-machine tests.

### P3 — Accessibility & privacy manifests

- **P3 · Privacy manifest embedded in extension/widget.** The app already declared file timestamp (`C617.1`) and UserDefaults (`CA92.1`) at `PatternVault/PatternVault/PrivacyInfo.xcprivacy:100`; this pass also adds that manifest to the share extension and widget resource phases at `PatternVault/PatternVault.xcodeproj/project.pbxproj:992` and `PatternVault/PatternVault.xcodeproj/project.pbxproj:1027`, because both embedded targets use `UserDefaults`.
- **P3 · Required-reason API review.** Current first-party usage found UserDefaults plus file timestamp/file metadata APIs; I did not find system boot time, active keyboard, or volume-capacity/disk-space API usage in first-party app/extension/widget code. Third-party SDK privacy manifests are present in the built app for GoogleMobileAds, UserMessagingPlatform, Firebase Core/Crashlytics/Installations, GoogleUtilities, Lottie, and related bundles.
- **P3-1/P3-2/P3-3 · Accessibility remains a pre-submit manual QA item.** Dynamic Type adoption in `Theme.Typography`, VoiceOver for interactive charts/voice counter/PatternCardView, and color-only status alternatives were not completed in this pass. Recommended next PR: switch `Theme.Typography` to `Font.custom(..., relativeTo:)` / semantic styles, then run a real-device VoiceOver pass over Patterns, chart mode, voice row counter, paywall, account deletion, and share extension.

### P4 — Website, legal & metadata polish

- **P4-3 · Public support contact standardized.** Website privacy and terms now use `support@corvidcraft.com`, matching the public `/contact` page and `Info.plist` SupportURL. See `website/src/pages/privacy.md:68`, `website/src/pages/privacy.md:72`, and `website/src/pages/terms.md:72`.
- **P4-4 · CI TEST_HOST checked.** The Xcode test host points to the local built app binary (`$(BUILT_PRODUCTS_DIR)/CorvidCraft.app/CorvidCraft`) at `PatternVault/PatternVault.xcodeproj/project.pbxproj:1351`; this is not the dead `corvidcraft.app` website host. I did not find a GitHub workflow referencing `corvidcraft.app`.
- **P4 · Version/config review.** Current project settings are `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 9`, and `IPHONEOS_DEPLOYMENT_TARGET = 17.0` in `PatternVault/PatternVault.xcodeproj/project.pbxproj`. `ITSAppUsesNonExemptEncryption = false` is present in `PatternVault/PatternVault/Info.plist`. Confirm build number 9 has not already been uploaded before archiving.

### App Store submission checklist

1. Ship the app build that includes `EntitlementRepository.setPremium` → `set_premium`, then manually apply `034_lock_entitlement_columns.sql` to production.
2. Deploy/verify `enrich-pattern` with `verify_jwt=true` and the SSRF guard, and redeploy the website parser/legal updates if not already live.
3. Decide before upload whether to keep public-by-URL storage for launch or execute the private-bucket signed-URL rollout plan above.
4. Set real AdMob app/banner/native IDs in the untracked release `Config.xcconfig`; confirm no test ad IDs appear in a Release archive.
5. Real-device QA: ATT/UMP consent, no tracking before consent, paywall purchase/restore/cancel paths, account deletion, camera/mic/speech permission prompts, share-extension import, Ravelry import/search, PDF/image memory behavior, offline cache fallback, iPad orientations, VoiceOver, and Dynamic Type.
6. Archive a Release build and inspect the generated privacy report / App Store Connect privacy questionnaire against actual SDK usage before upload.

---

## App Store approval pass (2026-07-25)

**Trigger:** App Review rejection of 1.0 (8) on 2026-05-21, both under **Guideline 2.1(b) App Completeness**: (1) IAP products referenced ("Premium") but never submitted for review; (2) the subscription page loaded to an error on iPhone 17 Pro Max / iPad Air 11" — Apple's screenshots show the paywall surfacing developer debug text ("Verify StoreKit configuration is attached to this scheme Run action…").
**Method:** static review of the current working tree, live Supabase advisor/migration/edge-function dumps, live legal-page and parser-endpoint fetches, full test run. App Store Connect could not be browsed (Chrome extension disconnected) — see the manual ASC checklist below.
**Validation:** working tree builds clean; **104 tests, 0 failures** (suite grew from 95 with ChartGridSolverTests).

### Why the rejection happened, and what actually fixes it

The paywall error is two problems layered:

1. **App-side (fixed, verified):** `SubscriptionStore.loadProducts` composed a debug message containing scheme/StoreKit-config instructions and PaywallView displayed it. As of the current tree, the debug text is `#if DEBUG`-only ([SubscriptionStore.swift:244](PatternVault/PatternVault/Services/SubscriptionStore.swift:244), [PaywallView.swift:126](PatternVault/PatternVault/Core/Settings/PaywallView.swift:126)); Release users/reviewers get a friendly retry message, a Try again button, Restore Purchases, and the 3.1.2 auto-renew disclosure with Terms/Privacy links. Product IDs match the rejection screenshot exactly (`com.corvidcraft.premium.monthly` / `.yearly`); a 5-attempt backoff covers transient StoreKit launch races.
2. **ASC-side (the actual root cause — code cannot fix it):** in Apple's review environment, `Product.products(for:)` returns products from App Store Connect. It returns **empty** when the subscriptions were never attached to the submission, their metadata is incomplete (each needs a localized name/description **and an App Review screenshot**), or the **Paid Applications Agreement** isn't active with banking/tax complete. Until that's done in ASC, build 10 will show the (now friendly) error to the reviewer and be rejected again for the same reason.

### Resubmission playbook (in order)

1. **Commit the working tree.** Nearly every fix in this file's earlier "pending next build" list — `setPremium` → `set_premium` RPC, SafariView, ad-unit guards, paywall sanitization, cache TTLs, SSRF-guarded edge source, the new stash camera/AI features — is **uncommitted**. The committed build-9 tag does not contain them. Commit, then bump `CURRENT_PROJECT_VERSION` 9 → 10 in all targets (9 may already exist in TestFlight; all six build-settings blocks currently say 9).
2. **Decide the ATT question (new P1 below)** and wire or un-declare it before archiving.
3. **In App Store Connect:**
   - Business → Agreements: **Paid Applications Agreement = Active**, banking + tax forms complete. (Most common cause of empty product fetches in review/sandbox.)
   - Monetization → Subscriptions: for both products, complete localized display name + description and upload the required **review screenshot** (paywall screenshot ≥ 640×920). Status must read **Ready to Submit**.
   - App version page → In-App Purchases and Subscriptions section: **attach both subscriptions to the 1.0 submission** (first-time subscription review must ride with a binary).
   - App Review Information: demo credentials (or an explicit note that Sign in with Apple creates an account — the reviewer used SIWA last time), plus a note that IAPs are now attached.
   - App Privacy labels: make them agree with the ATT decision (see P1-ATT).
4. **Archive Release with the real xcconfig values** (`GAD_APPLICATION_ID`, `GAD_BANNER_AD_UNIT_ID`, `GAD_NATIVE_AD_UNIT_ID`, Supabase, Gemini). Runtime guards mean missing ad IDs won't crash ([PatternVaultApp.swift:86](PatternVault/PatternVault/PatternVaultApp.swift:86)), but ads silently vanish.
5. **Sandbox-test on a physical device before submitting:** paywall loads both products, purchase monthly, restore, cancel; verify the $19.99-intro copy only shows when eligible.
6. **Immediately after uploading the build that contains the RPC change, apply `034_lock_entitlement_columns.sql`** (still unapplied on prod — verified via live migration list; 033/035/036/037/038 are applied).
7. Resubmit and reply in the rejection thread describing both fixes.

### New findings (this pass)

- **P1-ATT · ATT prompt is dead code while the privacy manifest declares tracking.** `AdService.requestTrackingAuthorizationIfNeeded()` ([AdService.swift:93](PatternVault/PatternVault/Services/AdService.swift:93)) has **no call sites**. But [PrivacyInfo.xcprivacy](PatternVault/PatternVault/PrivacyInfo.xcprivacy) sets `NSPrivacyTracking=true` **and lists `NSPrivacyTrackingDomains`** (doubleclick, googlesyndication, google-analytics), and the live privacy policy promises ads run "only with your ATT consent". Consequences: (a) iOS **blocks requests to declared tracking domains when ATT is unauthorized** — since the prompt never appears, ad serving can silently fail for every user; (b) if the ASC privacy label declares "Data Used to Track You" and the reviewer never sees an ATT prompt, that's a 5.1.2 label/behavior mismatch. **Fix (pick one):** call `await AdService.shared.requestTrackingAuthorizationIfNeeded()` immediately before `AdService.shared.initialize()` in [MainTabView.swift:98](PatternVault/PatternVault/Core/Shared/MainTabView.swift:98) (recommended — matches manifest, policy, and label), **or** commit to the no-tracking route: remove `NSPrivacyTracking`/domains, strip the tracking claims from the ASC label, and update the policy sentence.
- **~~P1-PARSE~~ · RETRACTED (same-day correction).** [website/api/parse.ts](website/api/parse.ts) **does** contain the origin allowlist and best-effort per-IP rate limit (lines 30–81) — the "missing guard" reading came from greps run from a stale shell working directory; a direct file read disproved it. Live prod (verified: 403 to non-site callers) and the repo copy agree. The real, smaller action: `website/api/` was untracked — commit it so deploys are reproducible from git.
- **P2-LEGAL · New stash features are undisclosed in the privacy policy.** The yarn-label scanner sends **user photos to Google Gemini** ([YarnLabelAnalyzer.swift:81](PatternVault/PatternVault/Services/YarnLabelAnalyzer.swift:81)) and barcode scans query **UPCitemdb** ([BarcodeLookupService.swift:32](PatternVault/PatternVault/Services/BarcodeLookupService.swift:32)). The live policy's Gemini row covers only "pattern content you submit", and UPCitemdb is absent. Add both (one row edit + one new row). Also consider declaring **Photos or Videos** in PrivacyInfo.xcprivacy and the ASC label — note photos and label photos are transmitted off-device; today only "Other User Content" is declared.
- **P3-UPC · UPCitemdb trial endpoint in production.** `prod/trial/lookup` is the unauthenticated dev tier (~100 lookups/day per IP, no SLA, ToS meant for evaluation). Degrades gracefully (nil → manual entry), so ship-ok, but plan a keyed tier or server-side proxy.
- **P3-GMA-INIT · SDK started before consent.** `PatternVaultApp.init` starts Google Mobile Ads at launch when an app ID exists, before the UMP consent flow that `AdService.initialize()` runs later. Google's UMP guidance is consent-then-start; EEA users could see the SDK warm up pre-consent (no ad requests, so low risk). Tidy-up: drop the early start and let `AdService.initialize()` own SDK startup.

### Verified green (evidence, this pass)

- **Build/tests:** clean build; 104/104 tests pass on iPhone 16 sim.
- **Backend:** `enrich-pattern` **v7 ACTIVE, `verify_jwt=true`**, SSRF guard live and byte-matched to the repo diff (manual redirect validation, private/metadata ranges blocked); `delete-account` ACTIVE (Apple 5.1.1(v) satisfied — Settings shows Delete Account, per Apple's own rejection screenshots); `extract-pattern-from-video` JWT-gated. Live advisor scan: **no anon-executable SECURITY DEFINER functions remain**; the surviving WARNs (`get_or_create_usage`, `increment_*`, `set_premium`, `count_notes_with_photo` callable by `authenticated`) are by design — they're the app's API and are `auth.uid()`-scoped internally. `mascot_poll_votes` / `waitlist_signups` RLS-no-policy INFOs are intentional (service-role writes only).
- **Paywall/StoreKit:** sanitized release error UI; disclosure + Terms/Privacy links + Restore on every paywall state; intro-offer copy gated by real `isEligibleForIntroOffer`; `isPremium` still derived exclusively from StoreKit entitlements (not the DB); no lifetime-SKU remnants in app code.
- **Ads:** ad-unit IDs nil-guard in Release ([BannerAdView](PatternVault/PatternVault/Core/Shared/BannerAdView.swift), [NativeAdCardView](PatternVault/PatternVault/Core/Shared/NativeAdCardView.swift)); AdMob app-ID validity gate prevents launch crash; premium users excluded via `canShowAds`.
- **Legal/site:** the working-tree privacy/terms updates are **already deployed** — live pages show the sub-processor table (Supabase/Gemini/AdMob/Firebase/Ravelry/Vercel), GDPR/CCPA rights, in-app deletion path, and `support@corvidcraft.com` everywhere.
- **New code quality:** LabelCameraView uses the system picker (camera string present and specific); YarnLabelAnalyzer downscales images, uses `thinkingBudget: 0`, sanitizes duplicate-key JSON before decoding (matches CLAUDE.md gotchas); new files are correctly registered in the pbxproj with unique IDs.

### Still open (carried forward, unchanged)

- **P0-1 (deferred decision):** `note-photos` / `pattern-pdfs` remain public-by-URL (enumeration was closed in 033). The signed-URL migration plan from the Codex pass still stands.
- **P3-4:** Leaked-password protection still disabled (advisor re-confirmed today) — one toggle in Supabase Auth settings.
- **Accessibility:** Dynamic Type adoption is still zero (`dynamicTypeSize`/`relativeTo:` → 0 hits; 80 `accessibilityLabel`s exist); color-only status cues; `UIUserInterfaceStyle = Light` locks out dark mode (confirm deliberate).
- **Architecture/tests:** PatternDetailView god-object, chart-extraction state machine, repository/store test seams.

### ASC checklist (do manually — browser access was unavailable this session)

- [ ] Paid Applications Agreement **Active**; banking + tax **Complete**
- [ ] Both subscriptions: localization + **review screenshot** → **Ready to Submit**
- [ ] Subscriptions **attached to the 1.0 version submission**
- [ ] Confirm whether build 9 was already uploaded (if yes, next upload must be 10)
- [ ] App Privacy label matches the ATT decision (tracking declared ⟺ prompt shown)
- [ ] App Review notes: SIWA/demo account + "IAPs now submitted" reply in Resolution Center
- [ ] iPhone **and iPad** screenshot sets current (review ran on iPad Air 11")

### Remediation log (2026-07-25, same day)

**Applied and verified:**
- ATT prompt wired ahead of every ads-init path (MainTabView `.task` for the first session + the scenePhase re-foreground path); GMA SDK start removed from `PatternVaultApp.init` and consent-gated inside `AdService.initialize()` behind `hasValidAdMobAppId`.
- `PrivacyInfo.xcprivacy`: added `NSPrivacyCollectedDataTypePhotosorVideos` (linked, non-tracking, app functionality).
- Privacy policy: Gemini row now covers yarn-label photos; UPCitemdb row + note added; last-updated date stamped. **Deployed to production** (corvidcraft.com/privacy verified serving both).
- `website/api/parse.ts`: raw NUL byte inside the NUL-stripping regex replaced with `\u0000` — file was being classified as binary ("data"); now clean UTF-8. `website/api/` committed to git.
- Build bumped 9 → 10 across all 4 targets; **104/104 tests pass post-change**; Release archive succeeds with real AdMob app ID and all config substituted (verified in the archived Info.plist).
- Migration **034 applied to production** (`lock_entitlement_columns`, version 20260725182209) — P0-2 closed end-to-end.
- All working-tree changes committed and pushed: `4258249` (iOS), `4022854` (backend), `315ca49` (website+docs).
- Archive copied to `~/Library/Developer/Xcode/Archives/2026-07-25/` so it appears in Xcode Organizer.

**Root cause confirmed by the upload attempt:** `xcodebuild -exportArchive` (destination: upload) failed with **"You do not have required contracts to perform an operation."** — an App Store Connect **agreements block**. This is the same underlying condition that makes `Product.products(for:)` return empty in Apple's review environment. Until the Account Holder accepts the pending agreement(s) (Paid Applications Agreement with banking + tax, and any pending Program License Agreement update), the paywall cannot work in review and the binary cannot be uploaded. Only the Account Holder can do this: **App Store Connect → Business / Agreements, Tax, and Banking**.

**Remaining (user, in order):** accept agreements → complete banking/tax → upload build 10 (Organizer "Distribute App", or rerun the exportArchive command) → complete both subscriptions' metadata + review screenshots → attach them to the 1.0 version → sandbox-test the paywall on device → resubmit with a Resolution Center reply. Optional before archiving a future build: add `GAD_NATIVE_AD_UNIT_ID` and `RAVELRY_ACCESS_KEY`/`RAVELRY_PERSONAL_KEY` to Config.xcconfig (native ads and Ravelry "Find patterns" are silently disabled in build 10 without them); enable Supabase leaked-password protection (dashboard toggle).
