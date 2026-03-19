# Deploy the extract-pattern-from-video Edge Function

> **Status:** Legacy/optional path. Core in-app AI flow is Gemini-based. Keep this only if you still use the Supabase Edge Function YouTube transcript pipeline.

This function lets the Pattern Vault share extension turn a **YouTube URL** into pattern metadata (title, summary, tags, materials, etc.) by fetching the video’s captions and running Claude on the transcript.

> If this function is disabled, the app should continue to support non-function fallback behavior for shared URLs.

---

## What you can do without the API

While the Edge Function is unavailable (e.g. Anthropic credits exhausted) or not set up, you can still:

- **Create and edit patterns manually** in the app — add title, summary, tags, materials, video URL, PDF, yarn links, etc. All CRUD and filters work.
- **Share a YouTube link from the share extension** — when the Edge Function fails, the extension falls back to fetching the video **page** (not the transcript). You get the page title and description (and the video URL) pre-filled; you can edit and save. No transcript or AI extraction, but the link is saved.
- **Share PDFs** — save PDF patterns and attach them to patterns as usual.
- **Share other web links** — the extension fetches the page and, if an in-app Anthropic key is set, runs AI analysis; otherwise it uses the page title/description as a fallback.
- **Use project notes, tags, and yarn & supplies** — everything that doesn’t depend on the Edge Function works as normal.

---

## Prerequisites

1. **Supabase CLI**  
   Install if you haven’t:
   ```bash
   brew install supabase/tap/supabase
   ```
   Or: https://supabase.com/docs/guides/cli/getting-started

2. **Docker Desktop** (required for deploy)  
   Install from https://www.docker.com/products/docker-desktop/ and have it running.

3. **Anthropic API key**  
   From https://console.anthropic.com/ — used by the function to call Claude.

4. **Your Supabase project**  
   You need the **Project ID** (see setup guidance in `docs/SETUP.md`).

---

## Step 1: Log in to Supabase

```bash
supabase login
```

This opens a browser to authenticate the CLI with your Supabase account.

---

## Step 2: Link this folder to your project

From the **PatternVault** directory (the one that contains the `supabase` folder):

```bash
cd /Users/angelam/Desktop/CraftManagement/PatternVault
supabase link --project-ref fbzbnztvanuiijzymckn
```

When prompted for the database password, use the one you set when creating the Supabase project (or reset it in Dashboard → Project Settings → Database).

Replace `fbzbnztvanuiijzymckn` with your actual **Project ID** from Supabase Dashboard → Project Settings → General.

---

## Step 3: Set the Anthropic API key (secret)

The function needs `ANTHROPIC_API_KEY` to call Claude. Set it as a secret so it isn’t in code:

```bash
supabase secrets set ANTHROPIC_API_KEY=your_anthropic_api_key_here
```

Replace `your_anthropic_api_key_here` with your real key from console.anthropic.com.

To confirm it’s set (name only, value is hidden):

```bash
supabase secrets list
```

You should see `ANTHROPIC_API_KEY` in the list.

---

## Step 3b (optional): Use a transcript API for reliable captions

The function can fetch transcripts by scraping YouTube (built-in). If that fails for some videos (e.g. no captions or blocking), you can add **one** of these secrets so the function uses a third-party API first:

**Option A – ScrapeCreators** (1 credit per request)  
- Sign up at [ScrapeCreators](https://scrapecreators.com), get an API key.  
- Set the secret:
  ```bash
  supabase secrets set SCRAPECREATORS_API_KEY=your_scrapecreators_api_key
  ```

**Option B – YouTubeTranscript.dev** (1 credit per caption fetch)  
- Sign up at [youtubetranscript.dev](https://www.youtubetranscript.dev), get an API key from the dashboard.  
- Set the secret:
  ```bash
  supabase secrets set YOUTUBE_TRANSCRIPT_DEV_API_KEY=your_youtubetranscript_dev_api_key
  ```

The function tries ScrapeCreators first (if set), then YouTubeTranscript.dev (if set), then the built-in fetcher. You only need one; leave the other unset if you don’t use it.

---

## Step 4: Deploy the function

Still in the `PatternVault` directory:

```bash
supabase functions deploy extract-pattern-from-video
```

Wait for the CLI to finish. You should see a success message and the function URL, e.g.:

```text
Deployed Function extract-pattern-from-video on project fbzbnztvanuiijzymckn
Function URL: https://fbzbnztvanuiijzymckn.supabase.co/functions/v1/extract-pattern-from-video
```

No extra config is needed in the app: the share extension already calls this URL using your project’s base URL (`SUPABASE_URL`) + `/functions/v1/extract-pattern-from-video`.

---

## Step 5: Quick test (optional)

You can call the function with curl. You need a valid Supabase **access token** (JWT) for a signed-in user.

1. Sign in to Pattern Vault (or any client that uses your Supabase project).
2. Get the session’s access token (e.g. from Supabase Auth or your app’s auth state).
3. Run:

```bash
curl -i -X POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/extract-pattern-from-video' \
  -H 'Authorization: Bearer YOUR_ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.youtube.com/watch?v=VIDEO_ID"}'
```

Replace `YOUR_PROJECT_REF`, `YOUR_ACCESS_TOKEN`, and `VIDEO_ID`. If the video has captions and the key is set, you should get a JSON object with `title`, `summary`, `tags`, etc.

---

## Troubleshooting

- **“Function deploy failed” / “internal error”**  
  Run with debug:  
  `supabase functions deploy extract-pattern-from-video --debug`  
  Ensure Docker is running. You can also try:  
  `supabase functions deploy extract-pattern-from-video --use-api`

- **“Could not fetch transcript”**  
  The video may have no captions, or YouTube’s page structure may have changed. The function only supports YouTube URLs and depends on captions being present.

- **401 Unauthorized from the app**  
  The share extension sends the user’s Supabase access token. Ensure the user is signed in and that `AuthService` is writing the session into the App Group so the extension can read it.

- **Secrets not visible to the function**  
  After changing secrets, redeploy once:  
  `supabase functions deploy extract-pattern-from-video`

---

## Summary

| Step | Command / action |
|------|-------------------|
| 1 | `supabase login` |
| 2 | `cd PatternVault` then `supabase link --project-ref YOUR_PROJECT_ID` |
| 3 | `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...` |
| 4 | `supabase functions deploy extract-pattern-from-video` |

After that, sharing a YouTube link to Pattern Vault will use this function to extract pattern info from the video’s captions.
