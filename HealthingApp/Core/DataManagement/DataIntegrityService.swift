//
//  DataIntegrityService.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import CoreData
import CryptoKit
import Combine
import OSLog

/// Data integrity verification service for continuous data protection
/// Implements REQ-072: Integrate data integrity verification into storage flows
/// Provides cryptographic verification, corruption detection, and automated healing
/// Integrates with SecurityManager for enhanced data protection
@MainActor
final class DataIntegrityService: ObservableObject {

    // MARK: - Singleton
    static let shared = DataIntegrityService()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "DataIntegrityService")
    private let dataStore = HealthDataStore.shared
    private let securityManager = SecurityManager.shared
    private let auditTrailService = AuditTrailService.shared
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    @Published var integrityStatus: IntegrityStatus = .unknown
    @Published var lastVerificationDate: Date?
    @Published var verificationProgress: Double = 0.0
    @Published var integrityStatistics: IntegrityStatistics?
    @Published var isVerifying = false
    @Published var corruptedRecords: [CorruptedRecord] = []

    // MARK: - Configuration
    private struct IntegrityConfiguration {
        let verificationInterval: TimeInterval = 86400 // 24 hours
        let batchSize: Int = 100
        let enableContinuousVerification: Bool = true
        let enableAutomaticHealing: Bool = true
        let maximumCorruptionTolerance: Double = 0.01 // 1%
    }

    private let config = IntegrityConfiguration()

    // MARK: - Keys
    private let lastVerificationKey = "last_integrity_verification"
    private let integrityStatisticsKey = "integrity_statistics"
    private let integrityConfigKey = "integrity_configuration"

    // MARK: - Initialization
    private init() {
        loadIntegrityData()
        startContinuousVerification()
        setupDataStoreObserver()
    }

    // MARK: - Data Loading & Persistence

    private func loadIntegrityData() {
        if let lastVerificationData = userDefaults.object(forKey: lastVerificationKey) as? Date {
            lastVerificationDate = lastVerificationData
        }

        if let statisticsData = userDefaults.data(forKey: integrityStatisticsKey),
           let statistics = try? JSONDecoder().decode(IntegrityStatistics.self, from: statisticsData) {
            integrityStatistics = statistics
        }

        logger.info("Loaded integrity data - Last verification: \(lastVerificationDate?.description ?? "none")")
    }

    private func saveIntegrityData() {
        if let lastVerification = lastVerificationDate {
            userDefaults.set(lastVerification, forKey: lastVerificationKey)
        }

        if let statistics = integrityStatistics,
           let statisticsData = try? JSONEncoder().encode(statistics) {
            userDefaults.set(statisticsData, forKey: integrityStatisticsKey)
        }
    }

    // MARK: - Data Store Observer

    private func setupDataStoreObserver() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                Task { await self?.handleDataStoreSave(notification) }
            }
            .store(in: &cancellables)
    }

    private func handleDataStoreSave(_ notification: Notification) async {
        guard config.enableContinuousVerification else { return }

        // Verify integrity of newly saved or modified objects
        if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for object in inserted {
                await verifyObjectIntegrity(object, operation: .create)
            }
        }

        if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updated {
                await verifyObjectIntegrity(object, operation: .update)
            }
        }
    }

    // MARK: - Integrity Verification

    /// Perform comprehensive integrity verification
    func performFullIntegrityCheck() async -> IntegrityReport {
        logger.info("Starting full integrity verification")

        await MainActor.run {
            isVerifying = true
            verificationProgress = 0.0
            integrityStatus = .verifying
        }

        defer {
            Task { @MainActor in
                isVerifying = false
                verificationProgress = 1.0
                lastVerificationDate = Date()
                saveIntegrityData()
            }
        }

        do {
            var report = IntegrityReport(
                startTime: Date(),
                endTime: Date(),
                totalRecords: 0,
                verifiedRecords: 0,
                corruptedRecords: [],
                healedRecords: [],
                errors: []
            )

            // Verify different data types
            report = try await verifyVitalSigns(report: report)
            report = try await verifyActivityData(report: report)
            report = try await verifyMedicalRecords(report: report)
            report = try await verifyUserData(report: report)

            report.endTime = Date()

            // Update integrity status
            let corruptionRate = Double(report.corruptedRecords.count) / Double(max(1, report.totalRecords))
            await MainActor.run {
                if corruptionRate > config.maximumCorruptionTolerance {
                    integrityStatus = .compromised
                } else if report.corruptedRecords.isEmpty {
                    integrityStatus = .healthy
                } else {
                    integrityStatus = .warningIssues
                }

                corruptedRecords = report.corruptedRecords

                // Update statistics
                integrityStatistics = IntegrityStatistics(
                    lastVerification: Date(),
                    totalVerifications: (integrityStatistics?.totalVerifications ?? 0) + 1,
                    totalRecordsVerified: report.totalRecords,
                    totalCorruptionDetected: report.corruptedRecords.count,
                    totalRecordsHealed: report.healedRecords.count,
                    averageVerificationTime: calculateAverageVerificationTime(report),
                    corruptionRate: corruptionRate
                )
            }

            // Log verification completion
            await auditTrailService.logSystemEvent(
                event: "integrity_verification_completed",
                details: "Verified \(report.totalRecords) records, found \(report.corruptedRecords.count) corrupted"
            )

            logger.info("Integrity verification completed - Status: \(integrityStatus)")
            return report

        } catch {
            logger.error("Integrity verification failed: \(error.localizedDescription)")

            await MainActor.run {
                integrityStatus = .verificationFailed
            }

            await auditTrailService.logSystemEvent(
                event: "integrity_verification_failed",
                details: "Integrity verification failed: \(error.localizedDescription)"
            )

            throw error
        }
    }

    /// Verify specific object integrity
    private func verifyObjectIntegrity(_ object: NSManagedObject, operation: DataOperation) async {
        do {
            let hasIntegrityData = object.entity.attributesByName.keys.contains("dataHash")

            if hasIntegrityData {
                let isValid = try await verifyDataHash(for: object)
                if !isValid {
                    await handleIntegrityFailure(object, operation: operation)
                }
            } else {
                // Generate integrity hash for objects that don't have one
                try await generateIntegrityHash(for: object)
            }
        } catch {
            logger.error("Failed to verify object integrity: \(error.localizedDescription)")
        }
    }

    /// Verify data hash for Core Data object
    private func verifyDataHash(for object: NSManagedObject) async throws -> Bool {
        guard let existingHash = object.value(forKey: "dataHash") as? String else {
            // Generate hash if missing
            try await generateIntegrityHash(for: object)
            return true
        }

        let computedHash = try generateObjectHash(object)
        return existingHash == computedHash
    }

    /// Generate integrity hash for Core Data object
    private func generateIntegrityHash(for object: NSManagedObject) async throws {
        let hash = try generateObjectHash(object)
        object.setValue(hash, forKey: "dataHash")

        try await dataStore.performBackgroundTask { context in
            if let existingObject = try? context.existingObject(with: object.objectID) {
                existingObject.setValue(hash, forKey: "dataHash")
                try context.save()
            }
        }
    }

    /// Generate cryptographic hash for object data
    private func generateObjectHash(_ object: NSManagedObject) throws -> String {
        var hashInput = ""

        // Include all non-system attributes in hash
        for (attributeName, attribute) in object.entity.attributesByName {
            guard attributeName != "dataHash" && attributeName != "lastModified" else { continue }

            if let value = object.value(forKey: attributeName) {
                hashInput += "\(attributeName):\(value)"
            }
        }

        let inputData = hashInput.data(using: .utf8) ?? Data()
        return securityManager.generateDataHash(inputData)
    }

    // MARK: - Data Type Verification

    private func verifyVitalSigns(report: IntegrityReport) async throws -> IntegrityReport {
        return try await verifyDataType(
            report: report,
            entityName: "VitalSigns",
            batchProcessor: { batch, report in
                return try await self.processVitalSignsBatch(batch, report: report)
            }
        )
    }

    private func verifyActivityData(report: IntegrityReport) async throws -> IntegrityReport {
        return try await verifyDataType(
            report: report,
            entityName: "ActivityData",
            batchProcessor: { batch, report in
                return try await self.processActivityDataBatch(batch, report: report)
            }
        )
    }

    private func verifyMedicalRecords(report: IntegrityReport) async throws -> IntegrityReport {
        return try await verifyDataType(
            report: report,
            entityName: "MedicalRecord",
            batchProcessor: { batch, report in
                return try await self.processMedicalRecordsBatch(batch, report: report)
            }
        )
    }

    private func verifyUserData(report: IntegrityReport) async throws -> IntegrityReport {
        return try await verifyDataType(
            report: report,
            entityName: "UserData",
            batchProcessor: { batch, report in
                return try await self.processUserDataBatch(batch, report: report)
            }
        )
    }

    private func verifyDataType(
        report: IntegrityReport,
        entityName: String,
        batchProcessor: @escaping ([NSManagedObject], IntegrityReport) async throws -> IntegrityReport
    ) async throws -> IntegrityReport {
        return try await dataStore.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.fetchBatchSize = self.config.batchSize

            let totalCount = try context.count(for: request)
            var updatedReport = report
            updatedReport.totalRecords += totalCount

            let batches = stride(from: 0, to: totalCount, by: self.config.batchSize)

            for batchOffset in batches {
                request.fetchOffset = batchOffset
                request.fetchLimit = self.config.batchSize

                let batch = try context.fetch(request)
                updatedReport = try await batchProcessor(batch, updatedReport)

                // Update progress
                let progress = Double(batchOffset + batch.count) / Double(totalCount)
                await MainActor.run {
                    self.verificationProgress = progress * 0.25 // Each data type is 25% of total
                }
            }

            return updatedReport
        }
    }

    // MARK: - Batch Processors

    private func processVitalSignsBatch(_ batch: [NSManagedObject], report: IntegrityReport) async throws -> IntegrityReport {
        var updatedReport = report

        for object in batch {
            updatedReport.verifiedRecords += 1

            do {
                let isValid = try await verifyDataHash(for: object)
                if !isValid {
                    let corruptedRecord = CorruptedRecord(
                        id: object.objectID.uriRepresentation().absoluteString,
                        entityName: object.entity.name ?? "Unknown",
                        corruptionType: .hashMismatch,
                        detectedAt: Date()
                    )
                    updatedReport.corruptedRecords.append(corruptedRecord)

                    if config.enableAutomaticHealing {
                        try await healCorruptedRecord(object)
                        updatedReport.healedRecords.append(corruptedRecord.id)
                    }
                }
            } catch {
                updatedReport.errors.append("Verification failed for vital signs record: \(error.localizedDescription)")
            }
        }

        return updatedReport
    }

    private func processActivityDataBatch(_ batch: [NSManagedObject], report: IntegrityReport) async throws -> IntegrityReport {
        var updatedReport = report

        for object in batch {
            updatedReport.verifiedRecords += 1

            // Verify activity data integrity
            if let steps = object.value(forKey: "steps") as? Int, steps < 0 {
                let corruptedRecord = CorruptedRecord(
                    id: object.objectID.uriRepresentation().absoluteString,
                    entityName: "ActivityData",
                    corruptionType: .invalidValue,
                    detectedAt: Date()
                )
                updatedReport.corruptedRecords.append(corruptedRecord)
            }

            // Verify hash integrity
            do {
                let isValid = try await verifyDataHash(for: object)
                if !isValid {
                    let corruptedRecord = CorruptedRecord(
                        id: object.objectID.uriRepresentation().absoluteString,
                        entityName: "ActivityData",
                        corruptionType: .hashMismatch,
                        detectedAt: Date()
                    )
                    updatedReport.corruptedRecords.append(corruptedRecord)
                }
            } catch {
                updatedReport.errors.append("Hash verification failed: \(error.localizedDescription)")
            }
        }

        return updatedReport
    }

    private func processMedicalRecordsBatch(_ batch: [NSManagedObject], report: IntegrityReport) async throws -> IntegrityReport {
        var updatedReport = report

        for object in batch {
            updatedReport.verifiedRecords += 1

            // Verify medical record integrity with enhanced security
            do {
                let isValid = try await verifyDataHash(for: object)
                if !isValid {
                    // Medical records corruption is critical
                    let corruptedRecord = CorruptedRecord(
                        id: object.objectID.uriRepresentation().absoluteString,
                        entityName: "MedicalRecord",
                        corruptionType: .criticalCorruption,
                        detectedAt: Date()
                    )
                    updatedReport.corruptedRecords.append(corruptedRecord)

                    // Log critical corruption
                    await auditTrailService.logSystemEvent(
                        event: "critical_data_corruption",
                        details: "Medical record corruption detected: \(corruptedRecord.id)"
                    )
                }
            } catch {
                updatedReport.errors.append("Medical record verification failed: \(error.localizedDescription)")
            }
        }

        return updatedReport
    }

    private func processUserDataBatch(_ batch: [NSManagedObject], report: IntegrityReport) async throws -> IntegrityReport {
        var updatedReport = report

        for object in batch {
            updatedReport.verifiedRecords += 1

            do {
                let isValid = try await verifyDataHash(for: object)
                if !isValid {
                    let corruptedRecord = CorruptedRecord(
                        id: object.objectID.uriRepresentation().absoluteString,
                        entityName: "UserData",
                        corruptionType: .hashMismatch,
                        detectedAt: Date()
                    )
                    updatedReport.corruptedRecords.append(corruptedRecord)
                }
            } catch {
                updatedReport.errors.append("User data verification failed: \(error.localizedDescription)")
            }
        }

        return updatedReport
    }

    // MARK: - Corruption Handling

    private func handleIntegrityFailure(_ object: NSManagedObject, operation: DataOperation) async {
        let corruptedRecord = CorruptedRecord(
            id: object.objectID.uriRepresentation().absoluteString,
            entityName: object.entity.name ?? "Unknown",
            corruptionType: .hashMismatch,
            detectedAt: Date()
        )

        await MainActor.run {
            corruptedRecords.append(corruptedRecord)
        }

        // Log integrity failure
        await auditTrailService.logSystemEvent(
            event: "data_integrity_failure",
            details: "Integrity failure detected in \(object.entity.name ?? "unknown") during \(operation.rawValue)"
        )

        if config.enableAutomaticHealing {
            await healCorruptedRecord(object)
        }
    }

    /// Attempt to heal corrupted record
    private func healCorruptedRecord(_ object: NSManagedObject) async {
        do {
            // Try to regenerate integrity hash
            try await generateIntegrityHash(for: object)

            logger.info("Healed corrupted record: \(object.entity.name ?? "unknown")")

            await auditTrailService.logSystemEvent(
                event: "data_healing_success",
                details: "Successfully healed corrupted record in \(object.entity.name ?? "unknown")"
            )

        } catch {
            logger.error("Failed to heal corrupted record: \(error.localizedDescription)")

            await auditTrailService.logSystemEvent(
                event: "data_healing_failed",
                details: "Failed to heal corrupted record: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Continuous Verification

    private func startContinuousVerification() {
        Timer.publish(every: config.verificationInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.performScheduledVerification() }
            }
            .store(in: &cancellables)
    }

    private func performScheduledVerification() async {
        guard !isVerifying else { return }

        do {
            _ = try await performFullIntegrityCheck()
            logger.info("Scheduled integrity verification completed")
        } catch {
            logger.error("Scheduled integrity verification failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Interface

    /// Get current integrity status summary
    func getIntegrityStatusSummary() async -> IntegrityStatusSummary {
        return IntegrityStatusSummary(
            status: integrityStatus,
            lastVerification: lastVerificationDate,
            totalCorrupted: corruptedRecords.count,
            isHealthy: integrityStatus == .healthy,
            needsAttention: integrityStatus == .compromised || integrityStatus == .verificationFailed
        )
    }

    /// Force immediate integrity check
    func forceIntegrityCheck() async throws -> IntegrityReport {
        return try await performFullIntegrityCheck()
    }

    // MARK: - Helper Methods

    private func calculateAverageVerificationTime(_ report: IntegrityReport) -> TimeInterval {
        let currentTime = report.endTime.timeIntervalSince(report.startTime)

        if let stats = integrityStatistics {
            let totalTime = stats.averageVerificationTime * Double(stats.totalVerifications) + currentTime
            return totalTime / Double(stats.totalVerifications + 1)
        }

        return currentTime
    }
}

// MARK: - Supporting Models

/// Integrity status enumeration
enum IntegrityStatus: String, CaseIterable {
    case unknown = "unknown"
    case healthy = "healthy"
    case warningIssues = "warning_issues"
    case compromised = "compromised"
    case verifying = "verifying"
    case verificationFailed = "verification_failed"
}

/// Integrity statistics
struct IntegrityStatistics: Codable {
    let lastVerification: Date
    let totalVerifications: Int
    let totalRecordsVerified: Int
    let totalCorruptionDetected: Int
    let totalRecordsHealed: Int
    let averageVerificationTime: TimeInterval
    let corruptionRate: Double
}

/// Integrity report
struct IntegrityReport {
    var startTime: Date
    var endTime: Date
    var totalRecords: Int
    var verifiedRecords: Int
    var corruptedRecords: [CorruptedRecord]
    var healedRecords: [String]
    var errors: [String]
}

/// Corrupted record information
struct CorruptedRecord: Identifiable, Codable {
    let id: String
    let entityName: String
    let corruptionType: CorruptionType
    let detectedAt: Date
}

/// Corruption types
enum CorruptionType: String, Codable {
    case hashMismatch = "hash_mismatch"
    case invalidValue = "invalid_value"
    case missingData = "missing_data"
    case criticalCorruption = "critical_corruption"
}

/// Integrity status summary
struct IntegrityStatusSummary {
    let status: IntegrityStatus
    let lastVerification: Date?
    let totalCorrupted: Int
    let isHealthy: Bool
    let needsAttention: Bool
}