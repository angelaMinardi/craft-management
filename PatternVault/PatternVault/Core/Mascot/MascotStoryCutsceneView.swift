//
//  MascotStoryCutsceneView.swift
//  PatternVault
//

import SwiftUI

struct MascotStoryCutsceneView: View {
    let chapter: MascotStoryChapter
    let mascotName: String
    var onDone: () -> Void

    private var localizedLines: [String] {
        chapter.lines.map { $0.replacingOccurrences(of: "[Name]", with: mascotName) }
    }

    private var localizedHook: String {
        chapter.hook.replacingOccurrences(of: "[Name]", with: mascotName)
    }

    @ViewBuilder
    private var chapterMascot: some View {
        switch chapter.trigger {
        case .saved10, .saved25, .seasonal:
            SpriteMascotView.thinking(size: 120)
        default:
            SpriteMascotView.knitting(size: 120)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                chapterMascot
                Text(chapter.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(localizedLines, id: \.self) { line in
                        Text(line)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.82))
                    }
                    Text("Hook: \(localizedHook)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.softCoral)
                        .padding(.top, Theme.Spacing.xs)
                }
                .padding()
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.softCoral)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Story Unlocked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onDone()
                    }
                }
            }
        }
    }
}

