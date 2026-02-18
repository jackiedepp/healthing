//
//  AppDelegate.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import UIKit
import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziHealthKit
import SpeziOnboarding
import FirebaseCore
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()

        // Initialize Phase 2A Core Services
        initializeCoreServices()

        // Configure Spezi modules
        let speziConfiguration = SpeziAppDelegate()
        speziConfiguration.configure {
            // Account management with Sign in with Apple
            AccountConfiguration(
                service: FirebaseAccountService(
                    providers: [
                        SignInWithAppleAccountService()
                    ]
                )
            )

            // HealthKit integration for Apple Health data
            HealthKit {
                CollectSample(HKQuantityType.quantityType(forIdentifier: .heartRate)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .stepCount)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .bodyMass)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .height)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!)
                CollectSample(HKQuantityType.quantityType(forIdentifier: .vo2Max)!)
                CollectSample(HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!)
            }

            // Onboarding configuration
            OnboardingDataSource(
                onboardingFlows: [
                    OnboardingFlow(
                        sequence: [
                            WelcomeView(),
                            PrivacyPolicyView(),
                            HealthKitPermissionsView(),
                            AccountSetupView()
                        ]
                    )
                ]
            )
        }

        return speziConfiguration.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Phase 2A Core Services Initialization

    private func initializeCoreServices() {
        print("🚀 AppDelegate: Initializing Phase 2A Core Services...")

        // Initialize SecurityManager (Secure Enclave hardening)
        let _ = SecurityManager.shared

        // Initialize Certificate Pinning Service
        let _ = CertificatePinningService.shared

        // Initialize HealthKit Sync Service
        let _ = HealthKitSyncService.shared

        // Initialize Background Processing Service and register background tasks
        let backgroundService = BackgroundProcessingService.shared

        // Initialize Conflict Resolution Service
        let _ = ConflictResolutionService.shared

        // Initialize GDPR Compliance Manager
        let _ = GDPRComplianceManager.shared

        // Verify Secure Enclave functionality on device startup
        Task {
            do {
                let isSecureEnclaveValid = try await SecurityManager.shared.verifySecureEnclaveKeyIntegrity()
                print("🔐 Secure Enclave integrity check: \(isSecureEnclaveValid ? "PASSED" : "FAILED")")
            } catch {
                print("⚠️ Secure Enclave integrity check failed: \(error)")
            }
        }

        print("✅ Phase 2A Core Services initialized successfully")
    }

    // MARK: - Background Task Handling

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Schedule background tasks when app enters background
        BackgroundProcessingService.shared.scheduleBackgroundTasks()

        // Lock the application for security
        SecurityManager.shared.lockApplication()

        print("📱 App entered background - security locked and background tasks scheduled")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // App will enter foreground - prepare for authentication
        print("📱 App entering foreground - authentication required")
    }
}