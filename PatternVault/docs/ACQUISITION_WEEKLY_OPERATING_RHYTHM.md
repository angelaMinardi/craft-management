# Acquisition Weekly Operating Rhythm

This defines the weekly execution cadence for Acquisition Pod strategy, reporting, and cross-pod handoffs.

## Objectives

- Keep test velocity high without creating cross-team thrash.
- Prioritize by ICE/RICE and limit concurrent live experiments.
- Maintain compliance and attribution realism in all decisions.
- Feed winning messages into store/web/in-app updates with clear ownership.

## Weekly Cadence

### Monday: Data Assembly + Draft Readout

- Update `ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`.
- Populate experiment outcomes and confidence tiers.
- Flag guardrail risks and stop-loss candidates.
- Draft recommendations for Core/Growth/Extension-Web.

### Tuesday: Acquisition Review + Prioritization

- Run internal Acquisition review.
- Score proposed tests with ICE or RICE.
- Select next-week queue and cap concurrent live experiments.
- Prepare handoff payloads for product pods.

### Wednesday: Cross-Pod Handoff Review

- Present recommendations and evidence quality.
- Confirm implementation feasibility and release windows with pods.
- Resolve dependency and sequencing conflicts.
- Record accepted/rejected/deferred decisions.

### Thursday-Friday: Implementation Planning + Launch Prep

- Finalize approved copy variants and campaign setup.
- Complete compliance preflight where required.
- Confirm telemetry/attribution fields needed for reporting.
- Launch eligible tests and update registry status.

## Required Artifacts Per Week

- Updated weekly readout:
  - `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
- Updated experiment registry:
  - `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`
- Updated message continuity table:
  - `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md`
- Any cross-pod handoff packets:
  - `docs/ACQUISITION_CROSS_POD_HANDOFFS.md` checklist entries

## Experiment Governance

### Prioritization

- Use ICE or RICE scoring for every proposed test.
- Minimum required metadata:
  - hypothesis
  - expected KPI impact
  - dependency risk
  - confidence tier expectation

### Concurrency Limits

- Default cap: maximum 3 concurrent live acquisition experiments.
- Do not run overlapping tests targeting the same funnel step and audience without isolation plan.

### Stop-Loss Enforcement

Monitor for two consecutive windows using canonical thresholds:
- `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`

If breached:
1. Pause/rollback affected test.
2. Escalate same day to pod owners.
3. Log root-cause analysis task and owner.

## Attribution and Reporting Language

Use canonical confidence and claim rules from:
- `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`

## Roles and Responsibilities

- Acquisition Pod:
  - owns test design, campaign taxonomy, report quality, and recommendation clarity.
- Core/Growth/Extension-Web pods:
  - own implementation scope, technical feasibility, and release timing.
- Shared:
  - maintain trust/compliance and brand consistency.

## Monthly Review Checkpoint

At month-end, run a deep review:

- top 3 scaled wins and why
- top 3 failed tests and lessons
- attribution confidence improvements needed
- compliance incidents (if any)
- roadmap adjustments for next month

