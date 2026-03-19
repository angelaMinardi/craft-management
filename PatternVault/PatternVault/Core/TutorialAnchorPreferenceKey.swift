//
//  TutorialAnchorPreferenceKey.swift
//  PatternVault
//
//  Preference key and view modifier for reporting tutorial anchor frames to the overlay.
//

import SwiftUI

/// Frames reported by tab content for the current tutorial anchor (in global coordinates).
struct TutorialAnchorFrames: Equatable {
    var frames: [TutorialAnchor: CGRect] = [:]

    static func merge(_ a: TutorialAnchorFrames, _ b: TutorialAnchorFrames) -> TutorialAnchorFrames {
        var merged = a.frames
        for (key, value) in b.frames {
            merged[key] = value
        }
        return TutorialAnchorFrames(frames: merged)
    }
}

struct TutorialAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: TutorialAnchorFrames { TutorialAnchorFrames() }

    static func reduce(value: inout TutorialAnchorFrames, nextValue: () -> TutorialAnchorFrames) {
        value = TutorialAnchorFrames.merge(value, nextValue())
    }
}

/// Call from a view that should report its frame for a given anchor when the tutorial is on that step.
struct TutorialAnchorModifier: ViewModifier {
    let anchor: TutorialAnchor
    let isActive: Bool
    let coordinateSpace: CoordinateSpace

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: TutorialAnchorPreferenceKey.self,
                            value: isActive ? TutorialAnchorFrames(frames: [anchor: geo.frame(in: coordinateSpace)]) : TutorialAnchorFrames()
                        )
                }
            )
    }
}

extension View {
    /// Report this view's frame as the given tutorial anchor when `isActive` is true.
    func tutorialAnchor(_ anchor: TutorialAnchor, isActive: Bool, coordinateSpace: CoordinateSpace = .global) -> some View {
        modifier(TutorialAnchorModifier(anchor: anchor, isActive: isActive, coordinateSpace: coordinateSpace))
    }
}
