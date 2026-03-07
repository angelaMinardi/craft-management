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
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Password")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    SecureField("Password (min 6 characters)", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .padding(12)
                        .background(Theme.warmCream)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
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
                .disabled(auth.isLoading || email.isEmpty || password.count < 6)

                Button("Already have an account? Sign in") {
                    auth.clearError()
                    isPresented = false
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.softCoral)
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.cardBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    auth.clearError()
                    isPresented = false
                }
            }
        }
        .onTapGesture { focusedField = nil }
    }

    private func signUp() {
        auth.clearError()
        Task {
            await auth.signUp(email: email, password: password)
        }
    }
}
