//
//  MascotStoryLogView.swift
//  PatternVault
//

import SwiftUI

struct MascotStoryLogView: View {
    @ObservedObject var storyStore: MascotStoryStore
    let mascotName: String
    var onReplay: (MascotStoryChapter) -> Void

    private var unlockedChapters: [MascotStoryChapter] {
        storyStore.chapters.filter { storyStore.progress.unlockedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if unlockedChapters.isEmpty {
                    Text("No chapters unlocked yet. Keep interacting with \(mascotName) to unlock story scenes.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                } else {
                    ForEach(unlockedChapters) { chapter in
                        Button {
                            onReplay(chapter)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.deepPlum)
                                Text(chapter.hook.replacingOccurrences(of: "[Name]", with: mascotName))
                                    .font(Theme.Typography.caption2)
                                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Story Log")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

