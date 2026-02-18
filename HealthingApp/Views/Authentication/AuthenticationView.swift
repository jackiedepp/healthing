//
//  AuthenticationView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import LocalAuthentication

struct AuthenticationView: View {
    @EnvironmentObject private var securityManager: SecurityManager
    @State private var isAuthenticating = false
    @State private var authenticationError: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App logo and title
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)

                Text("app_name".localized)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("app_tagline".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Authentication section
            VStack(spacing: 20) {
                if let error = authenticationError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: authenticateUser) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: securityManager.isBiometricEnabled ? "faceid" : "lock")
                        }

                        Text(securityManager.isBiometricEnabled ? "unlock_with_faceid".localized : "unlock_with_passcode".localized)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 32)
            }

            Spacer()

            // Privacy notice
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "shield.fill")
                        .foregroundColor(.green)
                    Text("privacy_protected".localized)
                        .fontWeight(.medium)
                }

                Text("privacy_notice".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 32)
        }
        .padding()
        .background(Color(.systemBackground))
        .onAppear {
            // Automatically attempt authentication if biometrics are enabled
            if securityManager.isBiometricEnabled {
                authenticateUser()
            }
        }
    }

    private func authenticateUser() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        authenticationError = nil

        Task {
            do {
                let success = try await securityManager.authenticateUser()
                await MainActor.run {
                    isAuthenticating = false
                    if !success {
                        authenticationError = "authentication_failed".localized
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authenticationError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(SecurityManager.shared)
}