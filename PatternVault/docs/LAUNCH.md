# Corvid Craft Launch Guide

Single source of truth for release readiness and launch execution.

## 1) Release readiness checklist

### Config and secrets

- `Config/Config.xcconfig` created locally and not committed.
- Production `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and required feature keys are set.
- Share extension and widget targets inherit required settings.

### Legal and policy

- App legal URLs are set and live:
  - Privacy
  - Terms
  - Support/contact
- App Store privacy disclosures match actual SDKs and data use.

### App Store and signing

- Version/build numbers set.
- Distribution signing/profiles valid.
- Required capabilities are present (App Groups, Sign in with Apple, etc., as used).
- App icons and required metadata complete.

### Data and backend

- Required migrations applied (through latest).
- RLS policies validated on production project.
- Entitlements migration (`012`) and app config migration (`013`) applied for freemium and AI kill switch behavior.

### Quality gates

- Unit tests pass.
- Manual regression pass completed (see `docs/TESTING.md`).
- App Review checklist completed (see `docs/APP_REVIEW_CHECKLIST.md`).
- Share extension smoke-tested on real URLs.
- In-app account deletion tested end-to-end in staging/production-like environment.

## 2) Launch day operations

- Publish coordinated announcement assets (screenshots + short demo clip).
- Post to primary channels the same day (social + community channels).
- Monitor:
  - Crash reports
  - Sign-in failures
  - Share extension save failures
  - AI usage/cost and kill switch status

## 3) Post-launch weekly checklist

- Review AI usage and spend against monthly cap.
- Review ad/subscription performance.
- Triage top user feedback and crash trends.
- Update release notes and prioritize fixes/features.

## 4) Growth playbook (lightweight)

- Share short clips demonstrating one concrete workflow.
- Keep a consistent app voice and visual identity.
- Reuse in-app share surfaces to support organic discovery.

