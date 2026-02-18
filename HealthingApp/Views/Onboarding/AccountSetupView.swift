//
//  AccountSetupView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import SpeziOnboarding
import SpeziAccount
import AuthenticationServices

struct AccountSetupView: View {
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var accountCreated = false

    var body: some View {
        OnboardingView(
            title: "Create Your Account",
            subtitle: "Secure your health data with Sign in with Apple"
        ) {
            VStack(spacing: 32) {
                // Benefits section
                VStack(alignment: .leading, spacing: 16) {
                    AccountBenefitRow(
                        icon: "shield.checkered",
                        title: "Enhanced Security",
                        description: "Two-factor authentication and device-level security"
                    )

                    AccountBenefitRow(
                        icon: "icloud.fill",
                        title: "Backup & Sync",
                        description: "Safely backup your app preferences and device settings"
                    )

                    AccountBenefitRow(
                        icon: "person.circle.fill",
                        title: "Personalized Experience",
                        description: "Customize the app to match your health goals"
                    )

                    AccountBenefitRow(
                        icon: "lock.fill",
                        title: "Privacy Protection",
                        description: "Your email remains private with Apple's privacy features"
                    )
                }

                Spacer()

                // Sign in section
                VStack(spacing: 16) {
                    if accountCreated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Account created successfully!")
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let error = signInError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        configureSignInRequest(request)
                    } onCompletion: { result in
                        handleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isSigningIn || accountCreated)

                    Button("Skip for Now") {
                        // Continue without account creation
                        completeOnboarding()
                    }
                    .foregroundColor(.secondary)
                    .disabled(isSigningIn)

                    if accountCreated {
                        OnboardingActionsView(
                            primaryText: "Get Started",
                            primaryAction: {
                                completeOnboarding()
                            }
                        )
                    }
                }

                // Privacy note
                VStack(spacing: 8) {
                    Text("Privacy Notice")
                        .fontWeight(.semibold)
                        .font(.caption)

                    Text("Creating an account only enables app features and preferences backup. Your health data always stays encrypted on your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
            }
            .padding()
        }
    }

    private func configureSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]

        // Generate a nonce for security
        let nonce = generateNonce()
        request.nonce = sha256(nonce)
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        isSigningIn = true
        signInError = nil

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Failed to get Apple ID credential"
                isSigningIn = false
                return
            }

            // Process the credential
            processAppleIDCredential(appleIDCredential)

        case .failure(let error):
            handleSignInError(error)
        }
    }

    private func processAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) {
        // Extract user information
        let userID = credential.user
        let email = credential.email ?? "private@privaterelay.appleid.com"
        let firstName = credential.fullName?.givenName ?? ""
        let lastName = credential.fullName?.familyName ?? ""

        // Create user profile
        let userProfile = UserProfile(
            id: userID,
            email: email,
            firstName: firstName,
            lastName: lastName,
            createdAt: Date()
        )

        // Save to secure storage
        Task {
            do {
                try await saveUserProfile(userProfile)
                await MainActor.run {
                    self.accountCreated = true
                    self.isSigningIn = false
                }
            } catch {
                await MainActor.run {
                    self.signInError = "Failed to create account: \(error.localizedDescription)"
                    self.isSigningIn = false
                }
            }
        }
    }

    private func handleSignInError(_ error: Error) {
        isSigningIn = false

        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                signInError = nil // User canceled, don't show error
            case .failed:
                signInError = "Sign in failed. Please try again."
            case .invalidResponse:
                signInError = "Invalid response from Apple. Please try again."
            case .notHandled:
                signInError = "Sign in not handled. Please try again."
            case .unknown:
                signInError = "Unknown error occurred. Please try again."
            @unknown default:
                signInError = "An error occurred. Please try again."
            }
        } else {
            signInError = error.localizedDescription
        }
    }

    private func saveUserProfile(_ profile: UserProfile) async throws {
        // Save encrypted user profile
        let encryptedProfile = try SecurityManager.shared.encryptHealthData(profile)

        // Store in keychain
        let profileData = try JSONEncoder().encode(encryptedProfile)
        try KeychainService.shared.store(
            data: profileData,
            service: "com.healthing.app.userprofile",
            account: profile.id
        )

        // Update app state
        UserDefaults.standard.set(profile.id, forKey: "current_user_id")
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        // Trigger app state change to show main interface
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }

    // MARK: - Utility Functions

    private func generateNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        return inputData.sha256Hash
    }
}

struct AccountBenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)

                Text(description)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Supporting Types

struct UserProfile: Codable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let createdAt: Date
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

extension Data {
    var sha256Hash: String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    AccountSetupView()
}