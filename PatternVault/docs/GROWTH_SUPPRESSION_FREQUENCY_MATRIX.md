# Growth Suppression + Frequency Matrix

Release-gate artifact for all review/paywall prompts. This must be reviewed before enabling growth experiments.

| trigger_event | eligibility_conditions | suppression_conditions | cooldown_window | max_exposures_per_day | max_exposures_per_version | analytics_event_names (shown, dismissed, converted, suppressed_reason) |
|---|---|---|---|---:|---:|---|
| review_after_pattern_save | onboarding complete OR equivalent first-value moment, positive event in current session | auth failure, network/retry error, import/parsing failure, purchase failure/cancel, recent paywall dismissal, interruption-heavy flow | 120 days | 1 | 1 | review_shown, review_suppressed |
| review_after_progress_or_completion | same as above + progress/completion win | same as above | 120 days | 1 | 1 | review_shown, review_suppressed |
| review_after_celebration_dismiss | celebration milestone viewed and dismissed | same as above | 120 days | 1 | 1 | review_shown, review_suppressed |
| paywall_ai_limit | free-tier AI limit reached | auth failure, network/retry error, import/parsing failure, purchase failure/cancel, recent paywall dismissal | 2 hours after friction event | 2 | 6 | paywall_shown, paywall_dismissed, paywall_converted, paywall_suppressed_reason |
| paywall_settings_entry | user opens premium from settings | recent paywall dismissal (quiet period), purchase failure/cancel | 2 hours after friction event | 2 | 6 | paywall_shown, paywall_dismissed, paywall_converted, paywall_suppressed_reason |
| paywall_other_limit_surfaces | user reaches a free-tier cap (patterns/imports/photos) | auth failure, network/retry error, import/parsing failure, purchase failure/cancel, recent paywall dismissal | 2 hours after friction event | 2 | 6 | paywall_shown, paywall_dismissed, paywall_converted, paywall_suppressed_reason |

## Notes

- First-session review ask is allowed only after a true positive emotional peak.
- Review asks are never shown after friction or interruption-heavy flows.
- Paywall presentation mode is experiment-controlled (`annualOnly` vs `annualPlusMonthly`) and annual-first.
- Premium CTA in error alerts must be entitlement/limit-relevant only.
- StoreKit in-app review API does not expose direct dismissed/converted callbacks; use `review_shown` + rating velocity for outcome inference.
