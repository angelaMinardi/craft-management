//
//  AuthService.swift
//  PatternVault
//

import Foundation
import Supabase
import SwiftUI

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// Redirect URL for OAuth (Google). Must be added to Supabase Auth → URL Configuration → Redirect URLs.
    static let oauthRedirectURL = "com.patternvault.app://auth/callback"

    @Published private(set) var session: Session?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    var isSignedIn: Bool { session != nil }
    var currentUserId: UUID? { session?.user.id }

    private static let appGroupId = "group.com.patternvault.app"
    private let client = SupabaseManager.client

    private init() {
        session = client.auth.currentSession
        syncSessionToAppGroup()
        Task { await observeSession() }
    }

    func observeSession() async {
        for await (_, session) in client.auth.authStateChanges {
            self.session = session
            syncSessionToAppGroup()
        }
    }

    /// Writes current session credentials and Supabase config to App Group so the share extension can authenticate.
    private func syncSessionToAppGroup() {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        // Share Supabase config so extension can make REST calls
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String {
            defaults?.set(url, forKey: "supabase_url")
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String {
            defaults?.set(key, forKey: "supabase_anon_key")
        }
        if let session {
            defaults?.set(session.accessToken, forKey: "supabase_access_token")
            defaults?.set(session.user.id.uuidString, forKey: "supabase_user_id")
        } else {
            defaults?.removeObject(forKey: "supabase_access_token")
            defaults?.removeObject(forKey: "supabase_user_id")
        }
        defaults?.synchronize()
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            session = client.auth.currentSession
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            session = client.auth.currentSession
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call this when the app is opened via OAuth redirect (e.g. Google). Pass the callback URL.
    func session(from url: URL) async {
        guard url.absoluteString.hasPrefix(Self.oauthRedirectURL) else { return }
        do {
            let newSession = try await client.auth.session(from: url)
            self.session = newSession
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sign in with Apple (native). Pass the identity token and optionally the user's name from the credential.
    func signInWithApple(idToken: String, fullName: (given: String?, family: String?)? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )
            session = client.auth.currentSession
            if let fullName, let given = fullName.given ?? fullName.family, !given.isEmpty {
                let nameParts = [fullName.given, fullName.family].compactMap { $0 }
                let fullNameString = nameParts.joined(separator: " ")
                _ = try? await client.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name": .string(fullNameString),
                            "given_name": .string(fullName.given ?? ""),
                            "family_name": .string(fullName.family ?? "")
                        ]
                    )
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts Google OAuth via Supabase. The SDK opens a browser; session updates via authStateChanges.
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let redirectURL = URL(string: Self.oauthRedirectURL) else {
            errorMessage = "Invalid redirect URL"
            return
        }
        do {
            _ = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: redirectURL
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.signOut()
            session = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.signOut()
            session = nil
            // Supabase does not expose user delete from client by default; use Edge Function or dashboard
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
