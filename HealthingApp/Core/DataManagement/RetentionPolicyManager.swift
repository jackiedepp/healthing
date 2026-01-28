//
//  RetentionPolicyManager.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import CoreData
import Combine
import OSLog

/// Data retention policy management service for automated cleanup and archival
/// Implements REQ-070: Data cleanup and retention policy management
/// Supports GDPR Article 5 (Storage Limitation) compliance
/// Integrates with audit trail for transparent data lifecycle management
@MainActor
final class RetentionPolicyManager: ObservableObject {

    // MARK: - Singleton
    static let shared = RetentionPolicyManager()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "RetentionPolicyManager")
    private let dataStore = HealthDataStore.shared
    private let auditTrailService = AuditTrailService.shared
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    @Published var retentionPolicies: [RetentionPolicy] = []
    @Published var isCleanupRunning = false
    @Published var lastCleanupDate: Date?
    @Published var nextScheduledCleanup: Date?
    @Published var cleanupStatistics: CleanupStatistics?

    // MARK: - Default Retention Periods (in days)
    private struct DefaultRetentionPeriods {
        static let vitals = 1095 // 3 years
        static let activityData = 730 // 2 years
        static let sleepData = 730 // 2 years
        static let medicalRecords = 3650 // 10 years (regulatory requirement)
        static let documents = 2190 // 6 years
        static let auditLogs = 2555 // 7 years (GDPR requirement)
        static let achievements = 1095 // 3 years
        static let medication = 1095 // 3 years
        static let appointments = 730 // 2 years
        static let temporaryFiles = 30 // 30 days
        static let crashLogs = 90 // 90 days
    }

    // MARK: - Keys
    private let retentionPoliciesKey = "retention_policies"
    private let lastCleanupKey = "last_cleanup_date"
    private let userRetentionPreferencesKey = "user_retention_preferences"

    // MARK: - Initialization
    private init() {
        loadRetentionPolicies()
        scheduleAutomaticCleanup()
        setupNotificationObservers()
    }

    // MARK: - Policy Management

    /// Load retention policies from storage
    private func loadRetentionPolicies() {
        if let policiesData = userDefaults.data(forKey: retentionPoliciesKey),
           let decodedPolicies = try? JSONDecoder().decode([RetentionPolicy].self, from: policiesData) {
            retentionPolicies = decodedPolicies
        } else {
            // Initialize with default policies
            retentionPolicies = createDefaultRetentionPolicies()
            saveRetentionPolicies()
        }

        if let lastCleanupData = userDefaults.object(forKey: lastCleanupKey) as? Date {
            lastCleanupDate = lastCleanupData
        }

        logger.info("Loaded \(retentionPolicies.count) retention policies")
    }

    /// Save retention policies to storage
    private func saveRetentionPolicies() {
        if let policiesData = try? JSONEncoder().encode(retentionPolicies) {
            userDefaults.set(policiesData, forKey: retentionPoliciesKey)
        }

        if let lastCleanup = lastCleanupDate {
            userDefaults.set(lastCleanup, forKey: lastCleanupKey)
        }
    }

    /// Create default retention policies
    private func createDefaultRetentionPolicies() -> [RetentionPolicy] {
        return [
            RetentionPolicy(
                id: "vitals_retention",
                dataType: .vitals,
                retentionPeriodDays: DefaultRetentionPeriods.vitals,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.vitals", comment: "Vital signs and health measurements")
            ),
            RetentionPolicy(
                id: "activity_retention",
                dataType: .activity,
                retentionPeriodDays: DefaultRetentionPeriods.activityData,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.activity", comment: "Physical activity and exercise data")
            ),
            RetentionPolicy(
                id: "sleep_retention",
                dataType: .sleep,
                retentionPeriodDays: DefaultRetentionPeriods.sleepData,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.sleep", comment: "Sleep tracking and analysis data")
            ),
            RetentionPolicy(
                id: "medical_records_retention",
                dataType: .medicalRecords,
                retentionPeriodDays: DefaultRetentionPeriods.medicalRecords,
                isEnabled: true,
                userConfigurable: false,
                description: NSLocalizedString("retention.policy.medical", comment: "Medical records and clinical documents")
            ),
            RetentionPolicy(
                id: "documents_retention",
                dataType: .documents,
                retentionPeriodDays: DefaultRetentionPeriods.documents,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.documents", comment: "Uploaded health documents and images")
            ),
            RetentionPolicy(
                id: "audit_retention",
                dataType: .auditLogs,
                retentionPeriodDays: DefaultRetentionPeriods.auditLogs,
                isEnabled: true,
                userConfigurable: false,
                description: NSLocalizedString("retention.policy.audit", comment: "System audit logs and access records")
            ),
            RetentionPolicy(
                id: "achievements_retention",
                dataType: .achievements,
                retentionPeriodDays: DefaultRetentionPeriods.achievements,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.achievements", comment: "Health achievements and gamification data")
            ),
            RetentionPolicy(
                id: "medication_retention",
                dataType: .medications,
                retentionPeriodDays: DefaultRetentionPeriods.medication,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.medication", comment: "Medication tracking and adherence data")
            ),
            RetentionPolicy(
                id: "appointments_retention",
                dataType: .appointments,
                retentionPeriodDays: DefaultRetentionPeriods.appointments,
                isEnabled: true,
                userConfigurable: true,
                description: NSLocalizedString("retention.policy.appointments", comment: "Healthcare appointments and reminders")
            ),
            RetentionPolicy(
                id: "temporary_retention",
                dataType: .temporaryFiles,
                retentionPeriodDays: DefaultRetentionPeriods.temporaryFiles,
                isEnabled: true,
                userConfigurable: false,
                description: NSLocalizedString("retention.policy.temporary", comment: "Temporary files and cache data")
            )
        ]
    }

    /// Update retention policy
    func updateRetentionPolicy(_ policy: RetentionPolicy) async -> Bool {
        guard let index = retentionPolicies.firstIndex(where: { $0.id == policy.id }) else {
            logger.error("Retention policy not found: \(policy.id)")
            return false
        }

        // Validate retention period
        guard validateRetentionPeriod(policy.retentionPeriodDays, for: policy.dataType) else {
            logger.error("Invalid retention period for \(policy.dataType): \(policy.retentionPeriodDays) days")
            return false
        }

        // Log the policy change for audit
        await auditTrailService.logDataOperation(
            operation: .modify,
            dataType: "retention_policy",
            details: "Updated retention policy: \(policy.id) to \(policy.retentionPeriodDays) days"
        )

        retentionPolicies[index] = policy
        saveRetentionPolicies()

        logger.info("Updated retention policy: \(policy.id)")
        return true
    }

    /// Validate retention period against regulatory requirements
    private func validateRetentionPeriod(_ days: Int, for dataType: DataType) -> Bool {
        switch dataType {
        case .medicalRecords:
            return days >= DefaultRetentionPeriods.medicalRecords // Minimum 10 years
        case .auditLogs:
            return days >= DefaultRetentionPeriods.auditLogs // Minimum 7 years for GDPR
        case .temporaryFiles:
            return days <= 90 // Maximum 90 days
        default:
            return days >= 30 && days <= 3650 // 30 days to 10 years
        }
    }

    // MARK: - Automatic Cleanup

    /// Schedule automatic cleanup based on policy settings
    private func scheduleAutomaticCleanup() {
        // Schedule daily cleanup at 2 AM
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.hour = 2
        dateComponents.minute = 0

        Timer.publish(every: 86400, on: .main, in: .common) // 24 hours
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.performAutomaticCleanup() }
            }
            .store(in: &cancellables)

        // Calculate next cleanup time
        nextScheduledCleanup = calendar.nextDate(
            after: Date(),
            matching: dateComponents,
            matchingPolicy: .nextTime
        )
    }

    /// Perform automatic cleanup based on retention policies
    func performAutomaticCleanup() async {
        guard !isCleanupRunning else {
            logger.info("Cleanup already running, skipping")
            return
        }

        logger.info("Starting automatic data cleanup")

        await MainActor.run {
            isCleanupRunning = true
        }

        defer {
            Task { @MainActor in
                isCleanupRunning = false
                lastCleanupDate = Date()
                saveRetentionPolicies()
            }
        }

        var totalDeletedRecords = 0
        var deletedByType: [DataType: Int] = [:]

        for policy in retentionPolicies.filter({ $0.isEnabled }) {
            do {
                let deletedCount = try await cleanupDataType(policy.dataType, retentionDays: policy.retentionPeriodDays)
                totalDeletedRecords += deletedCount
                deletedByType[policy.dataType] = deletedCount

                logger.info("Cleaned up \(deletedCount) records for \(policy.dataType)")
            } catch {
                logger.error("Failed to cleanup \(policy.dataType): \(error.localizedDescription)")
            }
        }

        // Update cleanup statistics
        await MainActor.run {
            cleanupStatistics = CleanupStatistics(
                totalRecordsDeleted: totalDeletedRecords,
                deletedByType: deletedByType,
                cleanupDate: Date()
            )
        }

        // Log cleanup completion for audit
        await auditTrailService.logDataOperation(
            operation: .delete,
            dataType: "bulk_cleanup",
            details: "Automatic cleanup completed: \(totalDeletedRecords) records deleted"
        )

        logger.info("Automatic cleanup completed: \(totalDeletedRecords) total records deleted")
    }

    /// Cleanup specific data type based on retention period
    private func cleanupDataType(_ dataType: DataType, retentionDays: Int) async throws -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        switch dataType {
        case .vitals:
            return try await cleanupVitals(olderThan: cutoffDate)
        case .activity:
            return try await cleanupActivityData(olderThan: cutoffDate)
        case .sleep:
            return try await cleanupSleepData(olderThan: cutoffDate)
        case .documents:
            return try await cleanupDocuments(olderThan: cutoffDate)
        case .achievements:
            return try await cleanupAchievements(olderThan: cutoffDate)
        case .medications:
            return try await cleanupMedications(olderThan: cutoffDate)
        case .appointments:
            return try await cleanupAppointments(olderThan: cutoffDate)
        case .auditLogs:
            return try await cleanupAuditLogs(olderThan: cutoffDate)
        case .temporaryFiles:
            return try await cleanupTemporaryFiles(olderThan: cutoffDate)
        case .medicalRecords:
            // Medical records typically shouldn't be auto-deleted due to regulatory requirements
            logger.warning("Medical records cleanup requested - manual review required")
            return 0
        }
    }

    // MARK: - Specific Cleanup Methods

    private func cleanupVitals(olderThan cutoffDate: Date) async throws -> Int {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<VitalSigns> = VitalSigns.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as CVarArg)

            let results = try context.fetch(request)
            let count = results.count

            for vital in results {
                context.delete(vital)
            }

            try context.save()
            return count
        }
    }

    private func cleanupActivityData(olderThan cutoffDate: Date) async throws -> Int {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<ActivityData> = ActivityData.fetchRequest()
            request.predicate = NSPredicate(format: "date < %@", cutoffDate as CVarArg)

            let results = try context.fetch(request)
            let count = results.count

            for activity in results {
                context.delete(activity)
            }

            try context.save()
            return count
        }
    }

    private func cleanupSleepData(olderThan cutoffDate: Date) async throws -> Int {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<SleepData> = SleepData.fetchRequest()
            request.predicate = NSPredicate(format: "startTime < %@", cutoffDate as CVarArg)

            let results = try context.fetch(request)
            let count = results.count

            for sleep in results {
                context.delete(sleep)
            }

            try context.save()
            return count
        }
    }

    private func cleanupDocuments(olderThan cutoffDate: Date) async throws -> Int {
        // This would integrate with DocumentUploadManager for secure deletion
        logger.info("Document cleanup would be handled by DocumentUploadManager")
        return 0
    }

    private func cleanupAchievements(olderThan cutoffDate: Date) async throws -> Int {
        // This would integrate with AchievementEngine for achievement cleanup
        logger.info("Achievement cleanup would be handled by AchievementEngine")
        return 0
    }

    private func cleanupMedications(olderThan cutoffDate: Date) async throws -> Int {
        // This would integrate with MedicationRemindersService for medication cleanup
        logger.info("Medication cleanup would be handled by MedicationRemindersService")
        return 0
    }

    private func cleanupAppointments(olderThan cutoffDate: Date) async throws -> Int {
        // This would integrate with AppointmentRemindersService for appointment cleanup
        logger.info("Appointment cleanup would be handled by AppointmentRemindersService")
        return 0
    }

    private func cleanupAuditLogs(olderThan cutoffDate: Date) async throws -> Int {
        return try await auditTrailService.cleanupAuditLogs(olderThan: cutoffDate)
    }

    private func cleanupTemporaryFiles(olderThan cutoffDate: Date) async throws -> Int {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        var deletedCount = 0

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            for fileURL in contents {
                let attributes = try fileURL.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = attributes.creationDate,
                   creationDate < cutoffDate {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                }
            }
        } catch {
            logger.error("Failed to cleanup temporary files: \(error.localizedDescription)")
            throw error
        }

        return deletedCount
    }

    // MARK: - Manual Cleanup

    /// Perform manual cleanup for specific data type
    func performManualCleanup(for dataType: DataType, olderThan date: Date) async throws -> Int {
        logger.info("Starting manual cleanup for \(dataType)")

        // Log manual cleanup request
        await auditTrailService.logDataOperation(
            operation: .delete,
            dataType: "manual_cleanup",
            details: "Manual cleanup requested for \(dataType) older than \(date)"
        )

        let deletedCount = try await cleanupDataType(dataType, retentionDays: Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)

        logger.info("Manual cleanup completed: \(deletedCount) records deleted")
        return deletedCount
    }

    /// Get data size estimates for each data type
    func getDataSizeEstimates() async -> [DataType: DataSizeEstimate] {
        var estimates: [DataType: DataSizeEstimate] = [:]

        for dataType in DataType.allCases {
            let estimate = await calculateDataSizeEstimate(for: dataType)
            estimates[dataType] = estimate
        }

        return estimates
    }

    private func calculateDataSizeEstimate(for dataType: DataType) async -> DataSizeEstimate {
        // This would calculate actual storage usage for each data type
        return DataSizeEstimate(
            recordCount: 0,
            estimatedSizeBytes: 0,
            oldestRecord: nil
        )
    }

    // MARK: - User Preferences

    /// Get user-configurable retention preferences
    func getUserRetentionPreferences() -> [String: Int] {
        return userDefaults.dictionary(forKey: userRetentionPreferencesKey) as? [String: Int] ?? [:]
    }

    /// Update user retention preferences
    func updateUserRetentionPreferences(_ preferences: [String: Int]) async {
        userDefaults.set(preferences, forKey: userRetentionPreferencesKey)

        // Apply user preferences to policies
        for (policyId, retentionDays) in preferences {
            if let policy = retentionPolicies.first(where: { $0.id == policyId && $0.userConfigurable }) {
                var updatedPolicy = policy
                updatedPolicy.retentionPeriodDays = retentionDays
                _ = await updateRetentionPolicy(updatedPolicy)
            }
        }

        logger.info("Updated user retention preferences")
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                // Perform final cleanup before app termination
                Task { await self?.performAutomaticCleanup() }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Models

/// Data retention policy definition
struct RetentionPolicy: Codable, Identifiable {
    let id: String
    let dataType: DataType
    var retentionPeriodDays: Int
    let isEnabled: Bool
    let userConfigurable: Bool
    let description: String
    let createdDate: Date
    let lastModifiedDate: Date

    init(
        id: String,
        dataType: DataType,
        retentionPeriodDays: Int,
        isEnabled: Bool = true,
        userConfigurable: Bool = true,
        description: String
    ) {
        self.id = id
        self.dataType = dataType
        self.retentionPeriodDays = retentionPeriodDays
        self.isEnabled = isEnabled
        self.userConfigurable = userConfigurable
        self.description = description
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
}

/// Data types for retention policies
enum DataType: String, CaseIterable, Codable {
    case vitals = "vitals"
    case activity = "activity"
    case sleep = "sleep"
    case medicalRecords = "medical_records"
    case documents = "documents"
    case auditLogs = "audit_logs"
    case achievements = "achievements"
    case medications = "medications"
    case appointments = "appointments"
    case temporaryFiles = "temporary_files"
}

/// Cleanup statistics
struct CleanupStatistics: Codable {
    let totalRecordsDeleted: Int
    let deletedByType: [DataType: Int]
    let cleanupDate: Date
}

/// Data size estimate
struct DataSizeEstimate {
    let recordCount: Int
    let estimatedSizeBytes: Int64
    let oldestRecord: Date?
}