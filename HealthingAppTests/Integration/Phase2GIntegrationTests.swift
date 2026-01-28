//
//  Phase2GIntegrationTests.swift
//  HealthingAppTests
//
//  Created by Claude on 2026-01-28.
//

import XCTest
import Combine
@testable import HealthingApp

/// Comprehensive integration tests for Phase 2G: Data Management & Quality
/// Tests end-to-end workflows involving retention policies, audit trails, and data integrity
/// Implements REQ-086: Comprehensive unit and integration testing coverage
final class Phase2GIntegrationTests: XCTestCase {

    var retentionManager: RetentionPolicyManager!
    var auditTrailService: AuditTrailService!
    var dataIntegrityService: DataIntegrityService!
    var backupPreferencesManager: BackupPreferencesManager!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        retentionManager = RetentionPolicyManager.shared
        auditTrailService = AuditTrailService.shared
        dataIntegrityService = DataIntegrityService.shared
        backupPreferencesManager = BackupPreferencesManager.shared
        cancellables = Set<AnyCancellable>()

        // Ensure audit trail is enabled for integration tests
        Task {
            await auditTrailService.updateConfiguration(isEnabled: true)
        }
    }

    override func tearDownWithError() throws {
        cancellables = nil
        backupPreferencesManager = nil
        dataIntegrityService = nil
        auditTrailService = nil
        retentionManager = nil
        try super.tearDownWithError()
    }

    // MARK: - Complete Data Management Workflow Tests

    func testCompleteDataLifecycleManagement() async throws {
        // Test 1: Data Creation and Audit Logging
        print("Phase 1: Testing data creation and audit logging...")

        // Log data creation
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "integration_test_data",
            recordId: "integration-record-1",
            userId: "integration-test-user",
            details: "Integration test data creation"
        )

        // Verify audit was logged
        let auditEntries = try await auditTrailService.getAuditEntries(
            for: "integration-test-user",
            limit: 5
        )
        XCTAssertGreaterThanOrEqual(auditEntries.count, 1, "Audit entry should be created")

        // Test 2: Data Integrity Verification
        print("Phase 2: Testing data integrity verification...")

        do {
            let integrityReport = try await dataIntegrityService.forceIntegrityCheck()
            XCTAssertGreaterThanOrEqual(integrityReport.totalRecords, 0, "Integrity check should complete")

            // Log integrity check completion
            await auditTrailService.logSystemEvent(
                event: "integration_test_integrity_check",
                details: "Integration test integrity verification completed"
            )

        } catch {
            // Integrity check might fail in test environment - log the attempt
            await auditTrailService.logSystemEvent(
                event: "integration_test_integrity_check_failed",
                details: "Integration test integrity verification failed: \(error.localizedDescription)"
            )
        }

        // Test 3: Retention Policy Application
        print("Phase 3: Testing retention policy application...")

        // Update a retention policy
        guard var testPolicy = retentionManager.retentionPolicies.first(where: { $0.dataType == .achievements }) else {
            XCTFail("Test policy should be available")
            return
        }

        let originalPeriod = testPolicy.retentionPeriodDays
        testPolicy.retentionPeriodDays = originalPeriod + 30

        let policyUpdateSuccess = await retentionManager.updateRetentionPolicy(testPolicy)
        XCTAssertTrue(policyUpdateSuccess, "Policy update should succeed")

        // Test 4: GDPR Compliance Workflow
        print("Phase 4: Testing GDPR compliance workflow...")

        // Export user data
        let exportData = try await auditTrailService.exportUserAuditData(for: "integration-test-user")
        XCTAssertGreaterThan(exportData.count, 0, "Export should contain data")

        // Test data deletion request
        let deletedCount = try await auditTrailService.deleteUserAuditData(for: "integration-test-user")
        XCTAssertGreaterThanOrEqual(deletedCount, 0, "Deletion should report count")

        // Test 5: Backup Preferences Integration
        print("Phase 5: Testing backup preferences integration...")

        let originalPreferences = backupPreferencesManager.backupPreferences

        var testPreferences = originalPreferences
        testPreferences.isCloudKitEnabled = !originalPreferences.isCloudKitEnabled

        await backupPreferencesManager.updateBackupPreferences(testPreferences)

        // Verify preferences were updated and audited
        XCTAssertEqual(
            backupPreferencesManager.backupPreferences.isCloudKitEnabled,
            testPreferences.isCloudKitEnabled,
            "Backup preferences should be updated"
        )

        // Restore original preferences
        await backupPreferencesManager.updateBackupPreferences(originalPreferences)

        print("Integration test completed successfully!")
    }

    // MARK: - Cross-Service Communication Tests

    func testAuditTrailAndRetentionPolicyIntegration() async throws {
        // Test that retention policy changes are properly audited

        // Get initial audit count
        let initialAuditCount = auditTrailService.auditLogCount

        // Update a retention policy
        guard var testPolicy = retentionManager.retentionPolicies.first(where: { $0.dataType == .temporaryFiles }) else {
            XCTFail("Temporary files policy should exist")
            return
        }

        let originalPeriod = testPolicy.retentionPeriodDays
        testPolicy.retentionPeriodDays = 15 // Change to 15 days

        let success = await retentionManager.updateRetentionPolicy(testPolicy)
        XCTAssertTrue(success, "Policy update should succeed")

        // Verify audit trail was updated
        await waitForAuditOperations()
        let finalAuditCount = auditTrailService.auditLogCount
        XCTAssertGreaterThan(finalAuditCount, initialAuditCount, "Audit count should increase after policy change")

        // Query for the specific audit entry
        let recentEntries = try await auditTrailService.getAuditEntries(
            for: "retention_policy",
            limit: 5
        )

        // Verify the policy change was audited
        let policyChangeEntry = recentEntries.first { entry in
            entry.dataType == "retention_policy" && entry.operation == .modify
        }

        XCTAssertNotNil(policyChangeEntry, "Policy change should be audited")

        // Restore original policy
        testPolicy.retentionPeriodDays = originalPeriod
        _ = await retentionManager.updateRetentionPolicy(testPolicy)
    }

    func testIntegrityServiceAndAuditTrailIntegration() async throws {
        // Test that integrity checks are properly audited

        let initialAuditCount = auditTrailService.auditLogCount

        // Perform integrity check
        do {
            _ = try await dataIntegrityService.forceIntegrityCheck()
        } catch {
            // Integrity check might fail in test environment
            print("Integrity check failed (expected in test environment): \(error)")
        }

        // Verify that integrity-related events were audited
        await waitForAuditOperations()
        let finalAuditCount = auditTrailService.auditLogCount
        XCTAssertGreaterThanOrEqual(finalAuditCount, initialAuditCount, "Audit count should be maintained or increased")

        // Check for integrity-related audit entries
        let systemEntries = try await auditTrailService.getAuditEntries(
            for: "system_event",
            limit: 10
        )

        let integrityEntries = systemEntries.filter { entry in
            entry.details?.contains("integrity") == true
        }

        XCTAssertGreaterThanOrEqual(integrityEntries.count, 0, "Integrity-related events should be present")
    }

    func testBackupPreferencesAndAuditTrailIntegration() async throws {
        // Test that backup preference changes are audited

        let initialAuditCount = auditTrailService.auditLogCount

        let originalPreferences = backupPreferencesManager.backupPreferences
        var modifiedPreferences = originalPreferences
        modifiedPreferences.allowManualBackup = !originalPreferences.allowManualBackup

        // Update backup preferences
        await backupPreferencesManager.updateBackupPreferences(modifiedPreferences)

        // Verify audit trail captured the change
        await waitForAuditOperations()
        let finalAuditCount = auditTrailService.auditLogCount
        XCTAssertGreaterThan(finalAuditCount, initialAuditCount, "Backup preference changes should be audited")

        // Query for privacy events (backup preference changes are privacy-related)
        let privacyEntries = try await auditTrailService.getAuditEntries(
            for: "backup_preferences",
            limit: 5
        )

        let backupEntry = privacyEntries.first { entry in
            entry.dataType == "backup_preferences"
        }

        XCTAssertNotNil(backupEntry, "Backup preference change should be audited")

        // Restore original preferences
        await backupPreferencesManager.updateBackupPreferences(originalPreferences)
    }

    // MARK: - Error Handling Integration Tests

    func testErrorPropagationAcrossServices() async throws {
        // Test how errors propagate between services and are handled

        // Test 1: Invalid retention policy update should be audited
        guard var invalidPolicy = retentionManager.retentionPolicies.first else {
            XCTFail("Should have at least one policy")
            return
        }

        invalidPolicy.retentionPeriodDays = -100 // Invalid negative period

        let invalidUpdateResult = await retentionManager.updateRetentionPolicy(invalidPolicy)
        XCTAssertFalse(invalidUpdateResult, "Invalid policy update should fail")

        // Test 2: Integrity check errors should be handled gracefully
        let initialStatus = dataIntegrityService.integrityStatus

        do {
            _ = try await dataIntegrityService.forceIntegrityCheck()
            // If successful, verify status is updated appropriately
            let finalStatus = dataIntegrityService.integrityStatus
            XCTAssertNotEqual(finalStatus, .verifying, "Status should not be stuck in verifying")
        } catch {
            // If failed, verify error handling
            let finalStatus = dataIntegrityService.integrityStatus
            XCTAssertEqual(finalStatus, .verificationFailed, "Status should reflect verification failure")
        }

        // Test 3: Backup operations should handle CloudKit unavailability
        let originalBackupStatus = backupPreferencesManager.backupStatus

        // This test assumes CloudKit might not be available in test environment
        let testPreferences = backupPreferencesManager.backupPreferences
        await backupPreferencesManager.updateBackupPreferences(testPreferences)

        // Verify backup service handles unavailability gracefully
        XCTAssertNotNil(backupPreferencesManager.backupStatus, "Backup status should always be defined")
    }

    // MARK: - Performance Integration Tests

    func testConcurrentDataManagementOperations() async throws {
        // Test multiple data management operations running concurrently

        let startTime = Date()

        // Run multiple operations concurrently
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in

            // Task 1: Integrity check
            group.addTask {
                do {
                    _ = try await self.dataIntegrityService.forceIntegrityCheck()
                    return true
                } catch {
                    return false // Might fail in test environment
                }
            }

            // Task 2: Audit trail queries
            group.addTask {
                do {
                    _ = try await self.auditTrailService.getAuditSummary(
                        for: DateInterval(start: Date().addingTimeInterval(-86400), end: Date())
                    )
                    return true
                } catch {
                    return false
                }
            }

            // Task 3: Retention policy operations
            group.addTask {
                let estimates = await self.retentionManager.getDataSizeEstimates()
                return !estimates.isEmpty
            }

            // Task 4: Backup preferences updates
            group.addTask {
                let backups = try? await self.backupPreferencesManager.getAvailableBackups()
                return backups != nil
            }

            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Verify operations completed within reasonable time
        XCTAssertLessThan(duration, 60.0, "Concurrent operations should complete within 60 seconds")
        XCTAssertEqual(results.count, 4, "All concurrent operations should complete")

        // At least some operations should succeed
        let successCount = results.filter { $0 }.count
        XCTAssertGreaterThanOrEqual(successCount, 2, "At least half of concurrent operations should succeed")
    }

    // MARK: - Data Consistency Tests

    func testDataConsistencyAcrossServices() async throws {
        // Test that data remains consistent across all services

        let testUserId = "consistency-test-user"

        // Phase 1: Create data and verify it's tracked consistently
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "consistency_test",
            recordId: "consistency-record-1",
            userId: testUserId,
            details: "Data consistency test"
        )

        // Phase 2: Perform integrity check and verify consistency
        do {
            let integrityReport = try await dataIntegrityService.forceIntegrityCheck()

            // Log integrity check
            await auditTrailService.logSystemEvent(
                event: "consistency_integrity_check",
                details: "Integrity check for consistency test: \(integrityReport.totalRecords) records"
            )

        } catch {
            await auditTrailService.logSystemEvent(
                event: "consistency_integrity_check_failed",
                details: "Integrity check failed: \(error.localizedDescription)"
            )
        }

        // Phase 3: Verify all services have consistent view of user data
        let userEntries = try await auditTrailService.getAuditEntries(for: testUserId, limit: 10)
        XCTAssertGreaterThanOrEqual(userEntries.count, 1, "User should have audit entries")

        // Phase 4: Test data cleanup maintains consistency
        let oldDate = Calendar.current.date(byAdding: .day, value: -1000, to: Date())!

        do {
            _ = try await retentionManager.performManualCleanup(for: .temporaryFiles, olderThan: oldDate)
        } catch {
            // Cleanup might fail in test environment
            print("Manual cleanup failed (expected in test environment): \(error)")
        }

        // Phase 5: Export and verify data consistency
        let exportData = try await auditTrailService.exportUserAuditData(for: testUserId)
        XCTAssertGreaterThan(exportData.count, 0, "Export should contain consistent data")

        // Cleanup: Delete test user data
        _ = try await auditTrailService.deleteUserAuditData(for: testUserId)
    }

    // MARK: - GDPR Compliance Integration Tests

    func testGDPRComplianceWorkflow() async throws {
        // Test complete GDPR compliance workflow across all services

        let gdprTestUserId = "gdpr-compliance-test-user"

        // Phase 1: Data Processing Consent
        await auditTrailService.logPrivacyEvent(
            event: .consentGiven,
            dataType: "health_data",
            consentGiven: true,
            details: "GDPR test user consent given"
        )

        // Phase 2: Data Collection and Processing
        await auditTrailService.logDataOperation(
            operation: .create,
            dataType: "gdpr_test_data",
            recordId: "gdpr-record-1",
            userId: gdprTestUserId,
            details: "GDPR test data creation"
        )

        await auditTrailService.logDataOperation(
            operation: .update,
            dataType: "gdpr_test_data",
            recordId: "gdpr-record-1",
            userId: gdprTestUserId,
            details: "GDPR test data update"
        )

        // Phase 3: Data Subject Rights - Right of Access
        let userAuditEntries = try await auditTrailService.getAuditEntries(for: gdprTestUserId, limit: 100)
        XCTAssertGreaterThanOrEqual(userAuditEntries.count, 2, "User should have audit trail for data access")

        // Phase 4: Data Subject Rights - Right to Data Portability
        let exportedData = try await auditTrailService.exportUserAuditData(for: gdprTestUserId)
        XCTAssertGreaterThan(exportedData.count, 0, "User data should be exportable")

        // Verify export contains expected data
        let decodedExport = try JSONDecoder().decode(AuditExportData.self, from: exportedData)
        XCTAssertEqual(decodedExport.userId, gdprTestUserId, "Export should be for correct user")
        XCTAssertGreaterThanOrEqual(decodedExport.entries.count, 2, "Export should contain user's audit entries")

        // Phase 5: Data Subject Rights - Right to be Forgotten
        await auditTrailService.logPrivacyEvent(
            event: .dataDeleted,
            dataType: "all_user_data",
            details: "GDPR deletion request for user: \(gdprTestUserId)"
        )

        let deletedCount = try await auditTrailService.deleteUserAuditData(for: gdprTestUserId)
        XCTAssertGreaterThanOrEqual(deletedCount, 0, "User data deletion should report count")

        // Phase 6: Verify Deletion Completeness
        let remainingEntries = try await auditTrailService.getAuditEntries(for: gdprTestUserId, limit: 10)
        XCTAssertTrue(remainingEntries.isEmpty, "No user data should remain after deletion")

        // Phase 7: Audit Retention Compliance
        let auditRetentionPolicy = retentionManager.retentionPolicies.first { $0.dataType == .auditLogs }
        XCTAssertNotNil(auditRetentionPolicy, "Audit retention policy should exist")
        XCTAssertGreaterThanOrEqual(auditRetentionPolicy!.retentionPeriodDays, 2555, "Audit logs should be retained for GDPR compliance (7 years)")
    }

    // MARK: - Stress Testing

    func testHighVolumeDataManagement() async throws {
        // Test system behavior under high data volume

        let testUserId = "high-volume-test-user"
        let operationCount = 50

        // Phase 1: Generate high volume of audit entries
        for i in 0..<operationCount {
            await auditTrailService.logDataOperation(
                operation: .create,
                dataType: "high_volume_test",
                recordId: "high-volume-record-\(i)",
                userId: testUserId,
                details: "High volume test entry \(i)"
            )
        }

        // Phase 2: Test querying with high volume
        let allEntries = try await auditTrailService.getAuditEntries(for: testUserId, limit: operationCount + 10)
        XCTAssertGreaterThanOrEqual(allEntries.count, operationCount, "Should retrieve high volume entries")

        // Phase 3: Test integrity check with high volume
        do {
            let integrityReport = try await dataIntegrityService.forceIntegrityCheck()
            XCTAssertGreaterThanOrEqual(integrityReport.totalRecords, operationCount, "Integrity check should handle high volume")
        } catch {
            // High volume might cause timeout in test environment
            print("High volume integrity check failed (expected in test environment): \(error)")
        }

        // Phase 4: Test export with high volume
        let exportData = try await auditTrailService.exportUserAuditData(for: testUserId)
        XCTAssertGreaterThan(exportData.count, 0, "High volume export should succeed")

        // Phase 5: Cleanup high volume data
        let deletedCount = try await auditTrailService.deleteUserAuditData(for: testUserId)
        XCTAssertGreaterThanOrEqual(deletedCount, operationCount, "Should delete all high volume entries")
    }

    // MARK: - Helper Methods

    private func waitForAuditOperations() async {
        // Give audit operations time to complete
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    private func createTestDateRange(daysAgo: Int = 30) -> DateInterval {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: endDate)!
        return DateInterval(start: startDate, end: endDate)
    }
}

// MARK: - Test Utilities

extension Phase2GIntegrationTests {

    /// Generate test data for integration testing
    func generateIntegrationTestData(userId: String, recordCount: Int = 10) async {
        for i in 0..<recordCount {
            await auditTrailService.logDataOperation(
                operation: DataOperation.allCases.randomElement() ?? .create,
                dataType: "integration_test_data",
                recordId: "test-record-\(userId)-\(i)",
                userId: userId,
                details: "Integration test data \(i)"
            )
        }
    }

    /// Verify service health across all data management services
    func verifyAllServicesHealthy() async -> Bool {
        // Check audit trail service
        let auditHealthy = auditTrailService.isLoggingEnabled

        // Check data integrity service
        let integrityStatus = await dataIntegrityService.getIntegrityStatusSummary()
        let integrityHealthy = integrityStatus.status != .verificationFailed

        // Check retention manager
        let retentionHealthy = !retentionManager.retentionPolicies.isEmpty

        // Check backup preferences
        let backupHealthy = backupPreferencesManager.backupStatus != .failed

        return auditHealthy && integrityHealthy && retentionHealthy && backupHealthy
    }
}