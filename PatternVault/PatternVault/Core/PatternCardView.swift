//
//  PatternCardView.swift
//  PatternVault
//
//  Modern card with image overlay title, status strip, and refined badges.
//

import SwiftUI

struct PatternCardView: View {
    let pattern: Pattern
    var isFavorite: Bool = false
    var isNew: Bool = false
    /// Use for dashboard/recent; softer shadow and larger radius.
    var elevated: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image with overlay title
            ZStack(alignment: .bottomLeading) {
                if let thumbnailUrl = pattern.thumbnailUrl,
                   let imageURL = URL(string: thumbnailUrl) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            placeholderImage
                        default:
                            placeholderImage
                                .overlay {
                                    ProgressView()
                                        .tint(Theme.softCoral)
                                }
                        }
                    }
                    .frame(minHeight: elevated ? 150 : 130, maxHeight: elevated ? 180 : 160)
                    .clipped()
                } else {
                    placeholderImage
                }

                // Gradient overlay for text legibility
                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Title overlaid on image
                VStack(alignment: .leading, spacing: 3) {
                    // Badges row
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

                    Text(pattern.title)
                        .font(.system(size: elevated ? 15 : 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .padding(Theme.Spacing.md)
            }

            // Status strip — thin colored bar at bottom
            Theme.statusColor(for: pattern.status)
                .frame(height: 3)
        }
        .cardStyle(elevated: elevated)
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
        .frame(minHeight: elevated ? 150 : 130, maxHeight: elevated ? 180 : 160)
    }
}
