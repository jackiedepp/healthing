//
//  PrivacyPolicyView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import SpeziOnboarding

struct PrivacyPolicyView: View {
    @State private var hasAgreed = false

    var body: some View {
        OnboardingView(
            title: "Your Privacy Matters",
            subtitle: "Understanding how we protect your health data"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                PrivacySection(
                    icon: "lock.shield.fill",
                    title: "Local Data Processing",
                    description: "All your sensitive health data is processed locally on your device using advanced encryption."
                )

                PrivacySection(
                    icon: "icloud.fill",
                    title: "Optional Cloud Sync",
                    description: "Only non-sensitive metadata can be synced to iCloud for backup. Full health data stays on your device."
                )

                PrivacySection(
                    icon: "eye.slash.fill",
                    title: "No Data Sharing",
                    description: "We never sell, share, or analyze your personal health information. Your data belongs to you."
                )

                PrivacySection(
                    icon: "key.fill",
                    title: "Encryption Standards",
                    description: "All data is protected with AES-256 encryption and biometric authentication."
                )

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 12) {
                    Text("What we collect:")
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        PrivacyDetailRow(text: "• Health metrics from connected devices (encrypted locally)")
                        PrivacyDetailRow(text: "• Medical documents you choose to upload (encrypted locally)")
                        PrivacyDetailRow(text: "• App usage analytics (anonymous, no health data)")
                        PrivacyDetailRow(text: "• Crash reports to improve app stability (no personal data)")
                    }

                    Text("What we DON'T collect:")
                        .fontWeight(.semibold)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        PrivacyDetailRow(text: "• Your actual health measurements or medical information")
                        PrivacyDetailRow(text: "• Personal identifiers linked to health data")
                        PrivacyDetailRow(text: "• Location data")
                        PrivacyDetailRow(text: "• Contact information beyond what you provide")
                    }
                }

                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    Toggle("I have read and agree to the privacy policy", isOn: $hasAgreed)
                        .toggleStyle(SwitchToggleStyle(tint: .red))

                    HStack(spacing: 16) {
                        Button("View Full Policy") {
                            // Open full privacy policy
                            if let url = URL(string: "https://healthing.app/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(.blue)

                        Spacer()

                        OnboardingActionsView(
                            primaryText: "Continue",
                            primaryAction: {
                                // Continue to next step
                            }
                        )
                        .disabled(!hasAgreed)
                    }
                }
            }
            .padding()
        }
    }
}

struct PrivacySection: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.red)
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

struct PrivacyDetailRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
}

#Preview {
    PrivacyPolicyView()
}