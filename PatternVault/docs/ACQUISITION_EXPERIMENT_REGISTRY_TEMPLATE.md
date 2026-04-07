# Acquisition Experiment Registry Template

Use this as the source of truth for all acquisition experiments.
One row per experiment. Keep historical rows; do not overwrite outcomes.

## Governance Rules

- Prioritize with ICE or RICE scoring before launch.
- Cap concurrent live experiments to prevent signal collision.
- Apply stop-loss thresholds with automatic rollback/escalation.
- Include attribution confidence tier on every report slice.

## Stop-Loss Defaults

Tune thresholds over time; start with:

- CAC deterioration: +20% vs trailing 4-week baseline
- activation drop: -10% install-to-onboarding-complete vs control/baseline
- D7 retention drop: -10% vs control/baseline
- complaint spike: +30% support/store complaints tagged to active experiment

If any threshold is breached for two consecutive measurement windows, trigger rollback and escalation.

## Registry Columns

| experimentId | hypothesis | intentCluster | creativeFamily | channel | owner | priorityMethod | priorityScore | successMetric | guardrails | attributionConfidence | compliancePreflight | startDate | endDate | status | finalDecision | notes |
| --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXP-2026-001 | If we lead with "save from anywhere" in first-win demo ads, onboarding completion will increase in utility-seeker traffic. | saveFromWeb | firstWinDemo | meta | Acquisition | ICE | 7.8 | onboarding completion rate | CAC <= baseline +20%; D7 retention >= baseline -10% | medium | passed | 2026-03-24 | 2026-03-31 | completed | scale | Confidence medium due to partial source mapping. |
| EXP-2026-002 | If paywall copy emphasizes calm organization outcomes, purchase conversion will increase without retention harm. | beginnerOrganizer | outcomeReel | appleSearchAds | Acquisition + Core | RICE | 64 | purchase conversion rate | activation >= baseline -10%; complaints <= baseline +30% | directional | passed | 2026-04-01 | 2026-04-08 | planned | pending | Requires Core implementation slot and release coordination. |

## Weekly Readout Snippet (Paste Under Active Week)

`Week of YYYY-MM-DD`

- Top winner:
  - `experimentId`:
  - why it won:
  - confidence tier:
  - recommended action:
- At-risk experiment:
  - `experimentId`:
  - breached guardrail:
  - rollback/escalation action:
- Product recommendations to pods:
  - Core:
  - Growth:
  - Extension-Web:

