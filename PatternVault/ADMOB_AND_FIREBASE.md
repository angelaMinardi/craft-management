# AdMob (ads) and Firebase (Analytics + Crashlytics)

Freemium setup: banner ads for free users, optional free analytics and crash reporting.

---

## Ads (Google AdMob)

**Already integrated.** Banner ads show at the bottom of the main tab bar for **free** users only; premium users never see ads.

- **SDK:** Google Mobile Ads (Swift Package).
- **Config:** `Info.plist` uses test IDs by default. For production:
  1. Create an app and ad unit in [AdMob](https://admob.google.com).
  2. Replace in **Info.plist** (or set in `Config.xcconfig` and reference from plist):
     - `GADApplicationIdentifier` → your AdMob app ID (e.g. `ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`).
     - `GADBannerAdUnitID` → your banner ad unit ID (e.g. `ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX`).
  3. Optional: add more `SKAdNetworkIdentifier` entries to `SKAdNetworkItems` (AdMob provides a list for attribution).

**Config.xcconfig.example** has commented placeholders for `GAD_APPLICATION_ID` and `GAD_BANNER_AD_UNIT_ID` if you prefer to keep IDs out of plist.

---

## Firebase (Analytics + Crashlytics)

**Optional, free.** Analytics gives usage/engagement; Crashlytics gives crash reports and non‑fatal errors.

- **SDKs:** FirebaseAnalytics, FirebaseCrashlytics, FirebaseCore (Swift Package).
- **Behavior:** Firebase is only initialized if **GoogleService-Info.plist** is present in the app bundle. Without it, the app runs as before (no analytics, no crash reporting).

**To enable:**

1. In [Firebase Console](https://console.firebase.google.com), create a project (or use existing) and add an iOS app with bundle ID `com.patternvault.app`.
2. Download **GoogleService-Info.plist** and add it to the **PatternVault** target (drag into Xcode, ensure “Copy items” and PatternVault target are checked).
3. Build and run. On launch, `FirebaseApp.configure()` runs and Crashlytics/Analytics start automatically.

**Crashlytics symbolication (optional):** For readable stack traces, add a Run Script build phase to upload dSYMs. In Xcode: Target → Build Phases → + → New Run Script Phase. Paste the script from [Firebase Crashlytics dSYM setup](https://firebase.google.com/docs/crashlytics/get-deobfuscated-reports). Typical location for SPM:  
`"${BUILD_DIR%/Build/*}/SourcePackages/artifacts/firebase-ios-sdk/Crashlytics/run"`  
with the input files Firebase documents.

---

## Privacy

- **Ads:** AdMob may collect device/usage data for ad serving; see [Google’s privacy policy](https://policies.google.com/privacy) and your own privacy policy.
- **Firebase:** Analytics and Crashlytics process usage and crash data; see [Firebase terms and privacy](https://firebase.google.com/support/privacy). Mention in your privacy policy that you use Google AdMob and (if enabled) Firebase Analytics/Crashlytics.

Update your **Privacy Policy** and any app-store “data collection” / “third-party SDK” disclosures to include AdMob and, if you add the plist, Firebase.
