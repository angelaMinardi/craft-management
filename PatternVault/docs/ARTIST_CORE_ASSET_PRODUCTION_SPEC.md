# Core Asset Kit Production Spec

This is the build-ready commissioning spec for the core mascot kit and onboarding scene pack.

## Scope

Deliver P0 and P1 assets first:

- P0: mascot expression + pose system
- P1: onboarding story scenes

References:
- `PatternVault/docs/ARTIST_CREATIVE_BRIEF.md`
- `PatternVault/docs/MASCOT_ASSET_HANDOFF.md`

## P0: Mascot Expression and Pose Kit

## Expression set (required)

- neutral-friendly
- happy
- proud
- focused
- empathetic
- playful

For each expression, provide:

- Bust crop (UI callouts)
- Full-body pose (hero and empty states)

## Pose set (required)

- idle standing
- wave
- point/guide
- cheering jump
- knitting/crafting action

For each pose, provide:

- Transparent PNG exports
- Layered source file with grouped parts

## Animation folders (required for iOS)

Provide frame sequences using existing app contract:

- `OnboardingMascotFrames/`
- `IdleMascotFrames/`
- `WalkingMascotFrames/`
- `JumpingMascotFrames/`
- `PoutyMascotFrames/`
- `KnittingMascotFrames/`

Frame naming:

- `frame_000.png` through `frame_0NN.png`
- Follow `frame_%03d.png`

Frame count guidance:

- Looping: 24-36
- One-shot jump: 18-30

## P1: Onboarding Story Scene Pack

## Required scenes

- Scene A: Bond moment (name + personality)
- Scene B: First-win intention (save/import prompt)
- Scene C: Purpose framing (why preferences matter)
- Scene D: Optional premium value moment (calm, non-pushy)

## Variants required per scene

- iOS portrait hero crop
- compact crop for smaller devices
- web-friendly landscape crop

## Layout constraints

- Reserve text-safe zone in top and bottom thirds.
- Avoid placing essential character details at edges.
- Keep visual focus centered for dynamic crop reuse.

## Midpoint UI-Fit Checkpoint (Mandatory)

Run midpoint review before final render polish.

Check:

- Legibility at small sizes
- Contrast behind copy overlays
- Mascot expression readability against Warm Cream backgrounds
- No visual clutter in onboarding text areas

If any fail, revise before continuing to final exports.

## File Naming and Versioning

Use deterministic names:

- `mascot_expression_<name>_v1.png`
- `mascot_pose_<name>_v1.png`
- `onboarding_scene_<a|b|c|d>_<variant>_v1.png`

Source files:

- `mascot_core_kit_v1.ai` or `mascot_core_kit_v1.fig`
- `onboarding_scenes_v1.ai` or `onboarding_scenes_v1.fig`

## Delivery Package (Core Kit)

Ship zip:

- `PatternVault_Artist_CoreKit_v1.zip`

Structure:

```text
PatternVault_Artist_CoreKit_v1/
  01_Source/
    mascot_core_kit_v1.ai
    onboarding_scenes_v1.ai
  02_Expressions/
    mascot_expression_*.png
  03_Poses/
    mascot_pose_*.png
  04_OnboardingScenes/
    onboarding_scene_*.png
  05_AnimationFrames/
    OnboardingMascotFrames/frame_000.png...
    IdleMascotFrames/frame_000.png...
    WalkingMascotFrames/frame_000.png...
    JumpingMascotFrames/frame_000.png...
    PoutyMascotFrames/frame_000.png...
    KnittingMascotFrames/frame_000.png...
```

## Acceptance Checklist

Core kit is accepted only when:

- All required expressions and poses delivered
- All required onboarding scenes delivered in all variants
- Animation frames follow naming and folder contract
- Visual style matches locked direction
- UI-fit checkpoint issues resolved
- Source files and exports are both included

