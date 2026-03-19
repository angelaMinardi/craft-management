//
//  NoteRowView.swift
//  PatternVault
//

import SwiftUI

struct NoteRowView: View {
    let note: ProjectNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Theme.noteTypeIcon(for: note.noteType))
                .foregroundStyle(Theme.noteTypeColor(for: note.noteType))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(note.noteType.displayName)
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.noteTypeColor(for: note.noteType))

                Text(note.content)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)

                Text(note.createdAt, style: .relative)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }

            Spacer()

            if note.photoUrl != nil {
                Image(systemName: "photo")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.noteType.displayName): \(note.content)")
        .accessibilityHint("Opens note details")
    }
}
