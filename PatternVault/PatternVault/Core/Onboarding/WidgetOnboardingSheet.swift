//
//  WidgetOnboardingSheet.swift
//  PatternVault
//
//  Shown after the user has used the row counter a few times. Explains how to add the Row Tracker lock-screen widget.
//

import SwiftUI

struct WidgetOnboardingSheet: View {
    var onDismiss: () -> Void

    private let steps: [(number: Int, text: String)] = [
        (1, "Long press your Home Screen"),
        (2, "Tap the + button in the corner"),
        (3, "Search for Pattern Vault and add \"Row Tracker\"")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    headerSection
                    mockWidgetSection
                    stepsSection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Row Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        WidgetOnboardingStore.shared.markWidgetOnboardingSeen()
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.softCoral)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TappableMascotView(size: 56)
            Text("Track rows without unlocking your phone")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.deepPlum)
            Text("Add the Row Tracker widget to your Home Screen or Lock Screen to tap +/− without opening the app.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.75))
        }
    }

    private var mockWidgetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Row Tracker widget")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My project")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("Row 38 / 120")
                        .font(.title2.weight(.bold))
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(Theme.softCoral)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.cardBackground.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(Theme.softCoral.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("How to add it")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)
            ForEach(steps, id: \.number) { step in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Text("\(step.number)")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.softCoral)
                        .clipShape(Circle())
                    Text(step.text)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    WidgetOnboardingSheet(onDismiss: {})
}
