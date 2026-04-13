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
    var userEmail: String? { session?.user.email }
    var displayName: String? {
        if let meta = session?.user.userMetadata,
           let name = meta["full_name"]?.stringValue,
           !name.isEmpty {
            return name
        }
        return nil
    }

    private static let appGroupId = "group.com.patternvault.app"
    private static let keychainService = "com.patternvault.app.supabase"
    private static let keychainTokenAccount = "supabase_access_token"
    private static let keychainUserIdAccount = "supabase_user_id"
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
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           !url.isEmpty, !url.contains("$("),
           let parsed = URL(string: url),
           let scheme = parsed.scheme?.lowercased(),
           (scheme == "https" || scheme == "http"),
           parsed.host != nil {
            defaults?.set(url.hasSuffix("/") ? String(url.dropLast()) : url, forKey: "supabase_url")
        } else {
            defaults?.removeObject(forKey: "supabase_url")
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
           !key.isEmpty, !key.contains("$(") {
            defaults?.set(key, forKey: "supabase_anon_key")
        }
        if let session {
            Self.saveToSharedKeychain(account: Self.keychainTokenAccount, value: session.accessToken)
            Self.saveToSharedKeychain(account: Self.keychainUserIdAccount, value: session.user.id.uuidString)
        } else {
            Self.deleteFromSharedKeychain(account: Self.keychainTokenAccount)
            Self.deleteFromSharedKeychain(account: Self.keychainUserIdAccount)
        }
        // Clean up legacy UserDefaults token storage
        defaults?.removeObject(forKey: "supabase_access_token")
        defaults?.removeObject(forKey: "supabase_user_id")
        defaults?.synchronize()
    }

    // MARK: - Shared Keychain helpers (access group = App Group for extension sharing)

    private static func saveToSharedKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: appGroupId
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteFromSharedKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: appGroupId
        ]
        SecItemDelete(query as CFDictionary)
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            session = client.auth.currentSession
            if session != nil { HapticService.success() }
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
            if session != nil { HapticService.success() }
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Sign in failed.")
        }
    }

    /// Call this when the app is opened via OAuth redirect (e.g. Google). Pass the callback URL.
    func session(from url: URL) async {
        guard url.absoluteString.hasPrefix(Self.oauthRedirectURL) else { return }
        do {
            let newSession = try await client.auth.session(from: url)
            self.session = newSession
            HapticService.success()
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Sign in failed.")
        }
    }

    /// Sign in with Apple (native). Pass the identity token, request nonce, and optionally the user's name.
    func signInWithApple(
        idToken: String,
        nonce: String? = nil,
        fullName: (given: String?, family: String?)? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            session = client.auth.currentSession
            if session != nil { HapticService.success() }
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
            let message = error.localizedDescription
            if message.isEmpty {
                errorMessage = "Apple sign-in failed."
            } else {
                errorMessage = "Apple sign-in failed: \(message)"
            }
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
            errorMessage = Self.sanitizedAuthError(error, fallback: "Google sign-in failed.")
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
            errorMessage = Self.sanitizedAuthError(error, fallback: "Sign out failed.")
        }
    }

    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let accessToken = session?.accessToken else {
                throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "You must be signed in to delete your account."])
            }
            try await deleteAccountOnServer(accessToken: accessToken)
            try await client.auth.signOut()
            session = nil
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Account deletion failed.")
        }
    }

    private func deleteAccountOnServer(accessToken: String) async throws {
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !baseURLString.isEmpty,
              !baseURLString.contains("$("),
              let baseURL = URL(string: baseURLString) else {
            throw NSError(domain: "AuthService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Supabase URL is not configured."])
        }
        guard let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !anonKey.isEmpty,
              !anonKey.contains("$(") else {
            throw NSError(domain: "AuthService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Supabase key is not configured."])
        }

        let endpoint = baseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("delete-account")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Account deletion failed."])
        }
        guard (200...299).contains(http.statusCode) else {
            #if DEBUG
            let serverMessage = String(data: data, encoding: .utf8) ?? ""
            NSLog("[AuthService] deleteAccount HTTP %d: %@", http.statusCode, serverMessage)
            #endif
            throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Could not delete account. Please try again."])
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Maps auth errors to user-safe messages. Logs details in DEBUG only.
    private static func sanitizedAuthError(_ error: Error, fallback: String) -> String {
        #if DEBUG
        NSLog("[AuthService] %@", error.localizedDescription)
        #endif
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid login") || message.contains("invalid email") || message.contains("wrong password") {
            return "Invalid email or password."
        }
        if message.contains("email not confirmed") {
            return "Please confirm your email address first."
        }
        if message.contains("already registered") || message.contains("already exists") {
            return "An account with this email already exists."
        }
        if message.contains("network") || message.contains("internet") || message.contains("offline") {
            return "Network error. Please check your connection and try again."
        }
        if message.contains("rate limit") || message.contains("too many") {
            return "Too many attempts. Please wait a moment and try again."
        }
        return fallback
    }
}
