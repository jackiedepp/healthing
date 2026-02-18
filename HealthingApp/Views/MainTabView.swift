//
//  MainTabView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var dataStore: HealthDataStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("dashboard".localized)
                }

            HealthDataView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("health_data".localized)
                }

            MedicalRecordsView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text("records".localized)
                }

            DevicesView()
                .tabItem {
                    Image(systemName: "applewatch")
                    Text("devices".localized)
                }

            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("settings".localized)
                }
        }
        .accentColor(.red)
    }
}

#Preview {
    MainTabView()
        .environmentObject(SecurityManager.shared)
        .environmentObject(HealthDataStore.shared)
}