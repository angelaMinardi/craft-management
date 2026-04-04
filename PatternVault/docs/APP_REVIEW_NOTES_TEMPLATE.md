# App Store Connect - Notes for Review (Template)

Copy/paste this into **Notes for Review** and fill in bracketed fields before each submission.

---

Hello App Review Team,

Thank you for reviewing **Pattern Vault**.

## Build and Access

- Build under review: `[version] ([build])`
- App type: Account-based app (email/Apple/Google sign-in)
- Demo account email: `[reviewer-demo-email]`
- Demo account password: `[reviewer-demo-password]`
- Region notes: `[if any storefront/region-specific behavior]`

## Core User Flows to Test

1. Sign in with demo credentials.
2. Create or edit a pattern in the main app.
3. Add a project note (including optional photo).
4. Open a pattern detail and run **Analyze Steps** (AI parsing).
5. Open Settings and verify legal links, support, and account actions.

## Non-Obvious Features

- **Share Extension (`SaveToPatternVault`)**  
  Share any supported URL/PDF from Safari (or another app) to Pattern Vault.
- **AI behavior**  
  AI step parsing/import can be disabled centrally via backend kill switch (`app_config.ai_enabled`).  
  If disabled, app shows a clear unavailable message and continues non-AI flows.
- **Ravelry integrations**  
  Optional and config-dependent. If keys are absent, related UI shows graceful setup messaging.
- **Ads/Analytics**  
  AdMob is used in the main app free tier only. Firebase Analytics/Crashlytics are optional by configuration.

## Account Deletion (Guideline 5.1.1(v))

- Path: **Settings -> Account -> Delete Account**
- Behavior: Deletion is self-service in-app and removes the user account and user-owned backend data.
- This action is irreversible.

## Test Environment Notes

- Backend services are live during review.
- Required migrations are applied through latest.
- If any feature is temporarily unavailable, user-facing fallback messaging is shown.

## Contact

- Review contact: `[name/email]`
- Response SLA: We monitor this inbox and can reply quickly to unblock review.

---

Optional quick note for update submissions:

- What changed in this build: `[1-4 bullets]`
- Why reviewer should retest specific area(s): `[if applicable]`
