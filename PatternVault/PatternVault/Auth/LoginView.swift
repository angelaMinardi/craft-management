//
//  LoginView.swift
//  PatternVault
//

import AuthenticationServices
import CryptoKit
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @Binding var isPresented: Bool
    var titleOverride: String? = nil
    var subtitleOverride: String? = nil

    @State private var email = ""
    @State private var password = ""
    @State private var currentAppleNonce: String?
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    private var emailTouched: Bool { !email.isEmpty }
    private var emailValid: Bool { isValidEmail(email) }
    private var formValid: Bool { emailValid && !password.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                SpriteMascotView.idle(size: 80)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(titleOverride ?? "Pattern Vault")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.deepPlum)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.85)
                    Text(subtitleOverride ?? "Sign in to save and sync your craft library")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.9)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Email")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .email)
                        .padding(12)
                        .background(Theme.warmCream)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        .accessibilityLabel("Email")
                        .accessibilityHint("Enter your email address")

                    if emailTouched && !emailValid {
                        Text("Enter a valid email address")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.softCoral)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Password")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .padding(12)
                        .background(Theme.warmCream)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        .accessibilityLabel("Password")
                        .accessibilityHint("Enter your password")
                }

                if let msg = auth.errorMessage {
                    VStack(spacing: Theme.Spacing.sm) {
                        SpriteMascotView.pouty(size: 64)
                        Text(msg)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.softCoral)
                            .multilineTextAlignment(.center)
                    }
                }

                Button(action: signIn) {
                    HStack {
                        if auth.isLoading { ProgressView().tint(.white) }
                        Text("Sign In")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(auth.isLoading || !formValid)
                .accessibilityLabel("Sign In")
                .accessibilityHint("Sign in with your email and password")

                SignInWithAppleButton(.signIn) { request in
                    focusedField = nil
                    request.requestedScopes = [.fullName, .email]
                    let nonce = randomNonceString()
                    currentAppleNonce = nonce
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.pill))

                Button(action: signInWithGoogle) {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.deepPlum)
                    .cardStyle()
                }
                .disabled(auth.isLoading)
                .accessibilityLabel("Sign in with Google")
                .accessibilityHint("Sign in using your Google account")

                Button("Create an account") {
                    auth.clearError()
                    isPresented = true
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.softCoral)
                .accessibilityLabel("Create an account")
                .accessibilityHint("Open sign up screen")
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.screenGradient.ignoresSafeArea())
    }

    private func signIn() {
        auth.clearError()
        Task {
            await auth.signIn(email: email, password: password)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        auth.clearError()
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                #if DEBUG
                print("[AppleSignIn] Failed to extract identity token from credential")
                #endif
                auth.errorMessage = "Could not get Apple sign-in token."
                return
            }
            let name: (given: String?, family: String?)? = credential.fullName.map { (given: $0.givenName, family: $0.familyName) }
            let nonce = currentAppleNonce
            currentAppleNonce = nil
            Task {
                await auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: name)
            }
        case .failure(let error):
            let nsError = error as NSError
            #if DEBUG
            print("[AppleSignIn] Error: domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)")
            #endif
            auth.errorMessage = "Apple sign-in failed (\(nsError.code)): \(error.localizedDescription)"
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess { random = 0 }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    private func signInWithGoogle() {
        auth.clearError()
        Task {
            await auth.signInWithGoogle()
        }
    }
}
