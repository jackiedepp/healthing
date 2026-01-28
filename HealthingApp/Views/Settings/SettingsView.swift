//
//  SettingsView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var dataStore: HealthDataStore
    @StateObject private var retentionManager = RetentionPolicyManager.shared
    @StateObject private var backupManager = BackupPreferencesManager.shared
    @StateObject private var dataIntegrityService = DataIntegrityService.shared
    @StateObject private var auditTrailService = AuditTrailService.shared

    @State private var showingProfileEdit = false
    @State private var showingDataExport = false
    @State private var showingAbout = false
    @State private var showingDataManagement = false
    @State private var showingIntegrityReport = false
    @State private var showingRetentionPolicies = false
    @State private var showingBackupPreferences = false
    @State private var showingAuditTrail = false

    var body: some View {
        NavigationView {
            List {
                // Profile section
                Section {
                    ProfileRow {
                        showingProfileEdit = true
                    }
                }

                // Privacy & Security
                Section("Privacy & Security") {
                    PrivacySettingsRow()
                    SecuritySettingsRow()
                    DataRetentionRow()
                }

                // Data Management & Quality
                Section("Data Management & Quality") {
                    // Data Integrity Status
                    DataIntegrityStatusRow(
                        integrityService: dataIntegrityService
                    ) {
                        showingIntegrityReport = true
                    }

                    // Backup & Sync Preferences
                    BackupPreferencesRow(
                        backupManager: backupManager
                    ) {
                        showingBackupPreferences = true
                    }

                    // Retention Policies
                    RetentionPoliciesRow(
                        retentionManager: retentionManager
                    ) {
                        showingRetentionPolicies = true
                    }

                    // Audit Trail
                    AuditTrailRow(
                        auditService: auditTrailService
                    ) {
                        showingAuditTrail = true
                    }

                    // Data Export (Enhanced)
                    EnhancedDataExportRow {
                        showingDataExport = true
                    }

                    // Manual Data Cleanup
                    ManualCleanupRow(
                        retentionManager: retentionManager
                    )
                }

                // Notifications
                Section("Notifications") {
                    NotificationSettingsRow()
                }

                // App Settings
                Section("App Settings") {
                    AppearanceRow()
                    UnitsRow()
                    LanguageRow()
                }

                // Support & Info
                Section("Support & Information") {
                    HelpSupportRow()
                    AboutRow {
                        showingAbout = true
                    }
                    FeedbackRow()
                }

                // Account Actions
                Section {
                    SignOutRow()
                    DeleteAccountRow()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingProfileEdit) {
                ProfileEditView()
            }
            .sheet(isPresented: $showingDataExport) {
                DataExportView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingIntegrityReport) {
                DataIntegrityReportView(integrityService: dataIntegrityService)
            }
            .sheet(isPresented: $showingRetentionPolicies) {
                RetentionPoliciesView(retentionManager: retentionManager)
            }
            .sheet(isPresented: $showingBackupPreferences) {
                BackupPreferencesView(backupManager: backupManager)
            }
            .sheet(isPresented: $showingAuditTrail) {
                AuditTrailView(auditService: auditTrailService)
            }
        }
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let editAction: () -> Void

    var body: some View {
        HStack {
            // Profile image placeholder
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 60, height: 60)
                .overlay {
                    Text("JD")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("John Doe")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("john.doe@example.com")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Member since January 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Edit") {
                editAction()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Settings Rows

struct PrivacySettingsRow: View {
    @State private var dataMinimization = true
    @State private var shareAnalytics = false

    var body: some View {
        NavigationLink(destination: PrivacySettingsDetailView()) {
            SettingRowContent(
                icon: "shield.fill",
                iconColor: .green,
                title: "Privacy Settings",
                subtitle: "Control what data is collected and how it's used"
            )
        }
    }
}

struct SecuritySettingsRow: View {
    var body: some View {
        NavigationLink(destination: SecuritySettingsDetailView()) {
            SettingRowContent(
                icon: "lock.fill",
                iconColor: .blue,
                title: "Security Settings",
                subtitle: "Biometric authentication and app lock"
            )
        }
    }
}

struct DataRetentionRow: View {
    var body: some View {
        NavigationLink(destination: DataRetentionView()) {
            SettingRowContent(
                icon: "timer",
                iconColor: .orange,
                title: "Data Retention",
                subtitle: "Manage how long data is stored"
            )
        }
    }
}

struct CloudSyncRow: View {
    @EnvironmentObject private var dataStore: HealthDataStore

    var body: some View {
        HStack {
            SettingRowContent(
                icon: "icloud.fill",
                iconColor: .blue,
                title: "iCloud Sync",
                subtitle: dataStore.cloudKitSyncStatus.displayText
            )

            Spacer()

            Toggle("", isOn: .constant(dataStore.isCloudKitEnabled))
                .disabled(true) // Read-only based on CloudKit availability
        }
    }
}

struct DataExportRow: View {
    let exportAction: () -> Void

    var body: some View {
        Button(action: exportAction) {
            SettingRowContent(
                icon: "square.and.arrow.up.fill",
                iconColor: .green,
                title: "Export Data",
                subtitle: "Download your health data"
            )
        }
        .foregroundColor(.primary)
    }
}

struct DataCleanupRow: View {
    var body: some View {
        NavigationLink(destination: DataCleanupView()) {
            SettingRowContent(
                icon: "trash.fill",
                iconColor: .red,
                title: "Data Cleanup",
                subtitle: "Remove old or unnecessary data"
            )
        }
    }
}

struct NotificationSettingsRow: View {
    var body: some View {
        NavigationLink(destination: NotificationSettingsView()) {
            SettingRowContent(
                icon: "bell.fill",
                iconColor: .purple,
                title: "Notifications",
                subtitle: "Health reminders and insights"
            )
        }
    }
}

struct AppearanceRow: View {
    @State private var colorScheme: ColorSchemePreference = .system

    var body: some View {
        HStack {
            SettingRowContent(
                icon: "paintbrush.fill",
                iconColor: .purple,
                title: "Appearance",
                subtitle: colorScheme.displayName
            )

            Spacer()

            Picker("Appearance", selection: $colorScheme) {
                ForEach(ColorSchemePreference.allCases, id: \.self) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            }
            .pickerStyle(MenuPickerStyle())
        }
    }
}

struct UnitsRow: View {
    var body: some View {
        NavigationLink(destination: UnitsSettingsView()) {
            SettingRowContent(
                icon: "ruler.fill",
                iconColor: .orange,
                title: "Units",
                subtitle: "Metric, Imperial, or Mixed"
            )
        }
    }
}

struct LanguageRow: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var showingLanguagePicker = false

    var body: some View {
        Button(action: { showingLanguagePicker = true }) {
            SettingRowContent(
                icon: "globe",
                iconColor: .blue,
                title: "language".localized,
                subtitle: localizationManager.currentLanguage.nativeName
            )
        }
        .foregroundColor(.primary)
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerView()
        }
    }
}

struct HelpSupportRow: View {
    var body: some View {
        NavigationLink(destination: HelpSupportView()) {
            SettingRowContent(
                icon: "questionmark.circle.fill",
                iconColor: .blue,
                title: "Help & Support",
                subtitle: "FAQs, guides, and contact support"
            )
        }
    }
}

struct AboutRow: View {
    let aboutAction: () -> Void

    var body: some View {
        Button(action: aboutAction) {
            SettingRowContent(
                icon: "info.circle.fill",
                iconColor: .gray,
                title: "About Healthing",
                subtitle: "Version 1.0.0 (Build 1)"
            )
        }
        .foregroundColor(.primary)
    }
}

struct FeedbackRow: View {
    var body: some View {
        Button(action: sendFeedback) {
            SettingRowContent(
                icon: "envelope.fill",
                iconColor: .green,
                title: "Send Feedback",
                subtitle: "Help us improve the app"
            )
        }
        .foregroundColor(.primary)
    }

    private func sendFeedback() {
        // Open feedback form or email
        if let url = URL(string: "mailto:support@healthing.app?subject=App Feedback") {
            UIApplication.shared.open(url)
        }
    }
}

struct SignOutRow: View {
    @EnvironmentObject private var securityManager: SecurityManager

    var body: some View {
        Button(action: signOut) {
            SettingRowContent(
                icon: "rectangle.portrait.and.arrow.right.fill",
                iconColor: .orange,
                title: "Sign Out",
                subtitle: "Sign out of your account"
            )
        }
        .foregroundColor(.orange)
    }

    private func signOut() {
        // Implement sign out logic
        securityManager.lockApplication()
    }
}

struct DeleteAccountRow: View {
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Button(action: { showingDeleteConfirmation = true }) {
            SettingRowContent(
                icon: "trash.fill",
                iconColor: .red,
                title: "Delete Account",
                subtitle: "Permanently delete your account and data"
            )
        }
        .foregroundColor(.red)
        .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This action cannot be undone. All your health data and account information will be permanently deleted.")
        }
    }

    private func deleteAccount() {
        // Implement account deletion logic
        print("Account deletion requested")
    }
}

