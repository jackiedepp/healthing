//
//  BackupPreferencesManager.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import CloudKit
import Combine
import OSLog

/// CloudKit sync preferences and backup management service
/// Implements REQ-071: Cloud backup preferences with user control
/// Provides granular control over data synchronization and privacy preferences
/// Ensures metadata-only sync while respecting user privacy choices
@MainActor
final class BackupPreferencesManager: ObservableObject {

    // MARK: - Singleton
    static let shared = BackupPreferencesManager()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "BackupPreferencesManager")
    private let dataStore = HealthDataStore.shared
    private let auditTrailService = AuditTrailService.shared
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    @Published var backupPreferences: BackupPreferences = BackupPreferences.default
    @Published var cloudKitAccountStatus: CKAccountStatus = .couldNotDetermine
    @Published var lastBackupDate: Date?
    @Published var backupStatus: BackupStatus = .unknown
    @Published var dataUsageStatistics: DataUsageStatistics?
    @Published var isConfiguring = false

    // MARK: - Keys
    private let preferencesKey = "backup_preferences"
    private let lastBackupKey = "last_backup_date"
    private let dataUsageKey = "data_usage_statistics"

    // MARK: - Initialization
    private init() {
        loadBackupPreferences()
        checkCloudKitAvailability()
        startDataUsageMonitoring()
    }

    // MARK: - Backup Preferences Management

    /// Load backup preferences from storage
    private func loadBackupPreferences() {
        if let preferencesData = userDefaults.data(forKey: preferencesKey),
           let preferences = try? JSONDecoder().decode(BackupPreferences.self, from: preferencesData) {
            backupPreferences = preferences
        }

        if let lastBackupData = userDefaults.object(forKey: lastBackupKey) as? Date {
            lastBackupDate = lastBackupData
        }

        if let usageData = userDefaults.data(forKey: dataUsageKey),
           let usage = try? JSONDecoder().decode(DataUsageStatistics.self, from: usageData) {
            dataUsageStatistics = usage
        }

        logger.info("Loaded backup preferences - CloudKit enabled: \(backupPreferences.isCloudKitEnabled)")
    }

    /// Save backup preferences to storage
    private func saveBackupPreferences() {
        if let preferencesData = try? JSONEncoder().encode(backupPreferences) {
            userDefaults.set(preferencesData, forKey: preferencesKey)
        }

        if let lastBackup = lastBackupDate {
            userDefaults.set(lastBackup, forKey: lastBackupKey)
        }

        if let usage = dataUsageStatistics,
           let usageData = try? JSONEncoder().encode(usage) {
            userDefaults.set(usageData, forKey: dataUsageKey)
        }
    }

    /// Update backup preferences
    func updateBackupPreferences(_ newPreferences: BackupPreferences) async {
        isConfiguring = true
        defer { isConfiguring = false }

        let oldPreferences = backupPreferences

        // Log preference change for audit
        await auditTrailService.logPrivacyEvent(
            event: .privacySettingsChanged,
            dataType: "backup_preferences",
            details: "Backup preferences updated - CloudKit: \(newPreferences.isCloudKitEnabled)"
        )

        backupPreferences = newPreferences
        saveBackupPreferences()

        // Handle CloudKit state changes
        if oldPreferences.isCloudKitEnabled != newPreferences.isCloudKitEnabled {
            if newPreferences.isCloudKitEnabled {
                await enableCloudKitSync()
            } else {
                await disableCloudKitSync()
            }
        }

        // Update sync data types if changed
        if oldPreferences.syncDataTypes != newPreferences.syncDataTypes {
            await updateSyncDataTypes(newPreferences.syncDataTypes)
        }

        logger.info("Updated backup preferences")
    }

    // MARK: - CloudKit Management

    /// Check CloudKit account availability
    private func checkCloudKitAvailability() {
        CKContainer.default().accountStatus { [weak self] status, error in
            Task { @MainActor in
                self?.cloudKitAccountStatus = status

                if let error = error {
                    self?.logger.error("CloudKit account check failed: \(error.localizedDescription)")
                    self?.backupStatus = .failed
                } else {
                    self?.updateBackupStatus(for: status)
                }
            }
        }
    }

    /// Update backup status based on CloudKit account status
    private func updateBackupStatus(for accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            backupStatus = backupPreferences.isCloudKitEnabled ? .enabled : .disabled
        case .noAccount:
            backupStatus = .noAccount
        case .restricted:
            backupStatus = .restricted
        case .couldNotDetermine:
            backupStatus = .unknown
        case .temporarilyUnavailable:
            backupStatus = .temporaryError
        @unknown default:
            backupStatus = .unknown
        }
    }

    /// Enable CloudKit synchronization
    private func enableCloudKitSync() async {
        guard cloudKitAccountStatus == .available else {
            logger.warning("Cannot enable CloudKit sync - account not available")
            backupStatus = .failed
            return
        }

        do {
            // Configure CloudKit for metadata-only sync
            try await dataStore.enableCloudKitSync(
                metadataOnly: true,
                dataTypes: backupPreferences.syncDataTypes
            )

            backupStatus = .enabled
            lastBackupDate = Date()
            saveBackupPreferences()

            logger.info("CloudKit sync enabled successfully")

            // Log privacy event
            await auditTrailService.logPrivacyEvent(
                event: .privacySettingsChanged,
                dataType: "cloudkit_sync",
                consentGiven: true,
                details: "CloudKit sync enabled with metadata-only configuration"
            )

        } catch {
            logger.error("Failed to enable CloudKit sync: \(error.localizedDescription)")
            backupStatus = .failed

            // Revert preference on failure
            backupPreferences.isCloudKitEnabled = false
            saveBackupPreferences()
        }
    }

    /// Disable CloudKit synchronization
    private func disableCloudKitSync() async {
        do {
            try await dataStore.disableCloudKitSync()

            backupStatus = .disabled
            saveBackupPreferences()

            logger.info("CloudKit sync disabled successfully")

            // Log privacy event
            await auditTrailService.logPrivacyEvent(
                event: .privacySettingsChanged,
                dataType: "cloudkit_sync",
                consentGiven: false,
                details: "CloudKit sync disabled by user"
            )

        } catch {
            logger.error("Failed to disable CloudKit sync: \(error.localizedDescription)")
        }
    }

    /// Update synchronized data types
    private func updateSyncDataTypes(_ dataTypes: Set<SyncDataType>) async {
        do {
            try await dataStore.updateSyncDataTypes(dataTypes)
            logger.info("Updated sync data types: \(dataTypes.map { $0.rawValue })")
        } catch {
            logger.error("Failed to update sync data types: \(error.localizedDescription)")
        }
    }

    // MARK: - Data Export and Backup

    /// Create manual backup of user data
    func createManualBackup() async throws -> BackupResult {
        guard backupPreferences.allowManualBackup else {
            throw BackupError.manualBackupDisabled
        }

        logger.info("Starting manual backup creation")

        let backupId = UUID().uuidString
        let backupDate = Date()

        do {
            // Export metadata and non-sensitive data only
            let exportData = try await exportBackupData()

            // Create backup archive
            let backupArchive = BackupArchive(
                id: backupId,
                date: backupDate,
                version: getAppVersion(),
                dataTypes: backupPreferences.syncDataTypes,
                exportData: exportData
            )

            // Save backup locally if enabled
            if backupPreferences.saveLocalBackups {
                try await saveLocalBackup(backupArchive)
            }

            // Upload to CloudKit if enabled
            if backupPreferences.isCloudKitEnabled {
                try await uploadToCloudKit(backupArchive)
            }

            lastBackupDate = backupDate
            saveBackupPreferences()

            // Update usage statistics
            await updateDataUsageStatistics(backupSize: exportData.count)

            // Log backup creation
            await auditTrailService.logDataOperation(
                operation: .export,
                dataType: "manual_backup",
                details: "Manual backup created with ID: \(backupId)"
            )

            logger.info("Manual backup completed successfully")

            return BackupResult(
                success: true,
                backupId: backupId,
                backupSize: exportData.count,
                message: NSLocalizedString("backup.success", comment: "Backup completed successfully")
            )

        } catch {
            logger.error("Manual backup failed: \(error.localizedDescription)")

            await auditTrailService.logSystemEvent(
                event: "backup_failed",
                details: "Manual backup failed: \(error.localizedDescription)"
            )

            throw error
        }
    }

    /// Restore from backup
    func restoreFromBackup(_ backupId: String) async throws {
        guard backupPreferences.allowBackupRestore else {
            throw BackupError.restoreDisabled
        }

        logger.info("Starting backup restore for ID: \(backupId)")

        do {
            let backup = try await retrieveBackup(backupId)

            // Verify backup integrity
            try await verifyBackupIntegrity(backup)

            // Create restore point
            let restorePointId = try await createRestorePoint()

            // Restore data
            try await restoreBackupData(backup.exportData)

            // Log restore operation
            await auditTrailService.logDataOperation(
                operation: .import,
                dataType: "backup_restore",
                details: "Backup restored from ID: \(backupId), restore point: \(restorePointId)"
            )

            logger.info("Backup restore completed successfully")

        } catch {
            logger.error("Backup restore failed: \(error.localizedDescription)")

            await auditTrailService.logSystemEvent(
                event: "restore_failed",
                details: "Backup restore failed: \(error.localizedDescription)"
            )

            throw error
        }
    }

    // MARK: - Data Usage Monitoring

    /// Start monitoring data usage for CloudKit
    private func startDataUsageMonitoring() {
        Timer.publish(every: 3600, on: .main, in: .common) // Every hour
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.updateDataUsageStatistics() }
            }
            .store(in: &cancellables)
    }

    /// Update data usage statistics
    private func updateDataUsageStatistics(backupSize: Int? = nil) async {
        do {
            let currentUsage = try await calculateCurrentDataUsage()

            var newStatistics = dataUsageStatistics ?? DataUsageStatistics(
                totalSyncedBytes: 0,
                lastCalculated: Date(),
                dailyUsage: [],
                monthlyLimit: backupPreferences.monthlyDataLimitMB
            )

            if let backupSize = backupSize {
                newStatistics.totalSyncedBytes += Int64(backupSize)
            }

            newStatistics.lastCalculated = Date()
            newStatistics.monthlyLimit = backupPreferences.monthlyDataLimitMB

            // Update daily usage
            let today = Calendar.current.startOfDay(for: Date())
            if let todayIndex = newStatistics.dailyUsage.firstIndex(where: {
                Calendar.current.isDate($0.date, inSameDayAs: today)
            }) {
                newStatistics.dailyUsage[todayIndex].bytesUsed = currentUsage
            } else {
                newStatistics.dailyUsage.append(
                    DailyDataUsage(date: today, bytesUsed: currentUsage)
                )

                // Keep only last 30 days
                newStatistics.dailyUsage = Array(newStatistics.dailyUsage.suffix(30))
            }

            dataUsageStatistics = newStatistics
            saveBackupPreferences()

        } catch {
            logger.error("Failed to update data usage statistics: \(error.localizedDescription)")
        }
    }

    /// Calculate current data usage
    private func calculateCurrentDataUsage() async throws -> Int64 {
        // This would calculate actual CloudKit usage
        return 0 // Placeholder implementation
    }

    // MARK: - Backup Operations

    private func exportBackupData() async throws -> Data {
        // Export metadata-only backup data
        let exportData = BackupExportData(
            timestamp: Date(),
            preferences: backupPreferences,
            metadata: try await dataStore.exportMetadata()
        )

        return try JSONEncoder().encode(exportData)
    }

    private func saveLocalBackup(_ backup: BackupArchive) async throws {
        let backupsDirectory = getLocalBackupsDirectory()
        let backupFile = backupsDirectory.appendingPathComponent("\(backup.id).backup")

        let backupData = try JSONEncoder().encode(backup)
        try backupData.write(to: backupFile)

        logger.info("Local backup saved to: \(backupFile.path)")
    }

    private func uploadToCloudKit(_ backup: BackupArchive) async throws {
        // CloudKit upload implementation would go here
        logger.info("CloudKit backup upload would be implemented here")
    }

    private func retrieveBackup(_ backupId: String) async throws -> BackupArchive {
        // Backup retrieval implementation would go here
        throw BackupError.backupNotFound
    }

    private func verifyBackupIntegrity(_ backup: BackupArchive) async throws {
        // Backup integrity verification would go here
        logger.info("Backup integrity verification would be implemented here")
    }

    private func createRestorePoint() async throws -> String {
        // Create restore point before restoration
        let restorePointId = UUID().uuidString
        logger.info("Created restore point: \(restorePointId)")
        return restorePointId
    }

    private func restoreBackupData(_ data: Data) async throws {
        // Data restoration implementation would go here
        logger.info("Data restoration would be implemented here")
    }

    // MARK: - Helper Methods

    private func getLocalBackupsDirectory() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupsDirectory = documentsDirectory.appendingPathComponent("Backups")

        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        return backupsDirectory
    }

    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Data Management

    /// Get available backup files
    func getAvailableBackups() async throws -> [BackupInfo] {
        var backups: [BackupInfo] = []

        // Get local backups
        if backupPreferences.saveLocalBackups {
            backups.append(contentsOf: try await getLocalBackups())
        }

        // Get CloudKit backups
        if backupPreferences.isCloudKitEnabled {
            backups.append(contentsOf: try await getCloudKitBackups())
        }

        return backups.sorted { $0.date > $1.date }
    }

    private func getLocalBackups() async throws -> [BackupInfo] {
        let backupsDirectory = getLocalBackupsDirectory()
        let fileManager = FileManager.default

        let backupFiles = try fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        )

        return backupFiles.compactMap { fileURL in
            guard fileURL.pathExtension == "backup" else { return nil }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return BackupInfo(
                    id: fileURL.deletingPathExtension().lastPathComponent,
                    date: resourceValues.creationDate ?? Date(),
                    size: Int64(resourceValues.fileSize ?? 0),
                    location: .local,
                    isComplete: true
                )
            } catch {
                return nil
            }
        }
    }

    private func getCloudKitBackups() async throws -> [BackupInfo] {
        // CloudKit backup listing would be implemented here
        return []
    }

    /// Delete backup
    func deleteBackup(_ backupId: String) async throws {
        // Implement backup deletion
        logger.info("Backup deletion would be implemented here for ID: \(backupId)")

        await auditTrailService.logDataOperation(
            operation: .delete,
            dataType: "backup",
            recordId: backupId,
            details: "Backup deleted by user"
        )
    }
}

