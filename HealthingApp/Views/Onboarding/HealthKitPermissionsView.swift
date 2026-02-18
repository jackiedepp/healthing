//
//  HealthKitPermissionsView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import SpeziOnboarding
import HealthKit

struct HealthKitPermissionsView: View {
    @State private var permissionStatus: HealthKitPermissionStatus = .notRequested
    @State private var isRequestingPermissions = false

    private let healthStore = HKHealthStore()

    var body: some View {
        OnboardingView(
            title: "Health Data Access",
            subtitle: "Connect your Apple Health data for comprehensive tracking"
        ) {
            VStack(spacing: 24) {
                // Permission explanation
                VStack(alignment: .leading, spacing: 16) {
                    HealthKitPermissionRow(
                        icon: "heart.fill",
                        title: "Heart Rate & Vitals",
                        description: "Track your heart rate, blood pressure, and other vital signs"
                    )

                    HealthKitPermissionRow(
                        icon: "figure.walk",
                        title: "Activity & Fitness",
                        description: "Monitor steps, workouts, active energy, and exercise minutes"
                    )

                    HealthKitPermissionRow(
                        icon: "bed.double.fill",
                        title: "Sleep Analysis",
                        description: "Analyze your sleep patterns and duration"
                    )

                    HealthKitPermissionRow(
                        icon: "scalemass.fill",
                        title: "Body Measurements",
                        description: "Track weight, height, BMI, and body composition"
                    )

                    HealthKitPermissionRow(
                        icon: "lungs.fill",
                        title: "Respiratory Health",
                        description: "Monitor VO2 max and respiratory rate"
                    )
                }

                Spacer()

                // Status indicator
                StatusIndicator(status: permissionStatus)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: requestHealthKitPermissions) {
                        HStack {
                            if isRequestingPermissions {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "heart.circle.fill")
                            }

                            Text(permissionButtonText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(permissionStatus == .granted ? Color.green : Color.red)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isRequestingPermissions || permissionStatus == .granted)

                    if permissionStatus == .denied {
                        Button("Open Settings") {
                            openAppSettings()
                        }
                        .foregroundColor(.blue)
                    }

                    OnboardingActionsView(
                        primaryText: "Continue",
                        primaryAction: {
                            // Continue to next step
                        }
                    )
                    .disabled(permissionStatus != .granted && permissionStatus != .denied)
                }
            }
            .padding()
        }
        .onAppear {
            checkCurrentPermissionStatus()
        }
    }

    private var permissionButtonText: String {
        switch permissionStatus {
        case .notRequested:
            return "Grant Health Access"
        case .requesting:
            return "Requesting Access..."
        case .granted:
            return "Access Granted"
        case .denied:
            return "Access Denied"
        }
    }

    private func requestHealthKitPermissions() {
        guard !isRequestingPermissions else { return }

        isRequestingPermissions = true
        permissionStatus = .requesting

        let healthDataTypes: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .height)!,
            HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        healthStore.requestAuthorization(toShare: nil, read: healthDataTypes) { success, error in
            DispatchQueue.main.async {
                self.isRequestingPermissions = false

                if success {
                    self.permissionStatus = .granted
                } else {
                    self.permissionStatus = .denied
                }
            }
        }
    }

    private func checkCurrentPermissionStatus() {
        let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let status = healthStore.authorizationStatus(for: sampleType)

        switch status {
        case .notDetermined:
            permissionStatus = .notRequested
        case .sharingDenied:
            permissionStatus = .denied
        case .sharingAuthorized:
            permissionStatus = .granted
        @unknown default:
            permissionStatus = .notRequested
        }
    }

    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

struct HealthKitPermissionRow: View {
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

struct StatusIndicator: View {
    let status: HealthKitPermissionStatus

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)

            Text(statusText)
                .foregroundColor(statusColor)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusIcon: String {
        switch status {
        case .notRequested, .requesting:
            return "clock.fill"
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .notRequested, .requesting:
            return .orange
        case .granted:
            return .green
        case .denied:
            return .red
        }
    }

    private var statusText: String {
        switch status {
        case .notRequested:
            return "Permission Required"
        case .requesting:
            return "Requesting Permission..."
        case .granted:
            return "Access Granted"
        case .denied:
            return "Access Denied"
        }
    }
}

enum HealthKitPermissionStatus {
    case notRequested
    case requesting
    case granted
    case denied
}

#Preview {
    HealthKitPermissionsView()
}