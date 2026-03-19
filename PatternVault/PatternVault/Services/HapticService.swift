//
//  HapticService.swift
//  PatternVault
//
//  Centralized haptic feedback for primary actions and key moments.
//

import UIKit

enum HapticService {

    /// Light impact for button taps and selections (e.g. Save, Get Started).
    static func lightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Medium impact for success moments (e.g. pattern saved, celebration).
    static func mediumImpact() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Success notification for completed actions (e.g. sign in, save complete).
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
