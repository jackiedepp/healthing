//
//  AuditTrailService.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import CoreData
import Combine
import CryptoKit
import OSLog

/// Audit trail service for GDPR-compliant data modification tracking
/// Implements REQ-073: Audit trail for data modifications
/// Supports GDPR Article 30 (Records of Processing Activities) compliance
/// Provides immutable audit log with cryptographic integrity verification
@MainActor
final class AuditTrailService: ObservableObject {

    // MARK: - Singleton
    static let shared = AuditTrailService()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "AuditTrailService")
    private let dataStore = HealthDataStore.shared
    private let securityManager = SecurityManager.shared
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    @Published var isLoggingEnabled = true
    @Published var auditLogCount: Int = 0
    @Published var lastAuditDate: Date?

    // MARK: - Keys
    private let auditEnabledKey = "audit_trail_enabled"
    private let auditConfigKey = "audit_configuration"

    // MARK: - Audit Configuration
    private struct AuditConfiguration {
        let retentionPeriodDays: Int
        let logLevel: AuditLogLevel
        let enableIntegrityChecking: Bool
        let anonymizePersonalData: Bool

        static let `default` = AuditConfiguration(
            retentionPeriodDays: 2555, // 7 years for GDPR compliance
            logLevel: .all,
            enableIntegrityChecking: true,
            anonymizePersonalData: true
        )
    }

    private var auditConfig = AuditConfiguration.default

    // MARK: - Initialization
    private init() {
        loadAuditConfiguration()
        startAuditLogCountMonitoring()
    }

    // MARK: - Configuration Management

    private func loadAuditConfiguration() {
        isLoggingEnabled = userDefaults.bool(forKey: auditEnabledKey)

        if let configData = userDefaults.data(forKey: auditConfigKey),
           let config = try? JSONDecoder().decode(AuditConfiguration.self, from: configData) {
            auditConfig = config
        }

        logger.info("Audit trail loaded - Enabled: \(isLoggingEnabled)")
    }

    /// Update audit trail configuration
    func updateConfiguration(
        isEnabled: Bool,
        retentionPeriodDays: Int = 2555,
        logLevel: AuditLogLevel = .all,
        enableIntegrityChecking: Bool = true,
        anonymizePersonalData: Bool = true
    ) async {
        isLoggingEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: auditEnabledKey)

        auditConfig = AuditConfiguration(
            retentionPeriodDays: retentionPeriodDays,
            logLevel: logLevel,
            enableIntegrityChecking: enableIntegrityChecking,
            anonymizePersonalData: anonymizePersonalData
        )

        if let configData = try? JSONEncoder().encode(auditConfig) {
            userDefaults.set(configData, forKey: auditConfigKey)
        }

        // Log configuration change
        await logSystemEvent(
            event: "audit_configuration_updated",
            details: "Audit trail configuration updated - enabled: \(isEnabled)"
        )

        logger.info("Audit configuration updated")
    }

    // MARK: - Audit Logging

    /// Log data operation with full audit trail
    func logDataOperation(
        operation: DataOperation,
        dataType: String,
        recordId: String? = nil,
        userId: String? = nil,
        details: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        guard isLoggingEnabled else { return }

        let auditEntry = AuditEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            operation: operation,
            dataType: dataType,
            recordId: recordId,
            userId: userId ?? getCurrentUserId(),
            ipAddress: getDeviceIPAddress(),
            userAgent: getDeviceInfo(),
            details: details,
            metadata: metadata,
            sessionId: getCurrentSessionId(),
            appVersion: getAppVersion()
        )

        await persistAuditEntry(auditEntry)
    }

    /// Log user access event
    func logUserAccess(
        accessType: AccessType,
        resourceType: String,
        resourceId: String? = nil,
        success: Bool = true,
        failureReason: String? = nil
    ) async {
        guard isLoggingEnabled else { return }

        var metadata: [String: String] = [
            "access_type": accessType.rawValue,
            "success": "\(success)"
        ]

        if let failureReason = failureReason {
            metadata["failure_reason"] = failureReason
        }

        await logDataOperation(
            operation: .access,
            dataType: resourceType,
            recordId: resourceId,
            details: "User access: \(accessType.rawValue)",
            metadata: metadata
        )
    }

    /// Log authentication events
    func logAuthentication(
        event: AuthenticationEvent,
        method: AuthenticationMethod,
        success: Bool,
        details: String? = nil
    ) async {
        guard isLoggingEnabled else { return }

        let metadata: [String: String] = [
            "event": event.rawValue,
            "method": method.rawValue,
            "success": "\(success)",
            "device_id": getDeviceId()
        ]

        await logSystemEvent(
            event: "authentication_\(event.rawValue)",
            details: details ?? "Authentication \(event.rawValue) - \(method.rawValue)",
            metadata: metadata
        )
    }

    /// Log system events
    func logSystemEvent(
        event: String,
        details: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        guard isLoggingEnabled else { return }

        await logDataOperation(
            operation: .system,
            dataType: "system_event",
            details: details ?? event,
            metadata: metadata.merging(["event_type": event]) { current, _ in current }
        )
    }

    /// Log privacy-related events
    func logPrivacyEvent(
        event: PrivacyEvent,
        dataType: String? = nil,
        consentGiven: Bool? = nil,
        details: String? = nil
    ) async {
        var metadata: [String: String] = [
            "privacy_event": event.rawValue
        ]

        if let consent = consentGiven {
            metadata["consent_given"] = "\(consent)"
        }

        if let dataType = dataType {
            metadata["data_type"] = dataType
        }

        await logDataOperation(
            operation: .privacy,
            dataType: "privacy_event",
            details: details ?? "Privacy event: \(event.rawValue)",
            metadata: metadata
        )
    }

    // MARK: - Audit Entry Persistence

    private func persistAuditEntry(_ entry: AuditEntry) async {
        do {
            try await dataStore.performBackgroundTask { context in
                let auditLog = AuditLog(context: context)
                auditLog.id = entry.id
                auditLog.timestamp = entry.timestamp
                auditLog.operation = entry.operation.rawValue
                auditLog.dataType = entry.dataType
                auditLog.recordId = entry.recordId
                auditLog.userId = entry.userId
                auditLog.ipAddress = entry.ipAddress
                auditLog.userAgent = entry.userAgent
                auditLog.details = entry.details
                auditLog.sessionId = entry.sessionId
                auditLog.appVersion = entry.appVersion

                // Store metadata as JSON
                if !entry.metadata.isEmpty,
                   let metadataData = try? JSONSerialization.data(withJSONObject: entry.metadata) {
                    auditLog.metadata = metadataData
                }

                // Generate integrity hash if enabled
                if auditConfig.enableIntegrityChecking {
                    auditLog.integrityHash = try self.generateIntegrityHash(for: entry)
                }

                try context.save()
            }

            await MainActor.run {
                auditLogCount += 1
                lastAuditDate = Date()
            }

        } catch {
            logger.error("Failed to persist audit entry: \(error.localizedDescription)")
        }
    }

    /// Generate cryptographic integrity hash for audit entry
    private func generateIntegrityHash(for entry: AuditEntry) throws -> String {
        let hashInput = "\(entry.id)\(entry.timestamp.timeIntervalSince1970)\(entry.operation.rawValue)\(entry.dataType)\(entry.userId ?? "")\(entry.details ?? "")"

        let inputData = hashInput.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: inputData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Audit Trail Queries

    /// Get audit entries for specific user
    func getAuditEntries(
        for userId: String,
        dateRange: DateInterval? = nil,
        operations: [DataOperation] = [],
        limit: Int = 100
    ) async throws -> [AuditEntry] {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()

            var predicates: [NSPredicate] = [
                NSPredicate(format: "userId == %@", userId)
            ]

            if let dateRange = dateRange {
                predicates.append(
                    NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                               dateRange.start as CVarArg,
                               dateRange.end as CVarArg)
                )
            }

            if !operations.isEmpty {
                let operationStrings = operations.map { $0.rawValue }
                predicates.append(NSPredicate(format: "operation IN %@", operationStrings))
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            request.fetchLimit = limit

            let results = try context.fetch(request)
            return results.compactMap { self.convertToAuditEntry($0) }
        }
    }

    /// Get audit entries for specific data type
    func getAuditEntries(
        for dataType: String,
        dateRange: DateInterval? = nil,
        limit: Int = 100
    ) async throws -> [AuditEntry] {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()

            var predicates: [NSPredicate] = [
                NSPredicate(format: "dataType == %@", dataType)
            ]

            if let dateRange = dateRange {
                predicates.append(
                    NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                               dateRange.start as CVarArg,
                               dateRange.end as CVarArg)
                )
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            request.fetchLimit = limit

            let results = try context.fetch(request)
            return results.compactMap { self.convertToAuditEntry($0) }
        }
    }

    /// Get audit summary statistics
    func getAuditSummary(for dateRange: DateInterval) async throws -> AuditSummary {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
            request.predicate = NSPredicate(
                format: "timestamp >= %@ AND timestamp <= %@",
                dateRange.start as CVarArg,
                dateRange.end as CVarArg
            )

            let results = try context.fetch(request)

            var operationCounts: [DataOperation: Int] = [:]
            var dataTypeCounts: [String: Int] = [:]
            var userCounts: [String: Int] = [:]

            for log in results {
                if let operation = DataOperation(rawValue: log.operation ?? "") {
                    operationCounts[operation, default: 0] += 1
                }

                if let dataType = log.dataType {
                    dataTypeCounts[dataType, default: 0] += 1
                }

                if let userId = log.userId {
                    userCounts[userId, default: 0] += 1
                }
            }

            return AuditSummary(
                dateRange: dateRange,
                totalEntries: results.count,
                operationCounts: operationCounts,
                dataTypeCounts: dataTypeCounts,
                uniqueUsers: userCounts.count
            )
        }
    }

    // MARK: - Data Integrity Verification

    /// Verify integrity of audit entries
    func verifyAuditIntegrity(for dateRange: DateInterval) async throws -> AuditIntegrityReport {
        guard auditConfig.enableIntegrityChecking else {
            throw AuditError.integrityCheckingDisabled
        }

        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
            request.predicate = NSPredicate(
                format: "timestamp >= %@ AND timestamp <= %@ AND integrityHash != nil",
                dateRange.start as CVarArg,
                dateRange.end as CVarArg
            )

            let results = try context.fetch(request)
            var verifiedCount = 0
            var failedVerifications: [String] = []

            for log in results {
                if let entry = self.convertToAuditEntry(log),
                   let storedHash = log.integrityHash {
                    do {
                        let computedHash = try self.generateIntegrityHash(for: entry)
                        if computedHash == storedHash {
                            verifiedCount += 1
                        } else {
                            failedVerifications.append(entry.id)
                        }
                    } catch {
                        failedVerifications.append(entry.id)
                    }
                }
            }

            return AuditIntegrityReport(
                dateRange: dateRange,
                totalEntries: results.count,
                verifiedEntries: verifiedCount,
                failedVerifications: failedVerifications,
                integrityPercentage: results.count > 0 ? Double(verifiedCount) / Double(results.count) * 100 : 0
            )
        }
    }

    // MARK: - Data Cleanup

    /// Clean up old audit logs based on retention policy
    func cleanupAuditLogs(olderThan cutoffDate: Date) async throws -> Int {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as CVarArg)

            let results = try context.fetch(request)
            let count = results.count

            for log in results {
                context.delete(log)
            }

            try context.save()
            return count
        }
    }

    // MARK: - GDPR Compliance

    /// Export audit data for GDPR data portability
    func exportUserAuditData(for userId: String) async throws -> Data {
        let auditEntries = try await getAuditEntries(for: userId, limit: 10000)

        let exportData = AuditExportData(
            userId: userId,
            exportDate: Date(),
            entries: auditEntries
        )

        return try JSONEncoder().encode(exportData)
    }

    /// Delete all audit data for specific user (GDPR right to be forgotten)
    func deleteUserAuditData(for userId: String) async throws -> Int {
        return try await dataStore.performBackgroundTask { context in
            let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)

            let results = try context.fetch(request)
            let count = results.count

            for log in results {
                context.delete(log)
            }

            try context.save()
            return count
        }
    }

    // MARK: - Helper Methods

    private func convertToAuditEntry(_ auditLog: AuditLog) -> AuditEntry? {
        guard let id = auditLog.id,
              let timestamp = auditLog.timestamp,
              let operationString = auditLog.operation,
              let operation = DataOperation(rawValue: operationString),
              let dataType = auditLog.dataType else {
            return nil
        }

        var metadata: [String: String] = [:]
        if let metadataData = auditLog.metadata,
           let metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: String] {
            metadata = metadataDict
        }

        return AuditEntry(
            id: id,
            timestamp: timestamp,
            operation: operation,
            dataType: dataType,
            recordId: auditLog.recordId,
            userId: auditLog.userId,
            ipAddress: auditLog.ipAddress,
            userAgent: auditLog.userAgent,
            details: auditLog.details,
            metadata: metadata,
            sessionId: auditLog.sessionId,
            appVersion: auditLog.appVersion
        )
    }

    private func startAuditLogCountMonitoring() {
        Timer.publish(every: 300, on: .main, in: .common) // Every 5 minutes
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.updateAuditLogCount() }
            }
            .store(in: &cancellables)
    }

    private func updateAuditLogCount() async {
        do {
            let count = try await dataStore.performBackgroundTask { context in
                let request: NSFetchRequest<AuditLog> = AuditLog.fetchRequest()
                return try context.count(for: request)
            }

            await MainActor.run {
                auditLogCount = count
            }
        } catch {
            logger.error("Failed to update audit log count: \(error.localizedDescription)")
        }
    }

    // MARK: - Device Information

    private func getCurrentUserId() -> String {
        return securityManager.getCurrentUserId() ?? "anonymous"
    }

    private func getCurrentSessionId() -> String {
        return securityManager.getCurrentSessionId()
    }

    private func getDeviceIPAddress() -> String {
        return "127.0.0.1" // Would implement actual IP detection
    }

    private func getDeviceInfo() -> String {
        return "HealthingApp iOS/\(getAppVersion())"
    }

    private func getDeviceId() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Supporting Models

