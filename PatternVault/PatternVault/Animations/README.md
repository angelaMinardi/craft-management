# Animations

## Crow mascot (SwiftUI)

The crow is animated with **AnimatedCrowView** — no extra dependencies. It uses `TimelineView` for a gentle bob, subtle scale pulse, and tilt. Use it anywhere you show the mascot: `AnimatedCrowView(size: 120, isProminent: true)` for empty states, or `AnimatedCrowView(size: 60, isProminent: false)` for inline (e.g. dashboard header).

## Lottie (optional)

Add `.json` or `.lottie` files here and reference them by name (without extension) in the app via `LottieAnimationView(name: "YourFileName", loop: true) { fallbackView }`.

- **EmptyPatterns** – Bundled minimal animation; the empty state currently uses the animated crow instead, but you can still use Lottie elsewhere.
- [LottieFiles](https://lottiefiles.com) – Download free animations and add them to this folder and the PatternVault target.

## Rive (optional, for a custom animated crow)

If you want a **fully custom animated character** (e.g. the crow waving, blinking, or reacting), use [Rive](https://rive.app):

1. Design and animate the crow in the Rive editor (or hire a designer).
2. Export as `.riv` and add to the project.
3. Add the [Rive iOS runtime](https://github.com/rive-app/rive-ios) via SPM: `https://github.com/rive-app/rive-ios`.
4. In SwiftUI: `RiveViewModel(filename: "crow").view()` (or load from URL).

Rive supports state machines (idle, happy, tap reaction) and runs natively. The current SwiftUI approach keeps the existing crow asset and adds motion without new tools.
