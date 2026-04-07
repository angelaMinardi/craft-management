//
//  MascotHelpView.swift
//  PatternVault
//

import SwiftUI

struct MascotHelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Mascot Dashboard Guide") {
                    guideRow(title: "Store", detail: "Opens the mascot store where you buy treats using Thread Points.")
                    guideRow(title: "Flame", detail: "Your daily interaction streak. Keep checking in to build it.")
                    guideRow(title: "Hearts", detail: "Bond level with your mascot. Petting and feeding increase hearts.")
                    guideRow(title: "Treat Icons", detail: "Your inventory. Drag a treat onto the mascot to feed it.")
                }
            }
            .navigationTitle("Mascot Help")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func guideRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.65))
        }
        .padding(.vertical, 4)
    }
}

