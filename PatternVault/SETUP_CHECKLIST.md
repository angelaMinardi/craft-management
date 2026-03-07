# Pattern Vault — Setup checklist

Use this to see what’s already done in the project and what you still need to do in the dashboard, Xcode, and Google/Apple.

---

## Done in the codebase (no action needed)


| Item                                     | Status                                                       |
| ---------------------------------------- | ------------------------------------------------------------ |
| **Project URL** in Xcode Build Settings  | Must match your Supabase project URL                         |
| **Anon key** in Xcode Build Settings     | Set (JWT) for Debug and Release                              |
| **OAuth URL scheme** for Google callback | `com.patternvault.app` in Info.plist                         |
| **App handles OAuth redirect**           | `onOpenURL` in app calls `auth.session(from:)`               |
| **Login UI**                             | Email, Sign in with Apple button, Sign in with Google button |
| **Bundle ID**                            | `com.patternvault.app` in project                            |


---

## Supabase Dashboard — your checklist

Do these in [Supabase](https://supabase.com/dashboard) → your project **pattern-vault**.


| Step                                                         | Where                                                                                                   | Done? |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- | ----- |
| **1. Email auth**                                            | Authentication → Providers → **Email** → Enable                                                         | ☐     |
| **2. (Optional)** Turn off “Confirm email” for quick testing | Email provider → Confirm email OFF                                                                      | ☐     |
| **3. Apple**                                                 | Authentication → Providers → **Apple** → Enable                                                         | ☐     |
| **4. Apple Client ID**                                       | Same Apple section → **Client IDs** → add `com.patternvault.app`                                        | ☐     |
| **5. Google**                                                | Authentication → Providers → **Google** → Enable                                                        | ☐     |
| **6. Google Client ID & Secret**                             | Same Google section → paste Web client ID and Secret from Google Cloud                                  | ☐     |
| **7. Redirect URL for Google**                               | Authentication → **URL Configuration** → **Redirect URLs** → add `com.patternvault.app://auth/callback` | ☐     |


---

## Xcode — your checklist


| Step                                 | Where                                                                                                 | Done? |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- | ----- |
| **1. Sign in with Apple capability** | PatternVault target → Signing & Capabilities → **+ Capability** → “Sign in with Apple”                | ☐     |
| **2. Bundle ID**                     | Target → General → Bundle Identifier is `com.patternvault.app` (must match Supabase Apple Client IDs) | ☐     |


---

## Google Cloud — only for Google sign-in


| Step                           | Where                                                                                                       | Done? |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- | ----- |
| **1. OAuth consent screen**    | APIs & Services → OAuth consent screen (e.g. External, app name, support email)                             | ☐     |
| **2. Web OAuth client**        | Credentials → Create credentials → OAuth client ID → **Web application**                                    | ☐     |
| **3. Redirect URI**            | In that client → Authorized redirect URIs → add `https://fbzbnztvanuiijzymckn.supabase.co/auth/v1/callback` | ☐     |
| **4. Copy Client ID & Secret** | Paste them into Supabase → Providers → Google                                                               | ☐     |


---

## Apple Developer — only for Sign in with Apple


| Step                      | Where                                                                                                                 | Done? |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------- | ----- |
| **1. App ID**             | Identifiers → ensure an App ID exists for `com.patternvault.app` (Xcode often creates it when you add the capability) | ☐     |
| **2. Sign in with Apple** | That App ID → Capabilities → Sign in with Apple enabled                                                               | ☐     |


---

## Database & Storage — your checklist

Run these migrations in order in Supabase Dashboard → **SQL Editor** → New query → paste → Run.

| Step                                         | File                                              | Done? |
| -------------------------------------------- | ------------------------------------------------- | ----- |
| **1. Patterns table**                        | `supabase_migrations/001_create_patterns.sql`     | ☐     |
| **2. Project notes table**                   | `supabase_migrations/002_create_project_notes.sql`| ☐     |
| **3. Tags + pattern_tags tables + seed data**| `supabase_migrations/003_create_tags.sql`         | ☐     |
| **4. Note photos storage bucket**            | See SQL below                                     | ☐     |

**Note photos storage SQL** (run in SQL Editor after migration 002):
```sql
INSERT INTO storage.buckets (id, name, public) VALUES ('note-photos', 'note-photos', true);
CREATE POLICY "Users can upload note photos" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'note-photos');
CREATE POLICY "Public read access for note photos" ON storage.objects FOR SELECT TO public USING (bucket_id = 'note-photos');
CREATE POLICY "Users can delete own note photos" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'note-photos');
```

---

## Quick test

After the checklists above:

1. **Email:** Sign up with email/password on the login screen → you should land on the main tabs.
2. **Apple:** Tap “Sign in with Apple” → complete flow → should land on main tabs (needs capability + Supabase Apple enabled + Client ID).
3. **Google:** Tap “Sign in with Google” → browser opens → sign in → redirects back to app (needs Google Cloud client, Supabase Google + redirect URL).

---

## Summary: still to do

- **Supabase:** Enable Email (and optionally Apple + Google), add Apple Client ID `com.patternvault.app`, add Google Client ID/Secret, add redirect URL `com.patternvault.app://auth/callback`.
- **Xcode:** Add “Sign in with Apple” capability.
- **Google Cloud:** Create Web OAuth client, set redirect URI to Supabase callback, copy ID/Secret to Supabase.
- **Apple Developer:** Ensure App ID has Sign in with Apple (often done when adding the capability in Xcode).

