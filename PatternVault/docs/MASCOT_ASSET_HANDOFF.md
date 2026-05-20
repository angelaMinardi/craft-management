# Corvid Craft Mascot Asset Handoff

Use this guide when commissioning professional mascot art and animation for Corvid Craft.
It documents exactly what files the app currently expects, plus recommended production deliverables for future-proofing.

## 1) Required deliverables (must-have)

Provide these files exactly as named.

### A) Static mascot art

1. iOS app mascot image:
   - `PatternVault/PatternVault/Assets.xcassets/CrowMascot.imageset/skein_mascot_crow.png`
2. Website mascot image:
   - `website/public/images/mascot.png`

Current mapped import profile (Mar 2026):

- `Pattern_Vault_Assets/excited_happy_static.png` -> `PatternVault/PatternVault/Assets.xcassets/CrowMascot.imageset/skein_mascot_crow.png`
- `Pattern_Vault_Assets/caw_static.png` -> `PatternVault/PatternVault/Assets.xcassets/CrowExpressions.imageset/skein_expression_sheet_mascot_crow.png`

### B) Sprite animation folders for iOS app

Create these folders at:

- `PatternVault/PatternVault/OnboardingMascotFrames/`
- `PatternVault/PatternVault/IdleMascotFrames/`
- `PatternVault/PatternVault/WalkingMascotFrames/`
- `PatternVault/PatternVault/JumpingMascotFrames/`
- `PatternVault/PatternVault/PoutyMascotFrames/`
- `PatternVault/PatternVault/KnittingMascotFrames/`

Current source-of-truth working folder:

- `Pattern_Vault_Assets/`

Current mapped import profile (Mar 2026):

- `Pattern_Vault_Assets/jump` -> `OnboardingMascotFrames`
- `Pattern_Vault_Assets/idle` -> `IdleMascotFrames`
- `Pattern_Vault_Assets/knitting` -> `WalkingMascotFrames`
- `Pattern_Vault_Assets/jump` -> `JumpingMascotFrames`
- `Pattern_Vault_Assets/idle` -> `PoutyMascotFrames`
- `Pattern_Vault_Assets/knitting` -> `KnittingMascotFrames`

Each folder should contain PNG frames named:

- `frame_000.png`
- `frame_001.png`
- `frame_002.png`
- ...

## 2) File naming contract (critical)

The app loads frames by this exact pattern:

- Filename: `frame_%03d.png`
- Example: `frame_000.png` to `frame_035.png`
- Current code limit: maximum index `035` (`maxFrameIndex = 36`)

If you deliver more than 36 frames per animation, extra frames will not be used until code is updated.

## 3) Animation set specs

| Folder | Emotion/action | Loop | Where used |
|---|---|---|---|
| `OnboardingMascotFrames` | Welcoming hero animation | Yes | Onboarding slides |
| `IdleMascotFrames` | Calm breathing/blink idle | Yes | Empty states, settings, inline support |
| `WalkingMascotFrames` | Walking cycle | Yes | Loading states |
| `JumpingMascotFrames` | Celebration jump | No (play once) | Success and celebration overlays |
| `PoutyMascotFrames` | Gentle disappointed expression | Yes | Error/recovery states |
| `KnittingMascotFrames` | Crafting/knitting action | Yes | Add pattern and dashboard accents |

Recommended frame count per set:

- Looping sets: 24-36 frames
- Jumping (one-shot): 18-30 frames

Target playback in app is currently ~15 FPS.

## 4) Export specs for animator

- Format: PNG-24
- Background: transparent alpha
- Color space: sRGB IEC61966-2.1
- Trim: keep consistent canvas size across all frames in a set
- Avoid: per-frame canvas shifts (causes visible jitter)

Recommended frame canvas:

- Preferred: `1024 x 1024` px
- Minimum acceptable: `768 x 768` px

Why: mascot is displayed up to ~200pt in-app; this keeps it crisp on modern Retina screens.

## 5) Character design guardrails

Keep the mascot recognizable across all poses:

- Preserve silhouette (head/body/beak proportions)
- Keep facial landmarks in stable positions
- Maintain color consistency with brand palette
- Use expressive but readable poses at small sizes
- Avoid ultra-thin strokes that disappear on mobile

## 6) Optional but strongly recommended deliverables

Ask your illustrator/animator to also provide:

1. Master source files
   - `mascot_master.ai` (or equivalent vector source)
   - `mascot_rig.riv` or animation project source (if rigged workflow)
2. Expression sheet
   - Neutral, happy, excited, focused, pouty
3. Layer-separated parts export
   - Head/body/beak/wings/accessories on separate layers
4. License handoff note
   - Commercial rights + modification rights + unlimited app/web use

## 7) Optional current app slot: expression sheet

If you want to maintain the expression sheet asset in iOS:

- `PatternVault/PatternVault/Assets.xcassets/CrowExpressions.imageset/skein_expression_sheet_mascot_crow.png`

This is currently available as an asset slot and can be refreshed with final art.

## 8) Handoff package structure (what to request)

Ask for a zip named:

- `PatternVault_Mascot_v1.zip`

With structure:

```text
PatternVault_Mascot_v1/
  01_Masters/
    mascot_master.ai
    mascot_master.psd
    mascot_rig.riv
  02_Static/
    skein_mascot_crow.png
    mascot.png
    skein_expression_sheet_mascot_crow.png
  03_Animations/
    OnboardingMascotFrames/frame_000.png ... frame_0NN.png
    IdleMascotFrames/frame_000.png ... frame_0NN.png
    WalkingMascotFrames/frame_000.png ... frame_0NN.png
    JumpingMascotFrames/frame_000.png ... frame_0NN.png
    PoutyMascotFrames/frame_000.png ... frame_0NN.png
    KnittingMascotFrames/frame_000.png ... frame_0NN.png
  04_Legal/
    license.txt
```

## 9) QA checklist before import

- All required folders exist with exact names.
- No missing frame naming sequence (or gaps are intentional).
- Every frame in a set has identical dimensions.
- Transparent background renders cleanly (no matte fringe).
- Colors match approved brand tones.
- Jumping animation reads clearly as a one-shot celebration.
- Idle/walking/knitting loops feel seamless at 15 FPS.

## 10) Developer notes (integration constraints)

Current implementation details:

- Sprite loader is in `PatternVault/PatternVault/Core/SpriteMascotView.swift`
- Loader currently checks `frame_000` through `frame_035`
- Playback defaults to `framesPerSecond = 15`
- Jumping uses `loop: false` and should end on a good resting frame

If your animator needs more than 36 frames per set, update `maxFrameIndex` in `SpriteMascotView.swift` before import.
