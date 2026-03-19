//
//  TappableMascotView.swift
//  PatternVault
//
//  Wraps the mascot so a tap plays a short jump animation + haptic. Use in empty states,
//  Settings footer, and floating palette where the mascot is already shown.
//

import SwiftUI

struct TappableMascotView: View {
    var size: CGFloat = 120
    /// When true, tap plays jumping animation then returns to idle. When false, shows idle only (no tap).
    var isInteractive: Bool = true

    @State private var isCheering = false

    var body: some View {
        Group {
            if isCheering {
                SpriteMascotView.jumping(size: min(size * 1.2, 100)) {
                    isCheering = false
                }
                .frame(width: size, height: size)
            } else {
                SpriteMascotView.idle(size: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            isCheering = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mascot")
        .accessibilityHint(isInteractive ? "Tap for a cheer" : "")
    }
}

#Preview("Tappable") {
    TappableMascotView(size: 120, isInteractive: true)
        .padding()
}

#Preview("Static") {
    TappableMascotView(size: 72, isInteractive: false)
        .padding()
}