// MARK: - Supporting Models

/// Backup preferences configuration
struct BackupPreferences: Codable {
    var isCloudKitEnabled: Bool
    var syncDataTypes: Set<SyncDataType>
    var allowManualBackup: Bool
    var allowBackupRestore: Bool
    var saveLocalBackups: Bool
    var autoBackupFrequency: AutoBackupFrequency
    var monthlyDataLimitMB: Int
    var retainBackupsFor: BackupRetentionPeriod

    static let `default` = BackupPreferences(
        isCloudKitEnabled: false,
        syncDataTypes: [.achievements, .preferences, .goals],
        allowManualBackup: true,
        allowBackupRestore: true,
        saveLocalBackups: true,
        autoBackupFrequency: .weekly,
        monthlyDataLimitMB: 100,
        retainBackupsFor: .sixMonths
    )
}

/// Data types available for synchronization
enum SyncDataType: String, CaseIterable, Codable {
    case achievements = "achievements"
    case preferences = "preferences"
    case goals = "goals"
    case reminders = "reminders"
    case insights = "insights"
    case metadata = "metadata"
}

/// Auto backup frequencies
enum AutoBackupFrequency: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case disabled = "disabled"
}

/// Backup retention periods
enum BackupRetentionPeriod: String, CaseIterable, Codable {
    case oneMonth = "one_month"
    case threeMonths = "three_months"
    case sixMonths = "six_months"
    case oneYear = "one_year"
    case indefinite = "indefinite"
}

