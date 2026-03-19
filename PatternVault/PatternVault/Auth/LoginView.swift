//
//  LoginView.swift
//  PatternVault
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @Binding var isPresented: Bool

    @State private var email = ""
    @State private var password = ""
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
                    Text("Pattern Vault")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Your personal craft library")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
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
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
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
        .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
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
            Task {
                await auth.signInWithApple(idToken: idToken, fullName: name)
            }
        case .failure(let error):
            let nsError = error as NSError
            #if DEBUG
            print("[AppleSignIn] Error: domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)")
            #endif
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                auth.errorMessage = "Apple sign-in failed. Make sure you're signed into iCloud and try again."
            }
        }
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
