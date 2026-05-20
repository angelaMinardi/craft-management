//
//  LoginView.swift
//  PatternVault
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @Binding var isPresented: Bool
    var titleOverride: String? = nil
    var subtitleOverride: String? = nil

    @State private var email = ""
    @State private var password = ""
    @State private var showPasswordReset = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    private var emailTouched: Bool { !email.isEmpty }
    private var emailValid: Bool { isValidEmail(email) }
    private var formValid: Bool { emailValid && !password.isEmpty }

    var body: some View {
        // Vertically center the sign-in form on iPad. Using ScrollView keeps the
        // form usable when the software keyboard expands; the inner Spacers push
        // content to the vertical center when it fits inside the viewport.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: Theme.Spacing.xl) {
                        SpriteMascotView.idle(size: 80)

                        VStack(spacing: Theme.Spacing.sm) {
                            Text(titleOverride ?? "Corvid Craft")
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
                            HStack {
                                Text("Password")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                                Spacer()
                                Button("Forgot password?") {
                                    auth.clearError()
                                    showPasswordReset = true
                                }
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.softCoral)
                                .accessibilityLabel("Forgot password")
                                .accessibilityHint("Send a password reset email")
                            }
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
                            request.nonce = auth.prepareAppleSignInNonceHash()
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
                    .frame(maxWidth: 520)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetSheet(prefillEmail: email)
                .environmentObject(auth)
        }
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
                // Nonce is read from AuthService.pendingAppleSignInNonce — see
                // prepareAppleSignInNonceHash() called from the request closure.
                await auth.signInWithApple(idToken: idToken, fullName: name)
            }
        case .failure(let error):
            let nsError = error as NSError
            #if DEBUG
            print("[AppleSignIn] Error: domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)")
            #endif
            auth.errorMessage = "Apple sign-in failed (\(nsError.code)): \(error.localizedDescription)"
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

// MARK: - Forgot password sheet

private struct PasswordResetSheet: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    var prefillEmail: String = ""

    @State private var email = ""
    @State private var didSubmit = false

    private var emailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.sm) {
                    SpriteMascotView.idle(size: 80)
                    Text("Reset your password")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Enter your email and we'll send a reset link.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.xl)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Email")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(Theme.warmCream)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        .disabled(didSubmit)
                }
                .padding(.horizontal, Theme.Spacing.xl)

                if let info = auth.passwordResetInfoMessage {
                    Text(info)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.sageGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                }

                Button {
                    if didSubmit {
                        auth.passwordResetInfoMessage = nil
                        dismiss()
                    } else {
                        didSubmit = true
                        Task { await auth.requestPasswordReset(email: email) }
                    }
                } label: {
                    HStack {
                        if auth.isRequestingPasswordReset { ProgressView().tint(.white) }
                        Text(didSubmit && !auth.isRequestingPasswordReset ? "Done" : "Send reset link")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled((!didSubmit && !emailValid) || auth.isRequestingPasswordReset)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.md)

                Spacer()
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        auth.passwordResetInfoMessage = nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                email = prefillEmail
                auth.passwordResetInfoMessage = nil
            }
        }
        .interactiveDismissDisabled(auth.isRequestingPasswordReset)
    }
}
