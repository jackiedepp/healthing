//
//  WelcomeView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import SpeziOnboarding

struct WelcomeView: View {
    var body: some View {
        OnboardingView(
            title: "Welcome to Healthing",
            subtitle: "Your comprehensive health companion",
            areas: [
                OnboardingInformationView.Content(
                    icon: Image(systemName: "heart.circle.fill"),
                    title: "Complete Health Tracking",
                    description: "Track all your health metrics from multiple sources including Apple Watch, Garmin devices, and manual entries."
                ),
                OnboardingInformationView.Content(
                    icon: Image(systemName: "doc.text.fill"),
                    title: "Medical Records Management",
                    description: "Securely store and organize your medical documents, lab results, and healthcare information."
                ),
                OnboardingInformationView.Content(
                    icon: Image(systemName: "brain.head.profile"),
                    title: "AI-Powered Insights",
                    description: "Get personalized health insights and recommendations based on your data, all processed locally on your device."
                ),
                OnboardingInformationView.Content(
                    icon: Image(systemName: "shield.fill"),
                    title: "Privacy First",
                    description: "Your health data is encrypted and stays on your device. We never sell or share your personal information."
                )
            ]
        )
        .foregroundColor(.red)
    }
}

#Preview {
    WelcomeView()
}