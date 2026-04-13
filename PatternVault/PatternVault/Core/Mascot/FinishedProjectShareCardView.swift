//
//  FinishedProjectShareCardView.swift
//  PatternVault
//
//  Layout for the "finished project" share image: pattern name, yarn, needle, notes, crow + branding.
//

import SwiftUI
import UIKit

struct FinishedProjectShareCardView: View {
    let patternTitle: String
    let yarnUsed: String?
    let needleSize: String?
    let notes: String?

    private let cardWidth: CGFloat = 400
    private let cardHeight: CGFloat = 500

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Theme.warmCream,
                    Theme.warmCream,
                    Theme.softCoral.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: cardWidth, height: cardHeight)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Finished project")
                    .font(Theme.Typography.footnoteSemibold)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                Text(patternTitle)
                    .font(Theme.Typography.titleBold)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let yarn = yarnUsed, !yarn.isEmpty {
                        row(icon: "tag", text: yarn)
                    }
                    if let needle = needleSize, !needle.isEmpty {
                        row(icon: "ruler", text: needle)
                    }
                    if let n = notes, !n.isEmpty {
                        row(icon: "note.text", text: n)
                            .lineLimit(2)
                    }
                }
                .font(Theme.Typography.footnoteSemibold)
                .foregroundStyle(Theme.deepPlum.opacity(0.85))
                Spacer(minLength: 0)
            }
            .frame(width: cardWidth - 48, height: cardHeight - 80, alignment: .leading)
            .padding(.leading, 24)
            .padding(.top, 28)

            HStack(spacing: 6) {
                Image("CrowMascot")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                Text("Pattern Vault")
                    .font(Theme.Typography.captionSemibold)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(20)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.softCoral)
                .frame(width: 18, alignment: .center)
            Text(text)
        }
    }
}

// MARK: - Share sheet (presents UIActivityViewController with the card image)

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview {
    FinishedProjectShareCardView(
        patternTitle: "Fluffy Sweater",
        yarnUsed: "Malabrigo Rios, Worsted",
        needleSize: "US 8 (5 mm)",
        notes: "Knit in the round; added 2\" length."
    )
}
#endif
