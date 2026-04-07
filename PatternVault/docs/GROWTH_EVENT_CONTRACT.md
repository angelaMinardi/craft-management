# Growth Event Contract

This contract defines event names and core properties for in-app growth orchestration analytics.

## Event Names

- `onboarding_slide_viewed`
- `onboarding_skipped`
- `onboarding_completed`
- `growth_positive_event`
- `growth_friction_event`
- `review_shown`
- `review_suppressed`
- `paywall_shown`
- `paywall_dismissed`
- `paywall_converted`
- `paywall_suppressed`
- `tutorial_started`
- `tutorial_step_viewed`
- `tutorial_skipped`
- `tutorial_completed`

## Core Properties

- `app_version`: app semantic version from bundle.
- `entry_surface`: paywall entry context (e.g., `settings`, `aiLimit`).
- `suppressed_reason`: suppression enum when a prompt is blocked.
- `event_name`: event subtype for grouped events (`growth_positive_event`, `growth_friction_event`).
- `step_index`: onboarding/tutorial step index.
- `step_id`: tutorial anchor id.
- `is_last_step`: tutorial step terminal indicator.

## Observability Notes

- StoreKit in-app review prompts do not provide direct callback telemetry for dismissed or converted outcomes.
- `review_shown` means the app requested the prompt while eligible; final user action is inferred via aggregate ratings velocity.

## Suppression Reason Values

- `onboardingIncomplete`
- `noPositiveEvent`
- `recentFriction`
- `reviewCooldown`
- `reviewAlreadyShownToday`
- `reviewAlreadyShownThisVersion`
- `paywallRecentFriction`
- `paywallDailyCap`
- `paywallVersionCap`

