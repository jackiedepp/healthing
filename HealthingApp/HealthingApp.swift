//
//  HealthingApp.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import Spezi

@main
struct HealthingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var dataStore = HealthDataStore.shared
    @StateObject private var localizationManager = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if securityManager.isAppLocked {
                    AuthenticationView()
                        .environmentObject(securityManager)
                        .environmentObject(localizationManager)
                } else {
                    MainTabView()
                        .environmentObject(securityManager)
                        .environmentObject(dataStore)
                        .environmentObject(localizationManager)
                }
            }
            .withLocalization()
            .onAppear {
                // Check authentication status on app launch
                if securityManager.isAuthenticationRequired {
                    securityManager.lockApplication()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // Lock app when going to background
                securityManager.lockApplication()
            }
        }
    }
}