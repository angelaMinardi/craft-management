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
        case .frogged: return dustyBlue
        }
    }

    static func statusIcon(for status: PatternStatus) -> String {
        switch status {
        case .wantToMake: return "heart"
        case .inProgress: return "hammer"
        case .completed: return "checkmark.circle"
        case .frogged: return "arrow.uturn.backward.circle"
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
        static let titleBold = Font.system(.title2, design: .rounded, weight: .bold)
        static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .rounded)
        static let bodySemibold = Font.system(.body, design: .rounded, weight: .semibold)
        static let callout = Font.system(.callout, design: .rounded, weight: .semibold)
        static let footnote = Font.system(.footnote, design: .rounded)
        static let footnoteSemibold = Font.system(.footnote, design: .rounded, weight: .semibold)
        static let caption = Font.system(.caption, design: .rounded)
        static let captionSemibold = Font.system(.caption, design: .rounded, weight: .semibold)
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
        static let textMuted = deepPlum.opacity(0.5)
        static let textOnAccent = Color.white
        static let iconMuted = deepPlum.opacity(0.58)
        static let iconFaint = deepPlum.opacity(0.25)
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

        /// Canonical spring used across the app. Single source of truth.
        static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.8)
        /// Snappier spring for press feedback and quick interactions.
        static let quickSpring: Animation = .spring(response: 0.25, dampingFraction: 0.7)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(configuration.isPressed ? Theme.softCoral.opacity(0.8) : Theme.softCoral)
            .foregroundStyle(Theme.Semantic.textOnAccent)
            .font(Theme.Typography.headline)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.pill))
            .scaleEffect(configuration.isPressed ? Theme.Motion.pressScale : 1.0)
            .animation(reduceMotion ? .none : Theme.Motion.quickSpring, value: configuration.isPressed)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (reduceMotion ? 0 : 16))
            .animation(
                reduceMotion ? .none :
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

    // MARK: - Animation Modifiers

    /// Applies animation only when Reduce Motion is off.
    func motionSafe<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionSafeModifier(animation: animation, value: value))
    }

    /// Shimmer loading effect for skeleton placeholders.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    /// Horizontal shake for validation errors. Set trigger to true to fire.
    func disapprovingShake(trigger: Binding<Bool>) -> some View {
        modifier(DisapprovingShakeModifier(trigger: trigger))
    }
}

// MARK: - MotionSafe Modifier

private struct MotionSafeModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .none : animation, value: value)
    }
}

// MARK: - Shimmer Loading Modifier

struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if !reduceMotion {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Theme.softCoral.opacity(0.12), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .rotationEffect(.degrees(15))
                        .offset(x: phase * 300)
                        .onAppear {
                            withAnimation(
                                .linear(duration: Theme.Motion.expressive * 2)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 1
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }
}

/// Skeleton placeholder row for loading states.
struct ShimmerPlaceholderView: View {
    var rows: Int = 3
    var rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(Theme.warmCream)
                    .frame(height: rowHeight)
                    .shimmer()
            }
        }
    }
}

// MARK: - Disapproving Shake Modifier

struct DisapprovingShakeModifier: ViewModifier {
    @Binding var trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakeOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                if reduceMotion {
                    // Skip shake — the InputSurfaceModifier hasError border flash handles it.
                    trigger = false
                    return
                }
                // Damped oscillation: -8, 8, -4, 4, 0
                let keyframes: [(CGFloat, Double)] = [
                    (-8, 0.04), (8, 0.04), (-4, 0.04), (4, 0.04), (0, 0.04)
                ]
                var delay: Double = 0
                for (offset, duration) in keyframes {
                    delay += duration
                    let d = delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                        withAnimation(.linear(duration: duration)) {
                            shakeOffset = offset
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05) {
                    trigger = false
                }
            }
    }
}

// MARK: - Card Press Style

struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? .none : Theme.Motion.quickSpring, value: configuration.isPressed)
    }
}
