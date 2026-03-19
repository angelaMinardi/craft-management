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
                } else {
                    placeholderImage
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
                    .font(.system(size: elevated ? 14 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: elevated ? 11 : 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            // Status strip — thin colored bar at bottom
            Theme.statusColor(for: pattern.status)
                .frame(height: 3)
        }
        .frame(width: elevated ? 168 : nil)
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
                Image(systemName: "scissors")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.deepPlum.opacity(0.2))
                Image(systemName: "oval.portrait")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Theme.softCoral.opacity(0.25))
            }
        }
        .frame(height: imageHeight)
    }
}
