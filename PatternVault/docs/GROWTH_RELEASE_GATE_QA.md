# Growth Release-Gate QA

Use this checklist before enabling growth experiments in production.

## 1) Review Prompt Gating

- Review request is only attempted after a positive event (`firstSave`, `progressLogged`, `patternCompleted`, `milestoneCelebration`).
- Review request is suppressed after recent friction (`auth`, `network/retry`, parsing/import, purchase fail/cancel, interruption-heavy flow).
- Cooldown is enforced (120 days).
- Once-per-version and daily caps are enforced.
- `review_shown` and `review_suppressed` events appear with expected properties.

## 2) Paywall Suppression + Frequency

- `canShowPaywall` is used at all entry surfaces (`settings`, `dashboard`, `patternLimit`, `aiLimit`, `notePhotoLimit`).
- Suppression reasons are emitted through `paywall_suppressed`.
- Dismissal counts increment and enforce daily/version caps.
- `paywall_shown`, `paywall_dismissed`, and `paywall_converted` fire with `entry_surface`.

## 3) Paywall UX Experiment Controls

- Annual-first ordering is active.
- Variant mode is respected (`annualOnly` vs `annualPlusMonthly`).
- Restore purchase path remains visible and functional.
- No coercive or urgency copy is introduced.

## 4) Tutorial + Onboarding Event Integrity

- `onboarding_slide_viewed`, `onboarding_skipped`, `onboarding_completed` emit correctly.
- `tutorial_started`, `tutorial_step_viewed`, `tutorial_skipped`, `tutorial_completed` emit correctly.
- Tutorial step metadata (`step_id`, `step_index`, `is_last_step`) is present.

## 5) Compliance and Trust Guardrails

- Premium CTA only appears in entitlement/limit-relevant AI error contexts.
- Entitlement unlock checks only known active premium product IDs.
- Legal/support links continue to resolve from app settings without regressions.

## 6) Production Readout Setup

- Dashboard includes rating velocity, paywall conversion by entry surface, and suppression reason rates.
- Baseline week is captured before experiment activation.
- Guardrails (D1/D7 retention, support complaints, refund trend) are monitored during rollout.

