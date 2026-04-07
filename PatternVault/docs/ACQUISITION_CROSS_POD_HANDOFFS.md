# Acquisition Cross-Pod Handoff Checklist

This checklist governs how Acquisition recommendations move into product execution.

## Ownership Model

- Acquisition Pod owns: test design, taxonomy governance, readout cadence, recommendation quality.
- Core/Growth/Extension-Web pods own: implementation scope, technical feasibility, prioritization, and release timing.

## Handoff Trigger Conditions

Open a handoff ticket when any of the following are true:

- Two consecutive weeks show directional or better improvement in activation quality.
- A paywall copy/framing experiment shows conversion lift without guardrail breaches.
- A channel/creative combo significantly improves CAC/payback quality in a priority cluster.
- A messaging mismatch appears between ad/store/in-app/web surfaces.

## Required Handoff Payload

- experimentId(s)
- target pod(s)
- problem statement
- recommended change
- expected KPI impact
- confidence tier (`high`/`medium`/`directional`)
- risk and guardrail notes
- compliance preflight status (if review/subscription-adjacent)
- ICE/RICE score and prioritization rationale
- recommended release window

## Pod-Specific Checklists

### Core Pod Handoff

- [ ] Onboarding or paywall variant details included
- [ ] UX scope and copy variants clearly defined
- [ ] Instrumentation dependency called out
- [ ] Guardrails and rollback criteria included

### Growth Pod Handoff

- [ ] Event schema changes proposed (if needed)
- [ ] Attribution assumptions documented
- [ ] Dashboard/readout field updates listed
- [ ] Confidence-tier reporting impact explained

### Extension-Web Pod Handoff

- [ ] Web/store messaging changes specified
- [ ] `/privacy`, `/terms`, `/contact` consistency verified
- [ ] CTA and promise continuity specified
- [ ] Launch sequencing dependencies listed

## Compliance Preflight Gate (Mandatory)

Required before launching any change touching review prompts, subscription framing, urgency language, or discount presentation:

- [ ] App Store-safe review behavior confirmed
- [ ] Subscription language is transparent and non-deceptive
- [ ] Urgency/discount claims are factual and bounded
- [ ] Legal copy consistency verified across web legal routes
- [ ] Pod owner sign-off captured

Canonical definition source:
- `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`

## Escalation and Stop-Loss Process

If guardrails breach threshold for two consecutive windows:

1. Pause or rollback experiment-linked rollout.
2. Notify pod owners and Acquisition lead the same day.
3. Document breach type (CAC, activation, D7 retention, complaint spike).
4. Open follow-up diagnosis task with owner and due date.

Canonical threshold source:
- `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`

## Weekly Cadence

- Monday: Acquisition readout prepared with confidence tiers.
- Tuesday: Cross-pod review and handoff decisions.
- Wednesday-Friday: Pod-level scoping, implementation planning, and release scheduling.

