//
//  PatternRowView.swift
//  PatternVault
//

import SwiftUI

struct PatternRowView: View {
    let pattern: Pattern

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnailUrl = pattern.thumbnailUrl, let imageURL = URL(string: thumbnailUrl) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderIcon
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            } else {
                placeholderIcon
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(pattern.title)
                    .font(Theme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let platform = pattern.sourcePlatform {
                        Text(platform)
                            .font(Theme.Typography.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.chipFill)
                            .clipShape(Capsule())
                    }
                    Text(pattern.status.displayName)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.statusColor(for: pattern.status))
                }
            }
            Spacer()
            Image(systemName: Theme.statusIcon(for: pattern.status))
                .foregroundStyle(Theme.statusColor(for: pattern.status))
        }
        .padding(.vertical, 4)
    }

    private var placeholderIcon: some View {
        Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(Theme.deepPlum.opacity(0.3))
            .frame(width: 44, height: 44)
            .background(Theme.warmCream)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }
}