// MARK: - Phase 2G Data Management Rows

struct DataIntegrityStatusRow: View {
    @ObservedObject var integrityService: DataIntegrityService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowContent(
                icon: integrityStatusIcon,
                iconColor: integrityStatusColor,
                title: "Data Integrity",
                subtitle: integrityStatusText
            )
        }
        .foregroundColor(.primary)
    }

    private var integrityStatusIcon: String {
        switch integrityService.integrityStatus {
        case .healthy:
            return "checkmark.shield.fill"
        case .warningIssues:
            return "exclamationmark.shield.fill"
        case .compromised:
            return "xmark.shield.fill"
        case .verifying:
            return "shield.fill"
        case .verificationFailed, .unknown:
            return "questionmark.shield.fill"
        }
    }

    private var integrityStatusColor: Color {
        switch integrityService.integrityStatus {
        case .healthy:
            return .green
        case .warningIssues:
            return .orange
        case .compromised, .verificationFailed:
            return .red
        case .verifying:
            return .blue
        case .unknown:
            return .gray
        }
    }

    private var integrityStatusText: String {
        switch integrityService.integrityStatus {
        case .healthy:
            return "All data verified and secure"
        case .warningIssues:
            return "Minor issues detected"
        case .compromised:
            return "Data integrity compromised"
        case .verifying:
            return "Verifying data integrity..."
        case .verificationFailed:
            return "Verification failed"
        case .unknown:
            return "Status unknown"
        }
    }
}

