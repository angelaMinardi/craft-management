# CTA Analytics Handoff

This schema is owned by Acquisition/Growth for campaign strategy. Extension + Web implements event emission points and mode context plumbing.

## Canonical Events

- `cta_impression`
- `cta_click`

## Canonical Properties

- `cta_destination`: `app_store` | `waitlist` | `referral`
- `cta_mode`: `liveFirst` | `prelaunchFirst`
- `page_section`: `header` | `hero` | `closing` | `footer` | `contact`
- `fallback_used`: `true` | `false`

## Implementation Notes

- Every rendered CTA includes `data-*` attributes that map directly to these properties.
- Acquisition controls `PUBLIC_CTA_MODE` and destination URLs.
- Web components consume mode/config and do not embed campaign decision logic.
