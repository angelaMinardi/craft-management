//
//  AIInfoView.swift
//  PatternVault
//

import SwiftUI

struct AIInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    infoRow(
                        icon: "doc.text.magnifyingglass",
                        iconColor: Theme.sageGreen,
                        title: "Pattern parsing — not pattern generating",
                        body: "Corvid Craft uses AI to read and structure patterns you've already saved. It extracts steps, rows, and chart positions from your PDFs and web pages. It never writes new pattern instructions."
                    )
                    infoRow(
                        icon: "lock.fill",
                        iconColor: Theme.dustyBlue,
                        title: "Your patterns stay yours",
                        body: "Pattern content is sent to Google Gemini only when you trigger analysis (import or the wand button). Nothing is shared with other users. Gemini's API is bound by Google's standard data processing terms."
                    )
                    infoRow(
                        icon: "switch.2",
                        iconColor: Theme.honey,
                        title: "You control when AI runs",
                        body: "AI analysis runs automatically when you save a pattern from the share extension. Inside the app, tap the wand button on any pattern to run it on demand. You can use patterns perfectly well without ever running AI analysis."
                    )
                    infoRow(
                        icon: "person.fill.checkmark",
                        iconColor: Theme.softCoral,
                        title: "Designed to assist crafters, not replace designers",
                        body: "The AI organizes information that already exists in your pattern. It does not generate creative content or design instructions. We built it to save you from manual re-typing — not to produce anything new."
                    )
                } header: {
                    Text("What the AI does")
                        .font(Theme.Typography.footnoteSemibold)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        .textCase(nil)
                }

                Section {
                    infoRow(
                        icon: "wand.and.stars",
                        iconColor: Theme.sageGreen,
                        title: "Step extraction",
                        body: "Turns freeform pattern text into a numbered step list you can tap through while crafting."
                    )
                    infoRow(
                        icon: "grid",
                        iconColor: Theme.dustyBlue,
                        title: "Chart grid detection",
                        body: "Locates chart grids in your PDF pages and calculates grid cell boundaries so the overlay snaps accurately."
                    )
                    infoRow(
                        icon: "tag.fill",
                        iconColor: Theme.honey,
                        title: "Metadata extraction",
                        body: "Pulls gauge, yarn weight, needle size, difficulty, and craft type from pattern text so you don't have to fill those fields by hand."
                    )
                } header: {
                    Text("Specific AI capabilities")
                        .font(Theme.Typography.footnoteSemibold)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        .textCase(nil)
                }

                Section {
                    Text("AI analyses use Google Gemini 2.5 Flash. Pattern content is transmitted over HTTPS and is not stored by Gemini beyond the request. Corvid Craft's privacy policy covers how your data is handled on our end.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .padding(.vertical, 4)
                } header: {
                    Text("Technical note")
                        .font(Theme.Typography.footnoteSemibold)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        .textCase(nil)
                }
            }
            .navigationTitle("How AI Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.bodySemibold)
                    .foregroundStyle(Theme.deepPlum)
                Text(body)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
            }
        }
        .padding(.vertical, 4)
    }
}
