//
//  PatternCardView.swift
//  PatternVault
//
//  Modern card with image overlay title, status strip, and refined badges.
//

import SwiftUI

struct PatternCardView: View {
    let pattern: Pattern
    /// When set, images load from local cache first and are cached for offline use.
    var userId: UUID? = nil
    var isFavorite: Bool = false
    var isNew: Bool = false
    /// Use for dashboard/recent; softer shadow and larger radius.
    var elevated: Bool = false
    /// Optional subtitle (e.g. designer/source) below title for horizontal lists.
    var subtitle: String? = nil

    private var imageHeight: CGFloat { elevated ? 180 : 160 }
    private var placeholderAssetName: String {
        let options = ["CrowMascot", "CrowExpressions"]
        let seed = pattern.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return options[seed % options.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image only (no overlay) so card clipping doesn't cut off text
            ZStack(alignment: .topLeading) {
                if let thumbnailUrl = pattern.thumbnailUrl,
                   let imageURL = URL(string: thumbnailUrl) {
                    CachedAsyncImage(url: imageURL, userId: userId) { phase in
                        switch phase {
                        case .loading:
                            placeholderImage
                                .overlay { ProgressView().tint(Theme.softCoral) }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: imageHeight)
                                .clipped()
                        case .failure:
                            placeholderImage
                        }
                    }
                    .accessibilityLabel("Thumbnail for \(pattern.title)")
                } else {
                    placeholderImage
                        .accessibilityLabel("No thumbnail for \(pattern.title)")
                }
                // Badges on image (small, top corner)
                if isFavorite || isNew {
                    HStack(spacing: 4) {
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Theme.softCoral.opacity(0.85))
                                .clipShape(Circle())
                                .accessibilityLabel("Favorite")
                        }
                        if isNew {
                            Text("NEW")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Theme.sageGreen.opacity(0.85))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
            }
            .frame(height: imageHeight)

            // Title below image — truncate with ellipsis so text never clips at card edges
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.title)
                    .font(Theme.Typography.footnoteSemibold)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.caption2.weight(.semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pattern.isEnriching {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Processing…")
                                .font(Theme.Typography.caption2.weight(.semibold))
                                .foregroundStyle(Theme.dustyBlue)
                        }
                        Text("We'll notify you when it's ready")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.deepPlum.opacity(0.45))
                    }
                } else if pattern.enrichmentFailed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.softCoral)
                        Text("Details incomplete")
                            .font(Theme.Typography.caption2.weight(.semibold))
                            .foregroundStyle(Theme.softCoral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            // Status strip — thin colored bar at bottom
            Theme.statusColor(for: pattern.status)
                .frame(height: 3)
        }
        .frame(width: elevated ? 168 : nil, alignment: .leading)
        .frame(minWidth: 0, maxWidth: elevated ? 168 : .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .cardStyle(elevated: elevated)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pattern.title), \(pattern.status.displayName)")
        .accessibilityHint("Opens pattern details")
    }

    private var placeholderImage: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.warmCream,
                    Theme.softCoral.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(placeholderAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .opacity(0.9)
            }
        }
        .frame(height: imageHeight)
    }
}
