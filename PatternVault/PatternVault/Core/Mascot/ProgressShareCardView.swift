//
//  ProgressShareCardView.swift
//  PatternVault
//
//  Branded share card showing in-progress pattern stats. Renders a card image
//  and presents a share sheet so users can post progress to social media.
//

import SwiftUI
import UIKit

struct ProgressShareCardView: View {
    let pattern: Pattern
    @ObservedObject var progressStore: PatternProgressStore
    @ObservedObject var rowCounterStore: RowCounterStore
    @Environment(\.dismiss) private var dismiss

    @State private var shareImage: UIImage?

    private var fraction: Double {
        progressStore.progressFraction(for: pattern.id)
    }

    private var rowState: RowCounterState {
        rowCounterStore.state(for: pattern.id, makeId: nil)
    }

    private var stepInfo: (current: Int, total: Int)? {
        guard let data = progressStore.progress(for: pattern.id),
              let count = data.stepCount, count > 0 else { return nil }
        return (data.currentStepIndex + 1, count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                cardPreview
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)

                Button {
                    renderAndShare()
                } label: {
                    Label("Share Progress", systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.bodySemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Theme.sageGreen)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(Theme.Spacing.xl)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Share Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareImage) { image in
                ShareSheet(image: image)
            }
        }
    }

    // MARK: - Card Layout

    private var cardPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Theme.warmCream, Theme.warmCream, Theme.sageGreen.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Work in progress")
                    .font(Theme.Typography.footnoteSemibold)
                    .foregroundStyle(Theme.sageGreen)

                Text(pattern.title)
                    .font(Theme.Typography.titleBold)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Progress ring + stats
                HStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(Theme.sageGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(fraction * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        if let total = rowState.totalRows, total > 0 {
                            statRow(icon: "arrow.up.arrow.down", text: "Row \(rowState.globalRow) / \(total)")
                        }
                        if let step = stepInfo {
                            statRow(icon: "list.number", text: "Step \(step.current) / \(step.total)")
                        }
                        if let craft = pattern.craftType {
                            statRow(icon: "scissors", text: craft.capitalized)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)

            HStack(spacing: 6) {
                Image("CrowMascot")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                Text("Corvid Craft")
                    .font(Theme.Typography.captionSemibold)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(20)
        }
        .frame(width: 360, height: 420)
    }

    private func statRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.sageGreen)
                .frame(width: 18)
            Text(text)
                .font(Theme.Typography.bodySemibold)
                .foregroundStyle(Theme.deepPlum)
        }
    }

    // MARK: - Render & Share

    @MainActor
    private func renderAndShare() {
        let renderer = ImageRenderer(content: cardPreview)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            shareImage = image
        }
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: Int { hashValue }
}