struct BackupPreferencesRow: View {
    @ObservedObject var backupManager: BackupPreferencesManager
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowContent(
                icon: "icloud.and.arrow.up.fill",
                iconColor: backupStatusColor,
                title: "Backup & Sync",
                subtitle: backupStatusText
            )
        }
        .foregroundColor(.primary)
    }

    private var backupStatusColor: Color {
        switch backupManager.backupStatus {
        case .enabled:
            return .green
        case .disabled:
            return .gray
        case .failed, .temporaryError:
            return .red
        case .noAccount, .restricted:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private var backupStatusText: String {
        switch backupManager.backupStatus {
        case .enabled:
            return "CloudKit sync enabled"
        case .disabled:
            return "CloudKit sync disabled"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "CloudKit restricted"
        case .failed:
            return "Sync failed"
        case .temporaryError:
            return "Temporary sync error"
        case .unknown:
            return "Status unknown"
        }
    }
}

struct RetentionPoliciesRow: View {
    @ObservedObject var retentionManager: RetentionPolicyManager
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowContent(
                icon: "calendar.badge.clock.fill",
                iconColor: .purple,
                title: "Data Retention",
                subtitle: "Manage how long data is kept"
            )
        }
        .foregroundColor(.primary)
    }
}

struct AuditTrailRow: View {
    @ObservedObject var auditService: AuditTrailService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowContent(
                icon: "list.clipboard.fill",
                iconColor: .indigo,
                title: "Audit Trail",
                subtitle: "\(auditService.auditLogCount) logged activities"
            )
        }
        .foregroundColor(.primary)
    }
}

struct EnhancedDataExportRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowContent(
                icon: "square.and.arrow.up.fill",
                iconColor: .blue,
                title: "Export Data",
                subtitle: "Export all health data and audit logs"
            )
        }
        .foregroundColor(.primary)
    }
}

struct ManualCleanupRow: View {
    @ObservedObject var retentionManager: RetentionPolicyManager
    @State private var showingCleanupOptions = false

