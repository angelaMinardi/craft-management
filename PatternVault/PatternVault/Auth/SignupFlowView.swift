//
//  SignupFlowView.swift
//  PatternVault
//
//  Two-screen signup flow: welcome → email/password (+ Apple/Google).
//  Craft, skill, and notification preferences are collected pre-auth in
//  OnboardingView; this screen is the auth funnel only. Once auth succeeds,
//  RootView transitions the user into MainTabView.
//

import AuthenticationServices
import SwiftUI

struct SignupFlowView: View {
    @EnvironmentObject var auth: AuthService
    @Binding var isPresented: Bool  // true = signup; false = login

    @State private var step: Step = .welcome
    @State private var email = ""
    @State private var password = ""

    enum Step { case welcome, email }

    var body: some View {
        ZStack {
            Theme.warmCream.ignoresSafeArea()
            switch step {
            case .welcome: welcome
            case .email:   emailStep
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - 1. Welcome

    private var welcome: some View {
        ZStack {
            blob(size: 220, color: Theme.softCoral.opacity(0.35), offset: .init(width: 140, height: -110))
            blob(size: 140, color: Theme.sageGreen.opacity(0.30), offset: .init(width: -140, height: -60))
            blob(size: 70, color: Theme.honey.opacity(0.40), offset: .init(width: 110, height: 40))

            VStack(spacing: 0) {
                Spacer(minLength: 30)
                SpriteMascotView.waving(size: 260)
                    .shadow(color: Theme.deepPlum.opacity(0.18), radius: 12, x: 0, y: 12)
                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    (
                        Text("Welcome to\n")
                            .font(.system(size: 44, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.deepPlum)
                        + Text("Corvid Craft")
                            .font(.system(size: 44, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.softCoral)
                    )
                    .multilineTextAlignment(.center)
                    .lineSpacing(-4)

                    Text("A cozy nest for your knitting, crochet, and maker patterns. Track rows, stash supplies, finish makes.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Spacer(minLength: 10).frame(height: 4)

                    Button(action: { step = .email }) {
                        HStack(spacing: 10) {
                            Text("Get started")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .buttonStyle(CoralPillButtonStyle())

                    HStack(spacing: 6) {
                        Text("Already have an account?")
                            .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        Button("Log in") {
                            auth.clearError()
                            isPresented = false
                        }
                        .foregroundStyle(Theme.softCoral)
                        .fontWeight(.heavy)
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - 2. Email

    private var emailStep: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { step = .welcome }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Theme.deepPlum.opacity(0.08), radius: 2, x: 0, y: 1)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.deepPlum)
                    }
                    .frame(width: 36, height: 36)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                (
                    Text("Let's build your ")
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.deepPlum)
                    + Text("nest")
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.softCoral)
                    + Text(".")
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.deepPlum)
                )
                Text("We'll sync your patterns across devices.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            VStack(spacing: 20) {
                LabeledField(label: "EMAIL", placeholder: "you@birdsong.co", text: $email, isSecure: false, keyboard: .emailAddress)
                LabeledField(label: "PASSWORD", placeholder: "\(AuthValidation.minPasswordLength)+ characters", text: $password, isSecure: true)

                HStack(spacing: 14) {
                    dividerLine
                    Text("or continue with")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    dividerLine
                }

                HStack(spacing: 10) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = auth.prepareAppleSignInNonceHash()
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 26))

                    Button(action: { Task { await auth.signInWithGoogle() } }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.honey)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text("G")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                )
                            Text("Google")
                        }
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.deepPlum.opacity(0.12), lineWidth: 1.5))
                        )
                    }
                }

                if let msg = auth.errorMessage {
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.softCoral)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)

            Spacer(minLength: 0)

            Button(action: createAccount) {
                HStack(spacing: 8) {
                    if auth.isLoading { ProgressView().tint(.white) }
                    Text("Create account")
                }
            }
            .buttonStyle(CoralPillButtonStyle(enabled: emailValid && passwordValid && !auth.isLoading))
            .disabled(!(emailValid && passwordValid) || auth.isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Theme.deepPlum.opacity(0.12))
            .frame(height: 1)
    }

    private var emailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    private var passwordValid: Bool { password.count >= AuthValidation.minPasswordLength }

    private func createAccount() {
        auth.clearError()
        Task {
            await auth.signUp(email: email, password: password)
            // RootView observes auth.isSignedIn and transitions to MainTabView.
        }
    }

    // MARK: - Apple sign-in

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        auth.clearError()
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                auth.errorMessage = "Could not get Apple sign-in token."
                return
            }
            let name: (given: String?, family: String?)? = credential.fullName.map {
                (given: $0.givenName, family: $0.familyName)
            }
            Task { await auth.signInWithApple(idToken: idToken, fullName: name) }
        case .failure(let error):
            let nsError = error as NSError
            auth.errorMessage = "Apple sign-in failed (\(nsError.code))."
        }
    }

    private func blob(size: CGFloat, color: Color, offset: CGSize) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(offset)
    }
}

// MARK: - Shared bits

private struct CoralPillButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(enabled ? .white : Theme.deepPlum.opacity(0.35))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(enabled ? Theme.softCoral : Theme.deepPlum.opacity(0.12))
            )
            .shadow(color: enabled ? Theme.softCoral.opacity(0.45) : .clear,
                    radius: 12, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(.newPassword)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.emailAddress)
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.deepPlum)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.deepPlum.opacity(0.12), lineWidth: 1.5))
            )
        }
    }
}
