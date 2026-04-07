# Acquisition Master Index

This is the entry point for Acquisition Pod operations.
It tells each role what to read first and which documents are authoritative.

## Canonical Sources

- Taxonomy and confidence rules:
  - `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`
- Stop-loss defaults and experiment record of truth:
  - `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`
- Weekly reporting structure:
  - `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
- Cross-pod ownership and handoff process:
  - `docs/ACQUISITION_CROSS_POD_HANDOFFS.md`
- Message continuity source of truth:
  - `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md`

## Role-Based Quick Starts

### Acquisition Lead

Read in this order:
1. `docs/ACQUISITION_POD_KICKOFF_PACKET.md`
2. `docs/ACQUISITION_WEEKLY_OPERATING_RHYTHM.md`
3. `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
4. `docs/ACQUISITION_CROSS_POD_HANDOFFS.md`

### Paid Operations

Read in this order:
1. `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`
2. `docs/ACQUISITION_CREATIVE_BRIEFS.md`
3. `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`
4. `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`

### ASO Manager

Read in this order:
1. `docs/ACQUISITION_KEYWORD_MAP.md`
2. `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md`
3. `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`
4. `docs/ACQUISITION_CROSS_POD_HANDOFFS.md`

### Analytics Partner

Read in this order:
1. `docs/ACQUISITION_CAMPAIGN_TAXONOMY.md`
2. `docs/ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md`
3. `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
4. `docs/ACQUISITION_WEEKLY_OPERATING_RHYTHM.md`

### Core/Growth/Extension-Web Liaisons

Read in this order:
1. `docs/ACQUISITION_CROSS_POD_HANDOFFS.md`
2. `docs/ACQUISITION_MESSAGE_SYNC_MATRIX.md`
3. `docs/ACQUISITION_WEEKLY_GROWTH_READOUT_TEMPLATE.md`
4. `docs/ACQUISITION_POD_KICKOFF_PACKET.md`

## Consolidation Rules

- Use `ACQUISITION_EXPERIMENT_REGISTRY_TEMPLATE.md` as the canonical location for stop-loss defaults.
- Use `ACQUISITION_CAMPAIGN_TAXONOMY.md` as the canonical location for attribution confidence and compliance preflight definitions.
- Other docs should reference these sources instead of redefining conflicting values.

## Weekly Maintenance

- Confirm links and ownership fields are current.
- Confirm no duplicate or conflicting threshold definitions were introduced.
- Confirm every active experiment appears in the registry and weekly readout.

