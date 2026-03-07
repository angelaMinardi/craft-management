//
//  SettingsView.swift
//  PatternVault
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject private var junkStore = JunkPhraseStore.shared
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showClearJunkConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    profileCard
                    accountSection
                    contentCleanupSection
                    aboutSection
                    appFooter
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can sign in again anytime.")
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteConfirm) {
                Button("Delete Account", role: .destructive) {
                    Task { await auth.deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete your account and all your data. This cannot be undone.")
            }
            .confirmationDialog("Clear removed phrases", isPresented: $showClearJunkConfirm) {
                Button("Clear All", role: .destructive) {
                    junkStore.clearAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Phrases will no longer be hidden from pattern steps. You can add them again by marking steps as \"Not part of pattern\".")
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Avatar circle with initial or mascot
            ZStack {
                Circle()
                    .fill(Theme.softCoral.opacity(0.12))
                    .frame(width: 64, height: 64)

                if let initial = userInitial {
                    Text(initial)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.softCoral)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.softCoral)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let name = auth.displayName {
                    Text(name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                }

                if let email = auth.userEmail {
                    Text(email)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .borderedCard()
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Account")

            VStack(spacing: 0) {
                // Sign out
                Button { showSignOutConfirm = true } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.softCoral)
                            .frame(width: 22)
                        Text("Sign Out")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign Out")
                .accessibilityHint("Signs out of your account")

                Divider()
                    .overlay(Theme.deepPlum.opacity(0.06))
                    .padding(.leading, 54)

                // Delete account
                Button { showDeleteConfirm = true } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 22)
                        Text("Delete Account")
                            .font(Theme.Typography.body)
                            .foregroundStyle(.red.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete Account")
                .accessibilityHint("Permanently deletes your account and all data")
            }
            .borderedCard()
        }
    }

    // MARK: - Content cleanup (learned junk phrases)

    private var contentCleanupSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Content cleanup")

            VStack(alignment: .leading, spacing: 0) {
                if junkStore.phrases.isEmpty {
                    Text("Phrases you mark as \"Not part of pattern\" on a step will appear here. They’re hidden from future pattern steps.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .padding(Theme.Spacing.lg)
                } else {
                    ForEach(junkStore.phrases, id: \.phrase) { item in
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Text(item.phrase)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Button {
                                junkStore.removePhrase(item.phrase)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.deepPlum.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.lg)
                        if item.phrase != junkStore.phrases.last?.phrase {
                            Divider()
                                .overlay(Theme.deepPlum.opacity(0.06))
                                .padding(.leading, Theme.Spacing.lg)
                        }
                    }
                    Button {
                        showClearJunkConfirm = true
                    } label: {
                        Text("Clear all")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.softCoral)
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .borderedCard()
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "About")

            VStack(spacing: 0) {
                aboutRow(icon: "info.circle", label: "Version", value: appVersion)

                Divider()
                    .overlay(Theme.deepPlum.opacity(0.06))
                    .padding(.leading, 54)

                aboutRow(icon: "hammer.fill", label: "Built with", value: "SwiftUI + Supabase")
            }
            .borderedCard()
        }
    }

    // MARK: - App Footer

    private var appFooter: some View {
        VStack(spacing: Theme.Spacing.md) {
            SpriteMascotView.idle(size: 72)

            Text("Pattern Vault")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.deepPlum.opacity(0.4))

            Text("Your craft companion")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.deepPlum.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func aboutRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.dustyBlue)
                .frame(width: 22)
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
            Spacer()
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.4))
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var userInitial: String? {
        if let name = auth.displayName, let first = name.first {
            return String(first).uppercased()
        }
        if let email = auth.userEmail, let first = email.first {
            return String(first).uppercased()
        }
        return nil
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
