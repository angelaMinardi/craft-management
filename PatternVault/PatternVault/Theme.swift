//
//  Theme.swift
//  PatternVault
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Brand Colors (SwiftUI)

    static let warmCream = Color("WarmCream")
    static let softCoral = Color("SoftCoral")
    static let deepPlum = Color("DeepPlum")
    static let sageGreen = Color("SageGreen")
    static let dustyBlue = Color("DustyBlue")
    static let honey = Color("Honey")

    static let cardBackground = Color.white
    static let chipFill = softCoral.opacity(0.12)
    static let inputBackground = Color("WarmCream").opacity(0.6)

    /// Subtle gradient for screens: warm cream with a hint of plum/coral at edges. Sleek, not flat.
    static var screenGradient: LinearGradient {
        LinearGradient(
            colors: [
                warmCream,
                warmCream,
                Color("WarmCream").opacity(0.98),
                Color(red: 0.99, green: 0.96, blue: 0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Brand Colors (UIKit — for Share Extension)

    static let uiWarmCream = UIColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0)
    static let uiSoftCoral = UIColor(red: 0.910, green: 0.514, blue: 0.420, alpha: 1.0)
    static let uiDeepPlum = UIColor(red: 0.290, green: 0.125, blue: 0.251, alpha: 1.0)
    static let uiSageGreen = UIColor(red: 0.659, green: 0.773, blue: 0.627, alpha: 1.0)
    static let uiDustyBlue = UIColor(red: 0.561, green: 0.667, blue: 0.741, alpha: 1.0)
    static let uiHoney = UIColor(red: 0.910, green: 0.722, blue: 0.294, alpha: 1.0)

    // MARK: - Status Colors

    static func statusColor(for status: PatternStatus) -> Color {
        switch status {
        case .wantToMake: return softCoral
        case .inProgress: return honey
        case .completed: return sageGreen
        }
    }

    static func statusIcon(for status: PatternStatus) -> String {
        switch status {
        case .wantToMake: return "heart"
        case .inProgress: return "hammer"
        case .completed: return "checkmark.circle"
        }
    }

    // MARK: - Note Type Colors

    static func noteTypeColor(for type: ProjectNoteType) -> Color {
        switch type {
        case .general: return dustyBlue
        case .yarnInfo: return deepPlum
        case .modifications: return softCoral
        case .progressUpdate: return sageGreen
        }
    }

    static func noteTypeIcon(for type: ProjectNoteType) -> String {
        switch type {
        case .general: return "note.text"
        case .yarnInfo: return "tag"
        case .modifications: return "pencil.and.ruler"
        case .progressUpdate: return "chart.line.uptrend.xyaxis"
        }
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title2, design: .rounded, weight: .semibold)
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded)
        static let caption2 = Font.system(.caption2, design: .rounded)
        static let cardTitle = Font.system(.subheadline, design: .rounded, weight: .semibold)
        static let cardSubtitle = Font.system(.caption2, design: .rounded)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 100
    }

    // MARK: - Semantic Surface and Text Roles

    enum Semantic {
        static let textPrimary = deepPlum
        static let textSecondary = deepPlum.opacity(0.72)
        static let textTertiary = deepPlum.opacity(0.62)
        static let textOnAccent = Color.white
        static let iconMuted = deepPlum.opacity(0.58)
        static let surfaceBase = cardBackground
        static let surfaceSubtle = warmCream.opacity(0.7)
        static let borderSubtle = deepPlum.opacity(0.08)
        static let borderStandard = deepPlum.opacity(0.12)
        static let borderStrong = deepPlum.opacity(0.22)
        static let accent = softCoral
        static let success = sageGreen
        static let warning = honey
        static let info = dustyBlue
        static let error = softCoral
    }

    // MARK: - Elevation

    enum Elevation {
        static let cardShadowColor = Color.black.opacity(0.06)
        static let cardShadowRadius: CGFloat = 10
        static let cardShadowY: CGFloat = 4
        static let softShadowColor = Color.black.opacity(0.04)
        static let softShadowRadius: CGFloat = 4
        static let softShadowY: CGFloat = 2
    }

    // MARK: - Motion Guardrails

    enum Motion {
        static let quick: Double = 0.2
        static let standard: Double = 0.35
        static let expressive: Double = 0.6
        static let pressScale: CGFloat = 0.96
        static let maxConcurrentAnimatedElements = 2
        static let staggerStep: Double = 0.06
        static let mascotLoopFramesPerSecond: Double = 15
    }

    // MARK: - Premium (consistent copy across app)

    enum Premium {
        /// One-line value prop used in Settings, Paywall, and limit messages.
        static let tagline = "Unlimited vault, project mode, Row Tracker widget, stash matching, and ad-free."
        /// Short teaser for non-intrusive placements (Dashboard, list).
        static let teaser = "Unlimited patterns, project mode, no ads & more with Premium"
        /// CTA when user hits a limit or we want to surface Premium.
        static let seePremiumTitle = "See Premium"
    }
}

// MARK: - View Modifiers

struct CardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: elevated ? 20 : Theme.CornerRadius.medium))
            .shadow(
                color: Color.black.opacity(elevated ? 0.06 : 0.05),
                radius: elevated ? 12 : 4,
                x: 0,
                y: elevated ? 4 : 2
            )
    }
}

