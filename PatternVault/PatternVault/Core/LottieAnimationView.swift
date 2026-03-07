//
//  LottieAnimationView.swift
//  PatternVault
//
//  SwiftUI wrapper for Lottie animations. Use for empty states, loading, or polish.
//  Add .json files to the project (e.g. Animations group) and reference by name (without extension).
//

import SwiftUI
import Lottie

/// A SwiftUI view that plays a Lottie animation by name, with a fallback when the animation isn't in the bundle.
struct LottieAnimationView<Fallback: View>: View {
    let name: String
    let loop: Bool
    let fallback: () -> Fallback

    init(
        name: String,
        loop: Bool = true,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.name = name
        self.loop = loop
        self.fallback = fallback
    }

    private var animationExists: Bool {
        Bundle.main.url(forResource: name, withExtension: "json") != nil
            || Bundle.main.url(forResource: name, withExtension: "lottie") != nil
    }

    var body: some View {
        if animationExists {
            LottieView(animation: .named(name))
                .playing(loopMode: loop ? .loop : .playOnce)
                .animationSpeed(1.0)
        } else {
            fallback()
        }
    }
}