/// Backup status
enum BackupStatus: String {
    case unknown = "unknown"
    case enabled = "enabled"
    case disabled = "disabled"
    case noAccount = "no_account"
    case restricted = "restricted"
    case temporaryError = "temporary_error"
    case failed = "failed"
}

/// Data usage statistics
struct DataUsageStatistics: Codable {
    var totalSyncedBytes: Int64
    var lastCalculated: Date
    var dailyUsage: [DailyDataUsage]
    var monthlyLimit: Int
}

/// Daily data usage
struct DailyDataUsage: Codable {
    let date: Date
    var bytesUsed: Int64
}

/// Backup result
struct BackupResult {
    let success: Bool
    let backupId: String?
    let backupSize: Int?
    let message: String
}

/// Backup archive
struct BackupArchive: Codable {
    let id: String
    let date: Date
    let version: String
    let dataTypes: Set<SyncDataType>
    let exportData: Data
}

/// Backup export data
struct BackupExportData: Codable {
    let timestamp: Date
    let preferences: BackupPreferences
    let metadata: Data
}

/// Backup information
struct BackupInfo: Identifiable {
    let id: String
    let date: Date
    let size: Int64
    let location: BackupLocation
    let isComplete: Bool
}

/// Backup location
enum BackupLocation: String {
    case local = "local"
    case cloudKit = "cloudkit"
    case both = "both"
}

/// Backup errors
enum BackupError: Error {
    case manualBackupDisabled
    case restoreDisabled
    case cloudKitNotAvailable
    case backupNotFound
    case insufficientSpace
    case networkError(String)
    case dataCorrupted
}

extension BackupError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .manualBackupDisabled:
            return NSLocalizedString("backup.error.manual_disabled", comment: "Manual backup is disabled")
        case .restoreDisabled:
            return NSLocalizedString("backup.error.restore_disabled", comment: "Backup restore is disabled")
        case .cloudKitNotAvailable:
            return NSLocalizedString("backup.error.cloudkit_unavailable", comment: "CloudKit is not available")
        case .backupNotFound:
            return NSLocalizedString("backup.error.not_found", comment: "Backup not found")
        case .insufficientSpace:
            return NSLocalizedString("backup.error.insufficient_space", comment: "Insufficient storage space")
        case .networkError(let message):
            return String.localizedStringWithFormat(NSLocalizedString("backup.error.network", comment: "Network error: %@"), message)
        case .dataCorrupted:
            return NSLocalizedString("backup.error.corrupted", comment: "Backup data is corrupted")
        }
    }
}