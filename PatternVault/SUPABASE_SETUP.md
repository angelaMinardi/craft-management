# Pattern Vault — Supabase & Auth Setup

## Your project URL

Supabase does not always show "Project URL" in the UI. You can build it from your **Project ID**:

- **Project ID:** `fbzbnztvanuiijzymckn`
- **Project URL:** `https://fbzbnztvanuiijzymckn.supabase.co`

This URL is already set in the Xcode project (Build Settings → SUPABASE_URL). The **anon key** (public) is also set. You can override either with a `Config/Config.xcconfig` file if you prefer.

---

## API keys (reference)

| Key | Use in app | Where in Supabase |
|-----|------------|-------------------|
| **Project URL** | `SUPABASE_URL` | `https://<PROJECT_ID>.supabase.co` |
| **Public anon key** | `SUPABASE_ANON_KEY` | Project Settings → API → anon public |
| **Publishable key** (`sb_publishable_...`) | Optional (some docs use this) | Project Settings → API |
| **Secret key** | Never in the app | Server/Edge only |

For Pattern Vault iOS you only need **Project URL** and **anon key** (the long JWT starting with `eyJ...`).

---

## Enable Email auth

1. Supabase Dashboard → **Authentication** → **Providers**.
2. Find **Email** → turn **Enable** on.
3. For quick testing, turn **Confirm email** off so users can sign in right after sign-up.

---

## Enable Sign in with Apple

### In Supabase

1. **Authentication** → **Providers** → **Apple**.
2. Turn **Enable** on.
3. Under **Client IDs**, add your app’s **Bundle ID** (e.g. `com.patternvault.app`).  
   This is the same as in Xcode: target → General → **Bundle Identifier**.
4. For **native iOS only** you do **not** need to fill Services ID, Secret Key, or Team ID. Those are for web/OAuth flows.

### In Xcode

1. Select the **PatternVault** target → **Signing & Capabilities**.
2. Click **+ Capability** → add **Sign in with Apple**.
3. Ensure the app’s **Bundle ID** matches what you added in Supabase (e.g. `com.patternvault.app`).

### In Apple Developer (if needed)

- You need an **App ID** with **Sign in with Apple** enabled (Xcode can do this when you add the capability).
- Add that **Bundle ID** to Supabase Apple provider **Client IDs** as above.

---

## Enable Google sign-in

### In Google Cloud

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create or select a project.
2. **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID**.
3. If asked, configure the **OAuth consent screen** (e.g. User type: External, App name, support email).
4. Create **OAuth client ID**:
   - **Application type:** **Web application** (for Supabase callback).
   - **Name:** e.g. "Pattern Vault Web".
   - **Authorized redirect URIs:** add:
     - `https://fbzbnztvanuiijzymckn.supabase.co/auth/v1/callback`
   - Copy the **Client ID** and **Client Secret**.
5. (Optional for native iOS) Create a second OAuth client:
   - **Application type:** **iOS**.
   - **Bundle ID:** `com.patternvault.app` (or your app’s bundle ID).
   - Use this Client ID in the app if you use native Google Sign-In SDK; for Supabase OAuth in a browser you often only need the Web client.

### In Supabase

1. **Authentication** → **Providers** → **Google**.
2. Turn **Enable** on.
3. Paste the **Client ID** (Web) and **Client Secret** from the Web application OAuth client.
4. Save.

### In the app and Supabase redirect list

1. **Supabase Dashboard:** **Authentication** → **URL Configuration** → **Redirect URLs**. Add exactly:
   - `com.patternvault.app://auth/callback`
2. The app already registers the URL scheme `com.patternvault.app` and handles this callback.

---

## Summary

| Provider | Supabase | Xcode / App | Third-party |
|----------|----------|-------------|-------------|
| **Email** | Providers → Email → Enable | (already in app) | — |
| **Apple** | Providers → Apple → Enable, add Bundle ID under Client IDs | Add “Sign in with Apple” capability | Apple Developer: App ID with capability |
| **Google** | Providers → Google → Enable, paste Web Client ID + Secret | Handle OAuth redirect URL | Google Cloud: Web OAuth client, redirect URI to Supabase callback |

Your **Project URL** for this project is: **`https://fbzbnztvanuiijzymckn.supabase.co`**.