    var body: some View {
        Button(action: { showingCleanupOptions = true }) {
            SettingRowContent(
                icon: "trash.fill",
                iconColor: retentionManager.isCleanupRunning ? .orange : .red,
                title: "Manual Cleanup",
                subtitle: retentionManager.isCleanupRunning ? "Cleanup in progress..." : "Clean up old data manually"
            )
        }
        .foregroundColor(.primary)
        .disabled(retentionManager.isCleanupRunning)
        .confirmationDialog("Manual Data Cleanup", isPresented: $showingCleanupOptions) {
            Button("Clean Temporary Files") {
                Task {
                    let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                    try? await retentionManager.performManualCleanup(for: .temporaryFiles, olderThan: oldDate)
                }
            }

            Button("Clean Old Activity Data (1 Year)") {
                Task {
                    let oldDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
                    try? await retentionManager.performManualCleanup(for: .activity, olderThan: oldDate)
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose what type of data to clean up. This action cannot be undone.")
        }
    }
}

// MARK: - Supporting Views

struct SettingRowContent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Detail Views (Placeholders)

struct ProfileEditView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section("Profile Information") {
                    TextField("First Name", text: .constant("John"))
                    TextField("Last Name", text: .constant("Doe"))
                    TextField("Email", text: .constant("john.doe@example.com"))
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct DataExportView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var dataStore: HealthDataStore
    @State private var isExporting = false

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                VStack(spacing: 16) {
                    Text("Export Your Data")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Download all your health data in a secure, encrypted format. This includes all measurements, documents, and app settings.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if isExporting {
                    ProgressView("Preparing your data...")
                } else {
                    Button("Export Data") {
                        exportData()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Data Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func exportData() {
        isExporting = true

        Task {
            do {
                let exportURL = try await dataStore.exportUserData()
                // Present share sheet with exported data
                await MainActor.run {
                    // Show share sheet
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    // Show error
                }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.red)

                        Text("Healthing")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Version 1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        AboutSection(
                            title: "Privacy First",
                            description: "All your health data is encrypted and processed locally on your device. We never share your personal health information."
                        )

                        AboutSection(
                            title: "Open Standards",
                            description: "Built with HL7 FHIR standards for medical data interoperability and Stanford Spezi framework for health applications."
                        )

                        AboutSection(
                            title: "Comprehensive Health Tracking",
                            description: "Track health metrics from Apple Watch, Garmin devices, and manual entries with AI-powered insights."
                        )
                    }

                    VStack(spacing: 12) {
                        Link("Privacy Policy", destination: URL(string: "https://healthing.app/privacy")!)
                        Link("Terms of Service", destination: URL(string: "https://healthing.app/terms")!)
                        Link("Open Source Licenses", destination: URL(string: "https://healthing.app/licenses")!)
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)

                    Text("© 2026 Healthing. All rights reserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct AboutSection: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .fontWeight(.semibold)

            Text(description)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Placeholder Detail Views

struct PrivacySettingsDetailView: View {
    var body: some View {
        Text("Privacy Settings Detail")
            .navigationTitle("Privacy")
    }
}

struct SecuritySettingsDetailView: View {
    var body: some View {
        Text("Security Settings Detail")
            .navigationTitle("Security")
    }
}

struct DataRetentionView: View {
    var body: some View {
        Text("Data Retention Settings")
            .navigationTitle("Data Retention")
    }
}

struct DataCleanupView: View {
    var body: some View {
        Text("Data Cleanup Options")
            .navigationTitle("Data Cleanup")
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        Text("Notification Settings")
            .navigationTitle("Notifications")
    }
}

struct UnitsSettingsView: View {
    var body: some View {
        Text("Units Settings")
            .navigationTitle("Units")
    }
}

struct LanguageSettingsView: View {
    var body: some View {
        Text("Language Settings")
            .navigationTitle("Language")
    }
}

struct HelpSupportView: View {
    var body: some View {
        Text("Help & Support")
            .navigationTitle("Help & Support")
    }
}

// MARK: - Supporting Types

enum ColorSchemePreference: CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SecurityManager.shared)
        .environmentObject(HealthDataStore.shared)
}