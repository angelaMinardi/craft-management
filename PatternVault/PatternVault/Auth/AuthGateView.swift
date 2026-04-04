//
//  AuthGateView.swift
//  PatternVault
//

import SwiftUI

struct AuthGateView: View {
    @State private var showingSignUp = false
    var titleOverride: String? = nil
    var subtitleOverride: String? = nil

    var body: some View {
        NavigationStack {
            if showingSignUp {
                SignUpView(
                    isPresented: $showingSignUp,
                    titleOverride: titleOverride ?? "Create account",
                    subtitleOverride: subtitleOverride
                )
            } else {
                LoginView(
                    isPresented: $showingSignUp,
                    titleOverride: titleOverride,
                    subtitleOverride: subtitleOverride
                )
            }
        }
    }
}
