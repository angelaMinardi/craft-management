//
//  SpriteMascotView.swift
//  PatternVault
//
//  Plays sprite animations from bundle subfolders (variable frame count; supports gaps, e.g. frame_003–frame_035).
//  Use: OnboardingMascotFrames (onboarding), IdleMascotFrames (empty/static),
//       WalkingMascotFrames (loading), JumpingMascotFrames (success), PoutyMascotFrames (errors), KnittingMascotFrames (crafting / add pattern).
//

import SwiftUI

struct SpriteMascotView: View {
    /// Bundle subdirectory name, e.g. "OnboardingMascotFrames", "IdleMascotFrames", "WalkingMascotFrames", "JumpingMascotFrames".
    let folder: String
    var size: CGFloat = 180
    var framesPerSecond: Double = 15
    /// If false, plays once and calls onComplete when done.
    var loop: Bool = true
    /// Optional fallback folder if `folder` has no readable frames.
    var fallbackFolder: String?
    var onComplete: (() -> Void)?

    init(
        folder: String = "OnboardingMascotFrames",
        size: CGFloat = 180,
        framesPerSecond: Double = 15,
        loop: Bool = true,
        fallbackFolder: String? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.folder = folder
        self.size = size
        self.framesPerSecond = framesPerSecond
        self.loop = loop
        self.fallbackFolder = fallbackFolder
        self.onComplete = onComplete
    }

    /// Max frame index to try (e.g. 36 for frame_000..frame_035). Frames may be missing; we load whatever exists.
    private let maxFrameIndex = 36

    @State private var currentFrame = 0
    @State private var loadedImages: [UIImage] = []

    var body: some View {
        Group {
            if let img = loadedImages[safe: currentFrame] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            if loadedImages.isEmpty {
                loadFrames()
                startTimer()
            }
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    @State private var timerTask: Task<Void, Never>?

    private func loadFrames() {
        var images = loadFrames(from: folder)
        if images.isEmpty, let fallbackFolder {
            images = loadFrames(from: fallbackFolder)
        }
        loadedImages = images
        if currentFrame >= images.count && !images.isEmpty {
            currentFrame = 0
        }
    }

    private func loadFrames(from folderName: String) -> [UIImage] {
        var images: [UIImage] = []
        for i in 0..<maxFrameIndex {
            let name = String(format: "frame_%03d", i)
            let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folderName)
                ?? Bundle.main.url(forResource: name, withExtension: "png")
            guard let url, let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        return images
    }

    private func startTimer() {
        timerTask?.cancel()
        let count = loadedImages.isEmpty ? maxFrameIndex : loadedImages.count
        guard count > 0 else { return }
        let interval = 1.0 / framesPerSecond
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                if currentFrame + 1 >= count {
                    if loop {
                        currentFrame = (currentFrame + 1) % count
                    } else {
                        currentFrame = count - 1
                        onComplete?()
                        return
                    }
                } else {
                    currentFrame += 1
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Convenience

extension SpriteMascotView {
    /// Idle: empty states, settings, login. Loops gently.
    static func idle(size: CGFloat = 120) -> SpriteMascotView {
        SpriteMascotView(folder: "IdleMascotFrames", size: size, loop: true)
    }

    /// Walking: loading patterns, fetching. Use while isLoading.
    static func walking(size: CGFloat = 80) -> SpriteMascotView {
        SpriteMascotView(folder: "WalkingMascotFrames", size: size, loop: true)
    }

    /// Jumping: play once on success (e.g. Get Started). Call onComplete when done.
    static func jumping(size: CGFloat = 180, onComplete: (() -> Void)? = nil) -> SpriteMascotView {
        SpriteMascotView(folder: "JumpingMascotFrames", size: size, loop: false, onComplete: onComplete)
    }

    /// Pouty: error states, failed load, something went wrong. Loops gently.
    static func pouty(size: CGFloat = 100) -> SpriteMascotView {
        SpriteMascotView(folder: "PoutyMascotFrames", size: size, loop: true)
    }

    /// Knitting: craft-in-progress, add pattern, pattern detail. Loops gently.
    static func knitting(size: CGFloat = 80) -> SpriteMascotView {
        SpriteMascotView(folder: "KnittingMascotFrames", size: size, loop: true)
    }

    /// Waving: greeting moments and discoverability nudges.
    static func waving(size: CGFloat = 120) -> SpriteMascotView {
        SpriteMascotView(folder: "WavingMascotFrames", size: size, loop: true, fallbackFolder: "IdleMascotFrames")
    }

    /// Thinking: processing and helper guidance moments.
    static func thinking(size: CGFloat = 100) -> SpriteMascotView {
        SpriteMascotView(folder: "ThinkingMascotFrames", size: size, loop: true, fallbackFolder: "WalkingMascotFrames")
    }

    /// Petting: one-shot affection reaction to user taps.
    static func petting(size: CGFloat = 120, onComplete: (() -> Void)? = nil) -> SpriteMascotView {
        SpriteMascotView(folder: "PettingMascotFrames", size: size, loop: false, fallbackFolder: "JumpingMascotFrames", onComplete: onComplete)
    }
}

#Preview("Onboarding (default)") {
    SpriteMascotView(size: 180)
        .padding()
}

#Preview("Idle") {
    SpriteMascotView.idle(size: 120)
        .padding()
}

#Preview("Walking") {
    SpriteMascotView.walking(size: 80)
        .padding()
}

#Preview("Pouty") {
    SpriteMascotView.pouty(size: 100)
        .padding()
}
