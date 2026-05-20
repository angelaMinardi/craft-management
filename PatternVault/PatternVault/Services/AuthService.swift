//
//  AuthService.swift
//  PatternVault
//

import CryptoKit
import Foundation
import Supabase
import Security
import SwiftUI

/// Shared auth-input rules. Keep in one place so Login/Signup/SetNewPassword agree.
enum AuthValidation {
    static let minPasswordLength = 8
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// Redirect URL for OAuth (Google) and password recovery. Must be added to
    /// Supabase Auth → URL Configuration → Redirect URLs.
    static let oauthRedirectURL = "com.corvidcraft.app://auth/callback"

    @Published private(set) var session: Session?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Set when an incoming recovery URL has been exchanged for a session and the
    /// user should be presented with the "set a new password" screen.
    @Published var isRecoveringPassword = false
    /// True while a password-reset email is in flight, false on completion (success or not).
    @Published private(set) var isRequestingPasswordReset = false
    /// One-shot info message shown after `requestPasswordReset` regardless of outcome
    /// (to avoid leaking which emails are registered).
    @Published var passwordResetInfoMessage: String?

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

    private static let appGroupId = "group.com.corvidcraft.app"
    private static let keychainService = "com.corvidcraft.app.supabase"
    private static let keychainTokenAccount = "supabase_access_token"
    private static let keychainUserIdAccount = "supabase_user_id"
    private static let pendingDeletionKey = "com.corvidcraft.app.pendingAccountDeletion"
    /// App Group queue for Apple `fullName`. Apple returns it ONLY on the first
    /// sign-in per AppleID+app pair, so if the first call fails for any reason
    /// (network blip, Supabase config drift) we'd lose it forever. We persist
    /// before the network round-trip and clear on success.
    private static let pendingAppleFullNameKey = "pendingAppleFullName"
    /// Drop a queued deletion after this much wall-clock time. Past this the refresh
    /// token is almost certainly revoked, so further retries can't authenticate.
    private static let pendingDeletionMaxAge: TimeInterval = 14 * 24 * 60 * 60
    private let client = SupabaseManager.client

    private struct PendingDeletion: Codable {
        let userId: String
        let refreshToken: String
        let createdAt: Date
    }

    private init() {
        session = client.auth.currentSession
        syncSessionToAppGroup()
        Task { await observeSession() }
        Task { await processPendingDeletionIfNeeded() }
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
        let normalizedEmail = Self.normalizedEmail(email)
        do {
            _ = try await client.auth.signUp(email: normalizedEmail, password: password)
            session = client.auth.currentSession
            if session != nil { HapticService.success() }
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Sign up failed.")
        }
    }

