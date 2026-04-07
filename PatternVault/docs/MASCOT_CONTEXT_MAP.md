# Mascot Context Map

This map is the source of truth for mascot emotional intent per UI context.

## Intent Taxonomy

- `greeting`: welcome and discoverability moments.
- `focus`: active work, parsing, and helper guidance.
- `encourage`: empty states and "you can do this" nudges.
- `celebrate`: successful user actions and rewards.
- `concern`: recoverable error and retry states.
- `curious`: hints, tips, and story reveal moments.

## Current Screen Mapping

- `Dashboard loading` -> `focus` -> `ThinkingMascotFrames`
- `Dashboard pet interaction` -> `encourage` -> `PettingMascotFrames`
- `Dashboard feed success` -> `focus` -> `KnittingMascotFrames`
- `Dashboard invalid treat` -> `concern` -> `PoutyMascotFrames`
- `Tappable mascot (generic)` -> `encourage` -> `PettingMascotFrames`
- `Loading lists (patterns/tools/stash)` -> `focus` -> `ThinkingMascotFrames`
- `Empty states` -> `encourage` -> `IdleMascotFrames`
- `Error states` -> `concern` -> `PoutyMascotFrames`
- `Onboarding hero` -> `greeting` -> `WavingMascotFrames`
- `Onboarding analyze summary` -> `focus` -> `ThinkingMascotFrames`
- `Onboarding companion named overlay` -> `celebrate` -> `JumpingMascotFrames`
- `Story cutscene (craft beats)` -> `focus` -> `KnittingMascotFrames`
- `Story cutscene (reveal beats)` -> `curious` -> `ThinkingMascotFrames`
- `Tutorial bubble speaker` -> `focus` -> `ThinkingMascotFrames`
- `Tutorial done` -> `celebrate` -> `JumpingMascotFrames`

## Fallback Rule

If a context-specific animation folder is unavailable at runtime, the app should fall back to `IdleMascotFrames` for loops and `JumpingMascotFrames` for one-shot celebratory actions.