/// Audit entry data model
struct AuditEntry: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let operation: DataOperation
    let dataType: String
    let recordId: String?
    let userId: String?
    let ipAddress: String?
    let userAgent: String?
    let details: String?
    let metadata: [String: String]
    let sessionId: String?
    let appVersion: String?
}

/// Data operations for audit trail
enum DataOperation: String, CaseIterable, Codable {
    case create = "create"
    case read = "read"
    case update = "update"
    case delete = "delete"
    case export = "export"
    case import = "import"
    case access = "access"
    case system = "system"
    case privacy = "privacy"
    case security = "security"
    case modify = "modify"
}

/// Access types for audit logging
enum AccessType: String, Codable {
    case view = "view"
    case download = "download"
    case print = "print"
    case share = "share"
    case search = "search"
}

/// Authentication events
enum AuthenticationEvent: String, Codable {
    case login = "login"
    case logout = "logout"
    case lockApp = "lock_app"
    case unlockApp = "unlock_app"
    case biometricAuth = "biometric_auth"
}

/// Authentication methods
enum AuthenticationMethod: String, Codable {
    case faceId = "face_id"
    case touchId = "touch_id"
    case passcode = "passcode"
    case password = "password"
}

/// Privacy events
enum PrivacyEvent: String, Codable {
    case consentGiven = "consent_given"
    case consentRevoked = "consent_revoked"
    case dataExported = "data_exported"
    case dataDeleted = "data_deleted"
    case privacySettingsChanged = "privacy_settings_changed"
}

/// Audit log levels
enum AuditLogLevel: String, Codable {
    case minimal = "minimal"
    case standard = "standard"
    case detailed = "detailed"
    case all = "all"
}

/// Audit summary
struct AuditSummary {
    let dateRange: DateInterval
    let totalEntries: Int
    let operationCounts: [DataOperation: Int]
    let dataTypeCounts: [String: Int]
    let uniqueUsers: Int
}

/// Audit integrity report
struct AuditIntegrityReport {
    let dateRange: DateInterval
    let totalEntries: Int
    let verifiedEntries: Int
    let failedVerifications: [String]
    let integrityPercentage: Double
}

/// Audit export data for GDPR compliance
struct AuditExportData: Codable {
    let userId: String
    let exportDate: Date
    let entries: [AuditEntry]
}

/// Audit errors
enum AuditError: Error {
    case integrityCheckingDisabled
    case invalidEntry
    case persistenceFailure(String)
}

// MARK: - Core Data Extension

extension AuditConfiguration: Codable {}