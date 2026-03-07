//
//  AuthGateView.swift
//  PatternVault
//

import SwiftUI

struct AuthGateView: View {
    @State private var showingSignUp = false

    var body: some View {
        NavigationStack {
            if showingSignUp {
                SignUpView(isPresented: $showingSignUp)
            } else {
                LoginView(isPresented: $showingSignUp)
            }
        }
    }
}
