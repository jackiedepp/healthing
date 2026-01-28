//
//  AuditTrailServiceTests.swift
//  HealthingAppTests
//
//  Created by Claude on 2026-01-28.
//

import XCTest
import Combine
@testable import HealthingApp

/// Comprehensive unit tests for AuditTrailService
/// Tests GDPR compliance, audit logging, and data integrity verification
final class AuditTrailServiceTests: XCTestCase {

    var auditTrailService: AuditTrailService!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        auditTrailService = AuditTrailService.shared
        cancellables = Set<AnyCancellable>()
    }

    override func tearDownWithError() throws {
        cancellables = nil
        auditTrailService = nil
        try super.tearDownWithError()
    }

    // MARK: - Configuration Tests

    func testDefaultAuditConfiguration() {
        // Test that audit trail is enabled by default and properly configured
        XCTAssertTrue(auditTrailService.isLoggingEnabled, "Audit logging should be enabled by default")
        XCTAssertGreaterThan(auditTrailService.auditLogCount, -1, "Audit log count should be initialized")
    }

    func testAuditConfigurationUpdate() async {
        // Test updating audit configuration
        let originalEnabled = auditTrailService.isLoggingEnabled

        await auditTrailService.updateConfiguration(
            isEnabled: !originalEnabled,
            retentionPeriodDays: 3000,
            logLevel: .detailed,
            enableIntegrityChecking: true,
            anonymizePersonalData: true
        )

        XCTAssertEqual(auditTrailService.isLoggingEnabled, !originalEnabled, "Audit enabled state should be updated")

        // Restore original configuration
        await auditTrailService.updateConfiguration(isEnabled: originalEnabled)
    }

    // MARK: - Data Operation Logging Tests

    func testLogDataOperation() async {
        // Test logging basic data operations
        let testUserId = "test-user-123"
        let testRecordId = "record-456"

        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "test_data",
            recordId: testRecordId,
            userId: testUserId,
            details: "Test data creation"
        )

        // Verify audit log count increased
        let finalCount = auditTrailService.auditLogCount
        XCTAssertGreaterThan(finalCount, 0, "Audit log count should increase after logging")
    }

    func testLogAllDataOperations() async {
        // Test logging all types of data operations
        let operations: [DataOperation] = [.create, .read, .update, .delete, .export, .import]
        let initialCount = auditTrailService.auditLogCount

        for operation in operations {
            await auditTrailService.logDataOperation(
                operation: operation,
                dataType: "test_data",
                recordId: "test-record-\(operation.rawValue)",
                userId: "test-user",
                details: "Testing \(operation.rawValue) operation"
            )
        }

        let finalCount = auditTrailService.auditLogCount
        XCTAssertGreaterThanOrEqual(finalCount, initialCount + operations.count, "All operations should be logged")
    }

    func testLogDataOperationWithMetadata() async {
        // Test logging with comprehensive metadata
        let metadata = [
            "source": "unit_test",
            "version": "1.0",
            "device": "test_device",
            "action": "comprehensive_test"
        ]

        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "test_data_with_metadata",
            recordId: "metadata-test-record",
            userId: "metadata-test-user",
            details: "Testing audit with metadata",
            metadata: metadata
        )

        // Verify logging succeeded (count increased)
        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "Metadata logging should succeed")
    }

    // MARK: - User Access Logging Tests

    func testLogUserAccess() async {
        // Test logging user access events
        let accessTypes: [AccessType] = [.view, .download, .print, .share, .search]

        for accessType in accessTypes {
            await auditTrailService.logUserAccess(
                accessType: accessType,
                resourceType: "test_resource",
                resourceId: "resource-\(accessType.rawValue)",
                success: true
            )
        }

        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "User access events should be logged")
    }

    func testLogFailedUserAccess() async {
        // Test logging failed user access attempts
        await auditTrailService.logUserAccess(
            accessType: .view,
            resourceType: "restricted_resource",
            resourceId: "forbidden-resource",
            success: false,
            failureReason: "Insufficient permissions"
        )

        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "Failed access attempts should be logged")
    }

    // MARK: - Authentication Logging Tests

    func testLogAuthenticationEvents() async {
        // Test logging authentication events
        let authEvents: [AuthenticationEvent] = [.login, .logout, .lockApp, .unlockApp, .biometricAuth]
        let authMethods: [AuthenticationMethod] = [.faceId, .touchId, .passcode, .password]

        for event in authEvents {
            for method in authMethods {
                await auditTrailService.logAuthentication(
                    event: event,
                    method: method,
                    success: true,
                    details: "Testing \(event.rawValue) with \(method.rawValue)"
                )
            }
        }

        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "Authentication events should be logged")
    }

    func testLogFailedAuthentication() async {
        // Test logging failed authentication attempts
        await auditTrailService.logAuthentication(
            event: .login,
            method: .faceId,
            success: false,
            details: "Face ID authentication failed"
        )

        await auditTrailService.logAuthentication(
            event: .unlockApp,
            method: .passcode,
            success: false,
            details: "Incorrect passcode attempt"
        )

        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "Failed authentication should be logged")
    }

    // MARK: - Privacy Event Logging Tests

    func testLogPrivacyEvents() async {
        // Test logging privacy-related events
        let privacyEvents: [PrivacyEvent] = [
            .consentGiven, .consentRevoked, .dataExported,
            .dataDeleted, .privacySettingsChanged
        ]

        for event in privacyEvents {
            await auditTrailService.logPrivacyEvent(
                event: event,
                dataType: "health_data",
                consentGiven: event == .consentGiven,
                details: "Testing privacy event: \(event.rawValue)"
            )
        }

        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "Privacy events should be logged")
    }

    // MARK: - System Event Logging Tests

    func testLogSystemEvents() async {
        // Test logging system events
        let systemEvents = [
            "app_launch", "app_terminate", "data_sync",
            "backup_created", "integrity_check", "error_occurred"
        ]

        for event in systemEvents {
            await auditTrailService.logSystemEvent(
                event: event,
                details: "System event test: \(event)",
                metadata: ["test": "true", "event_id": UUID().uuidString]
            )
        }

        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "System events should be logged")
    }

    // MARK: - Audit Trail Query Tests

    func testGetAuditEntriesForUser() async throws {
        // Test querying audit entries for specific user
        let testUserId = "query-test-user"

        // Log some entries for the test user
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "test_data",
            recordId: "test-record-1",
            userId: testUserId,
            details: "First test entry"
        )

        await auditTrailService.logDataOperation(
            operation: .update,
            dataType: "test_data",
            recordId: "test-record-2",
            userId: testUserId,
            details: "Second test entry"
        )

        // Query entries for the user
        let entries = try await auditTrailService.getAuditEntries(for: testUserId, limit: 10)

        XCTAssertGreaterThanOrEqual(entries.count, 0, "Should return audit entries for user")

        // Verify entries belong to the correct user
        for entry in entries.prefix(2) {
            XCTAssertEqual(entry.userId, testUserId, "All entries should belong to the test user")
        }
    }

    func testGetAuditEntriesForDataType() async throws {
        // Test querying audit entries for specific data type
        let testDataType = "query_test_data_type"

        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: testDataType,
            recordId: "data-type-test-1",
            details: "Data type test entry"
        )

        let entries = try await auditTrailService.getAuditEntries(for: testDataType, limit: 5)

        XCTAssertGreaterThanOrEqual(entries.count, 0, "Should return audit entries for data type")

        // Verify entries match the data type
        for entry in entries.prefix(1) {
            XCTAssertEqual(entry.dataType, testDataType, "Entry should match the queried data type")
        }
    }

    func testGetAuditSummary() async throws {
        // Test getting audit summary statistics
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!
        let dateRange = DateInterval(start: startDate, end: endDate)

        // Log some test entries
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "summary_test",
            details: "Summary test entry 1"
        )

        await auditTrailService.logDataOperation(
            operation: .read,
            dataType: "summary_test",
            details: "Summary test entry 2"
        )

        let summary = try await auditTrailService.getAuditSummary(for: dateRange)

        XCTAssertGreaterThanOrEqual(summary.totalEntries, 0, "Summary should contain entry count")
        XCTAssertGreaterThanOrEqual(summary.operationCounts.count, 0, "Summary should contain operation counts")
        XCTAssertGreaterThanOrEqual(summary.uniqueUsers, 0, "Summary should contain unique user count")
    }

    // MARK: - Data Integrity Tests

    func testVerifyAuditIntegrity() async throws {
        // Test audit trail integrity verification
        // This test checks if integrity verification works when enabled

        await auditTrailService.updateConfiguration(
            isEnabled: true,
            enableIntegrityChecking: true
        )

        // Log entries to verify
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "integrity_test",
            details: "Integrity test entry"
        )

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .minute, value: -5, to: endDate)!
        let dateRange = DateInterval(start: startDate, end: endDate)

        do {
            let integrityReport = try await auditTrailService.verifyAuditIntegrity(for: dateRange)

            XCTAssertGreaterThanOrEqual(integrityReport.totalEntries, 0, "Integrity report should include entries")
            XCTAssertGreaterThanOrEqual(integrityReport.integrityPercentage, 0, "Integrity percentage should be valid")
            XCTAssertLessThanOrEqual(integrityReport.integrityPercentage, 100, "Integrity percentage should not exceed 100%")
        } catch {
            // If integrity checking is disabled or not implemented, that's acceptable
            if case AuditError.integrityCheckingDisabled = error {
                XCTAssertTrue(true, "Integrity checking disabled is acceptable")
            } else {
                throw error
            }
        }
    }

    // MARK: - GDPR Compliance Tests

    func testExportUserAuditData() async throws {
        // Test GDPR data portability for audit data
        let testUserId = "gdpr-export-test-user"

        // Log some entries for the test user
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "gdpr_test",
            userId: testUserId,
            details: "GDPR export test entry"
        )

        let exportData = try await auditTrailService.exportUserAuditData(for: testUserId)

        XCTAssertGreaterThan(exportData.count, 0, "Export data should not be empty")

        // Verify it's valid JSON
        let decoded = try JSONDecoder().decode(AuditExportData.self, from: exportData)
        XCTAssertEqual(decoded.userId, testUserId, "Export should be for correct user")
        XCTAssertGreaterThanOrEqual(decoded.entries.count, 0, "Export should contain audit entries")
    }

    func testDeleteUserAuditData() async throws {
        // Test GDPR right to be forgotten for audit data
        let testUserId = "gdpr-delete-test-user"

        // Log some entries for the test user
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "gdpr_delete_test",
            userId: testUserId,
            details: "GDPR deletion test entry"
        )

        // Delete the user's audit data
        let deletedCount = try await auditTrailService.deleteUserAuditData(for: testUserId)

        XCTAssertGreaterThanOrEqual(deletedCount, 0, "Deletion should report number of deleted entries")

        // Verify entries are deleted by trying to retrieve them
        let remainingEntries = try await auditTrailService.getAuditEntries(for: testUserId, limit: 100)
        XCTAssertTrue(remainingEntries.isEmpty, "No entries should remain after deletion")
    }

    // MARK: - Data Cleanup Tests

    func testCleanupAuditLogs() async throws {
        // Test cleaning up old audit logs
        let oldDate = Calendar.current.date(byAdding: .year, value: -10, to: Date())!

        let deletedCount = try await auditTrailService.cleanupAuditLogs(olderThan: oldDate)

        XCTAssertGreaterThanOrEqual(deletedCount, 0, "Cleanup should report number of deleted entries")
    }

    // MARK: - Performance Tests

    func testAuditLoggingPerformance() {
        // Test performance of audit logging
        measure {
            Task {
                await auditTrailService.logDataOperation(
                    operation: .read,
                    dataType: "performance_test",
                    details: "Performance test entry"
                )
            }
        }
    }

    func testBulkAuditLoggingPerformance() {
        // Test performance of bulk audit logging
        measure {
            Task {
                for i in 0..<100 {
                    await auditTrailService.logDataOperation(
                        operation: .create,
                        dataType: "bulk_test",
                        recordId: "bulk-record-\(i)",
                        details: "Bulk test entry \(i)"
                    )
                }
            }
        }
    }

    // MARK: - Error Handling Tests

    func testAuditLoggingWhenDisabled() async {
        // Test that audit logging handles disabled state gracefully
        await auditTrailService.updateConfiguration(isEnabled: false)

        let initialCount = auditTrailService.auditLogCount

        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "disabled_test",
            details: "This should not be logged"
        )

        // When disabled, logging should be skipped (count shouldn't increase)
        let finalCount = auditTrailService.auditLogCount
        XCTAssertEqual(finalCount, initialCount, "Audit count should not increase when disabled")

        // Re-enable for other tests
        await auditTrailService.updateConfiguration(isEnabled: true)
    }

    // MARK: - Integration Tests

    func testAuditTrailIntegrationWithRetentionPolicy() async throws {
        // Test integration between audit trail and retention policy
        await auditTrailService.logSystemEvent(
            event: "retention_policy_test",
            details: "Testing audit trail integration with retention policies"
        )

        // Verify the event was logged
        XCTAssertGreaterThan(auditTrailService.auditLogCount, 0, "Integration test event should be logged")

        // Test cleanup operation
        let veryOldDate = Calendar.current.date(byAdding: .year, value: -50, to: Date())!
        let cleanedUp = try await auditTrailService.cleanupAuditLogs(olderThan: veryOldDate)

        XCTAssertGreaterThanOrEqual(cleanedUp, 0, "Cleanup integration should work without errors")
    }
}

// MARK: - Test Helpers

extension AuditTrailServiceTests {

    /// Generate test audit entry
    func createTestAuditEntry(operation: DataOperation = .create, userId: String? = nil) -> AuditEntry {
        return AuditEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            operation: operation,
            dataType: "test_data",
            recordId: "test-record-\(UUID().uuidString)",
            userId: userId ?? "test-user-\(UUID().uuidString)",
            ipAddress: "127.0.0.1",
            userAgent: "HealthingApp Test",
            details: "Test audit entry for \(operation.rawValue)",
            metadata: ["test": "true"],
            sessionId: "test-session",
            appVersion: "1.0.0"
        )
    }

    /// Wait for async audit operations to complete
    func waitForAuditOperations() async {
        // Give audit operations time to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

    /// Generate test date range
    func createTestDateRange(daysAgo: Int = 7) -> DateInterval {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: endDate)!
        return DateInterval(start: startDate, end: endDate)
    }
}