    /// Normalize an email before sending to Supabase. Trims whitespace/newlines
    /// (iOS soft keyboards readily insert a trailing space) and lowercases —
    /// Supabase's auth backend rejects untrimmed addresses with
    /// "Unable to validate email address: invalid format", which would surface
    /// to the user three screens after they typed it.
    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let email = Self.normalizedEmail(email)
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            session = client.auth.currentSession
            if session != nil { HapticService.success() }
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Sign in failed.")
        }
    }

    /// Call this when the app is opened via OAuth redirect (Google) or password
    /// recovery. The Supabase SDK exchanges the URL for a session; for recovery
    /// links the resulting session is valid but we flip `isRecoveringPassword`
    /// so the UI can route to the "set a new password" screen.
    func session(from url: URL) async {
        guard url.absoluteString.hasPrefix(Self.oauthRedirectURL) else { return }
        let isRecovery: Bool = {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
            if components.queryItems?.contains(where: { $0.name == "type" && $0.value == "recovery" }) == true { return true }
            // Supabase often returns the type in the URL fragment (e.g. "...#type=recovery&access_token=...").
            if let fragment = components.fragment, fragment.contains("type=recovery") { return true }
            return false
        }()
        do {
            let newSession = try await client.auth.session(from: url)
            self.session = newSession
            HapticService.success()
            if isRecovery { isRecoveringPassword = true }
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Sign in failed.")
        }
    }

    /// Send a password-reset email via Supabase. The reply is intentionally
    /// non-specific (success message regardless of whether the email exists) so
    /// the UI can't be used to enumerate registered addresses.
    func requestPasswordReset(email: String) async {
        isRequestingPasswordReset = true
        errorMessage = nil
        defer { isRequestingPasswordReset = false }
        let normalized = Self.normalizedEmail(email)
        guard let redirect = URL(string: "\(Self.oauthRedirectURL)?type=recovery") else {
            passwordResetInfoMessage = "If an account exists for that email, a reset link is on its way."
            return
        }
        do {
            try await client.auth.resetPasswordForEmail(normalized, redirectTo: redirect)
        } catch {
            #if DEBUG
            NSLog("[AuthService] requestPasswordReset failed: %@", error.localizedDescription)
            #endif
            // Intentionally do not surface specific errors to prevent user enumeration.
        }
        passwordResetInfoMessage = "If an account exists for that email, a reset link is on its way."
    }

    /// Update the signed-in user's password (used by the recovery flow).
    func updatePassword(to newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard newPassword.count >= AuthValidation.minPasswordLength else {
            errorMessage = "Password must be at least \(AuthValidation.minPasswordLength) characters."
            return false
        }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
            isRecoveringPassword = false
            HapticService.success()
            return true
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Could not update password.")
            return false
        }
    }

    /// Raw nonce captured when the caller initiated an Apple sign-in request.
    /// Lives on this MainActor singleton so it survives any view recreation
    /// SwiftUI may do while Apple's system sheet is up — `@State`-owned nonces
    /// were resetting to nil on iPad mid-flow, producing "Nonces mismatch" at
    /// the Supabase verification step. The view layer now never holds it.
    private var pendingAppleSignInNonce: String?

    /// Generates a fresh raw nonce, stores it on the service, and returns the
    /// SHA-256 hash to attach to the `ASAuthorizationAppleIDRequest.nonce`.
    /// Call this from the SignInWithAppleButton request closure.
    func prepareAppleSignInNonceHash() -> String {
        let raw = Self.randomNonceString()
        pendingAppleSignInNonce = raw
        return Self.sha256(raw)
    }

    /// Sign in with Apple (native). Pass the identity token; the raw nonce stored
    /// by `prepareAppleSignInNonceHash()` is used automatically. `fullName` is
    /// only present on the first sign-in per AppleID+app pair; we queue it to
    /// the App Group before the network call so a transient failure can't lose it.
    func signInWithApple(
        idToken: String,
        fullName: (given: String?, family: String?)? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let effectiveNonce = pendingAppleSignInNonce
        pendingAppleSignInNonce = nil

        // Queue the name BEFORE attempting auth. If auth fails, the pending entry
        // stays and the next successful sign-in writes it to user metadata.
        if let fullName, !(fullName.given ?? "").isEmpty || !(fullName.family ?? "").isEmpty {
            queuePendingAppleFullName(given: fullName.given, family: fullName.family)
        }

        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: effectiveNonce)
            )
            session = client.auth.currentSession
            if session != nil { HapticService.success() }
            await flushPendingAppleFullName()
        } catch {
            errorMessage = Self.sanitizedAuthError(error, fallback: "Apple sign-in failed.")
        }
    }

    private func queuePendingAppleFullName(given: String?, family: String?) {
        let payload: [String: String] = [
            "given": given ?? "",
            "family": family ?? ""
        ]
        UserDefaults(suiteName: Self.appGroupId)?.set(payload, forKey: Self.pendingAppleFullNameKey)
    }

    /// If a name is queued and we now have a session, write it to user metadata
    /// and clear the queue. Failure is non-fatal — the name stays queued.
    private func flushPendingAppleFullName() async {
        guard session != nil else { return }
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        guard let payload = defaults?.dictionary(forKey: Self.pendingAppleFullNameKey) as? [String: String] else { return }
        let given = payload["given"] ?? ""
        let family = payload["family"] ?? ""
        guard !given.isEmpty || !family.isEmpty else {
            defaults?.removeObject(forKey: Self.pendingAppleFullNameKey)
            return
        }
        let fullNameString = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        do {
            _ = try await client.auth.update(
                user: UserAttributes(
                    data: [
                        "full_name": .string(fullNameString),
                        "given_name": .string(given),
                        "family_name": .string(family)
                    ]
                )
            )
            defaults?.removeObject(forKey: Self.pendingAppleFullNameKey)
        } catch {
            #if DEBUG
            NSLog("[AuthService] flushPendingAppleFullName failed: %@", error.localizedDescription)
            #endif
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

    /// Delete the user's account. The user-facing flow MUST NOT fail visibly:
    /// once a user taps Delete Account we always sign them out locally and clear
    /// state. If the server-side delete can't reach Supabase right now (offline,
    /// 5xx, function cold-start), we persist a pending-deletion record with the
    /// refresh token and retry on every subsequent launch until it lands.
    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let activeSession = session else {
            errorMessage = "You must be signed in to delete your account."
            return
        }

        // Queue the deletion first so an app crash mid-delete doesn't lose it.
        queuePendingDeletion(
            userId: activeSession.user.id.uuidString,
            refreshToken: activeSession.refreshToken
        )

        // Try server-side delete with backoff; transient 5xx / network blips recover here.
        let succeeded = await attemptServerDeleteWithRetries(accessToken: activeSession.accessToken)

        if succeeded {
            clearPendingDeletion()
        }
        // If !succeeded, the pending record stays. processPendingDeletionIfNeeded()
        // picks it up on the next launch and retries quietly in the background.

        // Always sign out locally regardless of server outcome. The user explicitly
        // asked to delete; they should never remain signed in.
        try? await client.auth.signOut()
        session = nil
    }

    private func attemptServerDeleteWithRetries(accessToken: String) async -> Bool {
        // 3 attempts, exponential backoff. Total worst-case wait ~2.1s.
        let backoffsNs: [UInt64] = [0, 600_000_000, 1_500_000_000]
        for delay in backoffsNs {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            do {
                try await deleteAccountOnServer(accessToken: accessToken)
                return true
            } catch {
                #if DEBUG
                NSLog("[AuthService] deleteAccount attempt failed: %@", error.localizedDescription)
                #endif
            }
        }
        return false
    }

    // MARK: - Pending deletion queue

    private func queuePendingDeletion(userId: String, refreshToken: String) {
        let pending = PendingDeletion(userId: userId, refreshToken: refreshToken, createdAt: Date())
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingDeletionKey)
    }

    private func clearPendingDeletion() {
        UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
    }

    private func loadPendingDeletion() -> PendingDeletion? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingDeletionKey),
              let pending = try? JSONDecoder().decode(PendingDeletion.self, from: data) else {
            return nil
        }
        return pending
    }

    /// Background retry on launch. If the previous deletion failed to reach the
    /// server, refresh the access token via Supabase REST and re-call the
    /// delete-account function. Silent on success and silent on failure — the
    /// user is already signed out at this point.
    private func processPendingDeletionIfNeeded() async {
        guard let pending = loadPendingDeletion() else { return }

        // Drop ancient records — the refresh token has almost certainly expired
        // server-side by now, so further retries can't authenticate.
        if Date().timeIntervalSince(pending.createdAt) > Self.pendingDeletionMaxAge {
            clearPendingDeletion()
            return
        }

        do {
            let freshAccessToken = try await refreshAccessToken(using: pending.refreshToken)
            try await deleteAccountOnServer(accessToken: freshAccessToken)
            clearPendingDeletion()
        } catch {
            #if DEBUG
            NSLog("[AuthService] pending deletion retry failed: %@", error.localizedDescription)
            #endif
            // Keep the record for the next launch.
        }
    }

    /// Direct REST call to /auth/v1/token to swap a refresh token for a fresh
    /// access token. Used by the pending-deletion retry path so we don't touch
    /// the live `client.auth` session (the user is already signed out).
    private func refreshAccessToken(using refreshToken: String) async throws -> String {
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !baseURLString.isEmpty,
              !baseURLString.contains("$("),
              let baseURL = URL(string: baseURLString) else {
            throw NSError(domain: "AuthService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Supabase URL is not configured."])
        }
        guard let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !anonKey.isEmpty,
              !anonKey.contains("$(") else {
            throw NSError(domain: "AuthService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Supabase key is not configured."])
        }

        let endpoint = baseURL
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
            .appendingPathComponent("token")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let finalURL = components?.url else {
            throw NSError(domain: "AuthService", code: -12, userInfo: [NSLocalizedDescriptionKey: "Could not build token refresh URL."])
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "AuthService", code: -13, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed."])
        }
        struct RefreshResponse: Decodable { let access_token: String }
        return try JSONDecoder().decode(RefreshResponse.self, from: data).access_token
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

    // MARK: - Apple Sign-in nonce helpers

    /// Cryptographically random nonce string (`A-Z a-z 0-9 - . _`).
    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess { random = 0 }
                return random
            }
            for r in randoms {
                if remaining == 0 { break }
                if r < charset.count {
                    result.append(charset[Int(r)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Maps auth errors to user-safe messages. Logs details in DEBUG only.
    private static func sanitizedAuthError(_ error: Error, fallback: String) -> String {
        #if DEBUG
        NSLog("[AuthService] %@", error.localizedDescription)
        #endif
        let message = error.localizedDescription.lowercased()
        if message.contains("validate email") || message.contains("invalid format") || message.contains("invalid email") && !message.contains("password") {
            return "That email address doesn't look right. Please check and try again."
        }
        if message.contains("invalid login") || message.contains("wrong password") {
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
