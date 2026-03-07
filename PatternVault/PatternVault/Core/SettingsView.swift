//
//  SettingsView.swift
//  PatternVault
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirm = true
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: Theme.Spacing.sm) {
                            SpriteMascotView.idle(size: 48)
                            Text("Pattern Vault")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmCream)
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can sign in again anytime.")
            }
        }
    }
}