/// Softer, more interactive card for lists and dashboards. Larger radius, subtle shadow.
struct ElevatedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Semantic.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(
                color: Theme.Elevation.cardShadowColor,
                radius: Theme.Elevation.cardShadowRadius,
                x: 0,
                y: Theme.Elevation.cardShadowY
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(configuration.isPressed ? Theme.softCoral.opacity(0.8) : Theme.softCoral)
            .foregroundStyle(Theme.Semantic.textOnAccent)
            .font(Theme.Typography.headline)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.pill))
            .scaleEffect(configuration.isPressed ? Theme.Motion.pressScale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct TagPillStyle: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.chipFill : Theme.warmCream)
            .foregroundStyle(isSelected ? Theme.softCoral : Theme.deepPlum)
            .clipShape(Capsule())
    }
}

struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.8)
                .delay(Double(index) * Theme.Motion.staggerStep),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

// MARK: - Bordered Card (inspired by Timespent — stroke outline, no heavy shadow)

struct BorderedCardModifier: ViewModifier {
    var borderColor: Color = Theme.deepPlum.opacity(0.12)
    var cornerRadius: CGFloat = Theme.CornerRadius.large

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1.5)
            )
    }
}

struct AccentBorderedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.CornerRadius.large

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.softCoral.opacity(0.35), lineWidth: 1.5)
            )
    }
}

enum CalloutKind {
    case neutral
    case info
    case success
    case warning
    case error

    var borderColor: Color {
        switch self {
        case .neutral: return Theme.Semantic.borderStandard
        case .info: return Theme.Semantic.info.opacity(0.45)
        case .success: return Theme.Semantic.success.opacity(0.5)
        case .warning: return Theme.Semantic.warning.opacity(0.55)
        case .error: return Theme.Semantic.error.opacity(0.5)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral: return Theme.Semantic.surfaceSubtle
        case .info: return Theme.Semantic.info.opacity(0.12)
        case .success: return Theme.Semantic.success.opacity(0.15)
        case .warning: return Theme.Semantic.warning.opacity(0.16)
        case .error: return Theme.Semantic.error.opacity(0.12)
        }
    }
}

struct CalloutCardModifier: ViewModifier {
    var kind: CalloutKind = .neutral

    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.lg)
            .background(kind.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .stroke(kind.borderColor, lineWidth: 1.5)
            )
    }
}

struct BannerSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Semantic.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .stroke(Theme.Semantic.borderSubtle, lineWidth: 1)
            )
            .shadow(
                color: Theme.Elevation.softShadowColor,
                radius: Theme.Elevation.softShadowRadius,
                x: 0,
                y: Theme.Elevation.softShadowY
            )
    }
}

struct InputSurfaceModifier: ViewModifier {
    var isFocused: Bool = false
    var hasError: Bool = false

    private var borderColor: Color {
        if hasError { return Theme.Semantic.error.opacity(0.75) }
        if isFocused { return Theme.Semantic.accent.opacity(0.8) }
        return Theme.Semantic.borderStandard
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(borderColor, lineWidth: isFocused ? 1.6 : 1.2)
            )
    }
}

struct PaywallModuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.lg)
            .background(
                LinearGradient(
                    colors: [Theme.warmCream, Theme.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Theme.Semantic.borderStandard, lineWidth: 1.5)
            )
            .shadow(
                color: Theme.Elevation.cardShadowColor,
                radius: Theme.Elevation.cardShadowRadius,
                x: 0,
                y: Theme.Elevation.cardShadowY
            )
    }
}

// MARK: - Subtle sparkle overlay (welcome/onboarding backgrounds)

struct SparkleBackgroundView: View {
    private let positions: [(CGFloat, CGFloat)] = [
        (0.12, 0.18), (0.88, 0.22), (0.25, 0.45), (0.72, 0.38), (0.5, 0.72), (0.15, 0.85),
        (0.92, 0.78), (0.35, 0.28), (0.65, 0.62), (0.08, 0.55), (0.82, 0.12), (0.45, 0.92)
    ]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(positions.enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(Theme.softCoral.opacity(0.06))
                        .frame(width: 5, height: 5)
                        .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Reusable Section Header (Luma-style: bold title + optional trailing action)

struct SectionHeaderView: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
            Spacer(minLength: 0)
            if let trailing, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(trailing)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.softCoral)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.softCoral)
                    }
                }
            }
        }
    }
}

// MARK: - Status Badge (compact capsule with icon + text)

struct StatusBadge: View {
    let status: PatternStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Theme.statusIcon(for: status))
                .font(.system(size: 9, weight: .bold))
            Text(status.displayName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.statusColor(for: status))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.statusColor(for: status).opacity(0.12))
        .clipShape(Capsule())
    }
}

extension View {
    func cardStyle(elevated: Bool = false) -> some View {
        modifier(CardModifier(elevated: elevated))
    }

    func elevatedCardStyle() -> some View {
        modifier(ElevatedCardModifier())
    }

    func borderedCard(borderColor: Color = Theme.deepPlum.opacity(0.12)) -> some View {
        modifier(BorderedCardModifier(borderColor: borderColor))
    }

    func accentBorderedCard() -> some View {
        modifier(AccentBorderedCardModifier())
    }

    func tagPill(isSelected: Bool = false) -> some View {
        modifier(TagPillStyle(isSelected: isSelected))
    }

    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppearModifier(index: index))
    }

    func calloutCard(kind: CalloutKind = .neutral) -> some View {
        modifier(CalloutCardModifier(kind: kind))
    }

    func bannerSurface() -> some View {
        modifier(BannerSurfaceModifier())
    }

    func inputSurface(isFocused: Bool = false, hasError: Bool = false) -> some View {
        modifier(InputSurfaceModifier(isFocused: isFocused, hasError: hasError))
    }

    func paywallModule() -> some View {
        modifier(PaywallModuleModifier())
    }
}
