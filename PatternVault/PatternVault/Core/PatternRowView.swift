//
//  PatternRowView.swift
//  PatternVault
//

import SwiftUI

struct PatternRowView: View {
    let pattern: Pattern
    /// When set, images load from local cache first.
    var userId: UUID? = nil
    private var placeholderAssetName: String {
        let options = ["CrowMascot", "CrowExpressions"]
        let seed = pattern.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return options[seed % options.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnailUrl = pattern.thumbnailUrl, let imageURL = URL(string: thumbnailUrl) {
                CachedAsyncImage(url: imageURL, userId: userId) { phase in
                    switch phase {
                    case .loading:
                        ProgressView()
                            .frame(width: 44, height: 44)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                    case .failure:
                        placeholderIcon
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pattern.title), \(pattern.status.displayName)")
        .accessibilityHint("Opens pattern details")
    }

    private var placeholderIcon: some View {
        ZStack {
            Theme.warmCream
            Image(placeholderAssetName)
                .resizable()
                .scaledToFit()
                .padding(6)
                .opacity(0.92)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }
}
