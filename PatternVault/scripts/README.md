# Scripts

## ravelry-check-pattern.sh

**Troubleshoot why Ravelry PDFs aren’t showing in the app.** Calls the Ravelry API and prints the response shape and whether `pdf_url` / `free_pdf_url` are present.

Uses **Basic auth** (Personal API keys), not the app’s OAuth token. Get keys from [Ravelry Pro Developer](https://www.ravelry.com/pro/developer). **Note:** Ravelry may return **403 Forbidden** (“Your application was not authorized”) for app credentials on `patterns.json`; that endpoint may require a user OAuth 2.0 token. If you see 403, use the in-app troubleshooting below instead.

### Usage

```bash
# From repo root
cd /path/to/CraftManagement/PatternVault

# Set credentials (same keys as in Config.xcconfig for RAVELRY_ACCESS_KEY / RAVELRY_PERSONAL_KEY)
export RAVELRY_ACCESS_KEY=your_access_key
export RAVELRY_PERSONAL_KEY=your_personal_key

# Check one pattern by ID (default ID 124400 if omitted)
./scripts/ravelry-check-pattern.sh
./scripts/ravelry-check-pattern.sh 456789
```

### What to look for

- **`.patterns type`** — `array` or `object`. The app supports both; this confirms what Ravelry returns.
- **`pdf_url` / `free_pdf_url`** — If both are `(missing)` for a pattern that has a PDF on the website, the API may not return PDF links for that pattern or for your auth.
- **Nested `.pattern`** — If the first element has a `.pattern` wrapper, the app’s parser supports that.

If the script shows a `pdf_url` for a pattern but the app still doesn’t after import, the problem is likely in the app. If the script returns **403**, or shows no `pdf_url`, use **in-app troubleshooting** instead.

### In-app troubleshooting (when script gets 403 or you use “Connect Ravelry”)

1. In Xcode, run the app (Simulator or device) with the **Debug** scheme.
2. **Connect Ravelry** in Settings if needed, then tap **Import my Ravelry library**.
3. Watch the **Xcode console**. You should see lines like:
   - `[Ravelry] fetchPatternDetails: patterns is array, count=N` (or dictionary)
   - `[Ravelry] first pattern id=…, hasPdfUrl=true/false`
   - If `hasPdfUrl=true`, `[Ravelry] first pdfUrl: https://…`
4. If you see `hasPdfUrl=false` for every chunk, the API is not returning PDF links for your account/library. If you see `fetchPatternDetails returned empty for chunk of N ids`, the response shape may not be parsed correctly.

### Finding a pattern ID

- From a Ravelry pattern page URL, the numeric ID is sometimes in the URL or in the page source.
- Or search: `https://api.ravelry.com/patterns/search.json?query=Blossom+Robe` (with same Basic auth) and use the `id` from the first result.
