//
//  AnimatedCrowView.swift
//  PatternVault
//
//  Makes the crow mascot feel alive with a gentle bob and subtle pulse.
//  No extra dependencies — pure SwiftUI. Use anywhere you show the crow.
//

import SwiftUI

struct AnimatedCrowView: View {
    var size: CGFloat = 120
    /// If true, adds a gentle vertical bob and scale pulse. If false, only a very subtle idle motion.
    var isProminent: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : (isProminent ? sin(t * 1.2) * 4 : sin(t * 0.8) * 2)
            let scale = reduceMotion ? 1.0 : (isProminent ? 1.0 + sin(t * 0.9) * 0.04 : 1.0)
            let tilt = reduceMotion ? 0 : sin(t * 0.6) * 2.5

            Image("CrowMascot")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(scale)
                .offset(y: bob)
                .rotationEffect(.degrees(tilt))
        }
        .frame(width: size, height: size + (isProminent ? 12 : 6))
    }
}

#Preview("Prominent (empty state)") {
    AnimatedCrowView(size: 120, isProminent: true)
        .padding()
}

#Preview("Subtle (inline)") {
    AnimatedCrowView(size: 60, isProminent: false)
        .padding()
}
