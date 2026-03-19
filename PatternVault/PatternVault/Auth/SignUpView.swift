//
//  SignUpView.swift
//  PatternVault
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var auth: AuthService
    @Binding var isPresented: Bool

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    private var emailTouched: Bool { !email.isEmpty }
    private var emailValid: Bool { isValidEmail(email) }
    private var passwordTouched: Bool { !password.isEmpty }
    private var passwordValid: Bool { password.count >= 8 }
    private var formValid: Bool { emailValid && passwordValid }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                Text("Create account")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.deepPlum)

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
                    SecureField("Password (min 8 characters)", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .padding(12)
                        .background(Theme.warmCream)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        .accessibilityLabel("Password")
                        .accessibilityHint("Minimum 8 characters")

                    if passwordTouched && !passwordValid {
                        Text("Password must be at least 8 characters")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.softCoral)
                    }
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

                Button(action: signUp) {
                    HStack {
                        if auth.isLoading { ProgressView().tint(.white) }
                        Text("Sign Up")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(auth.isLoading || !formValid)
                .accessibilityLabel("Sign Up")
                .accessibilityHint("Create your account")

                Button("Already have an account? Sign in") {
                    auth.clearError()
                    isPresented = false
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.softCoral)
                .accessibilityLabel("Already have an account? Sign in")
                .accessibilityHint("Return to sign in screen")
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    auth.clearError()
                    isPresented = false
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    private func signUp() {
        auth.clearError()
        Task {
            await auth.signUp(email: email, password: password)
        }
    }
}
