# Corvid Craft — Marketing site

Static marketing site for the Corvid Craft app. Promotes the app and hosts legal pages (Privacy, Terms, Contact) at stable URLs for the App Store and in-app links.

## Setup

```bash
npm install
npm run dev   # http://localhost:4321
npm run build # output in dist/
```

## Deploy

- **Vercel:** Connect this repo, set root to `website`, and deploy. Add custom domain (e.g. `corvidcraft.com`) in Vercel project settings.
- **Elsewhere:** Run `npm run build` and serve the `dist/` folder.

## App Store / Info.plist

The iOS app’s `Info.plist` points to:

- `PrivacyPolicyURL` → `https://corvidcraft.com/privacy`
- `TermsOfServiceURL` → `https://corvidcraft.com/terms`
- `SupportURL` → `https://corvidcraft.com/contact`

If you use a different domain, update those URLs in `PatternVault/PatternVault/Info.plist` after deploying.

## Pages

| Path       | Purpose                    |
| ---------- | -------------------------- |
| `/`        | Marketing landing + CTA    |
| `/privacy` | Privacy policy (template)  |
| `/terms`   | Terms of service (template)|
| `/contact` | Support / contact email    |

Privacy and terms are placeholder templates; have a lawyer review before launch.

## Images

- `public/images/app-icon.png` — App icon (from `PatternVault/PatternVault/Assets.xcassets/AppIcon.appiconset/skein_app_icon.png`). Used as favicon, apple-touch-icon, and in the header.
- `public/images/mascot.png` — Crow mascot (from `PatternVault/PatternVault/Assets.xcassets/CrowMascot.imageset/skein_mascot_crow.png`). Shown in the hero and footer. To refresh, copy the latest from the app assets.
