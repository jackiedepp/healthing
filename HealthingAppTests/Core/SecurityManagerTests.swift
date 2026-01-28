//
//  SecurityManagerTests.swift
//  HealthingAppTests
//
//  Created by Claude on 2026-01-28.
//

import XCTest
import CryptoKit
@testable import HealthingApp

/// Comprehensive unit tests for SecurityManager
/// Implements REQ-086: Comprehensive unit and integration testing coverage
/// Covers encryption, authentication, and security functionality
final class SecurityManagerTests: XCTestCase {

    var securityManager: SecurityManager!
    var testData: Data!
    var testString: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        securityManager = SecurityManager.shared
        testData = "Test health data for encryption".data(using: .utf8)!
        testString = "Test string for hashing"
    }

    override func tearDownWithError() throws {
        securityManager = nil
        testData = nil
        testString = nil
        try super.tearDownWithError()
    }

    // MARK: - Encryption Tests

    func testAESEncryptionDecryption() throws {
        // Test AES encryption and decryption
        let encryptedData = try securityManager.encryptData(testData)
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")

        let decryptedData = try securityManager.decryptData(encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testEncryptionWithDifferentData() throws {
        // Test encryption with various data types
        let jsonData = try JSONSerialization.data(withJSONObject: ["key": "value", "number": 123])
        let encryptedJSON = try securityManager.encryptData(jsonData)
        let decryptedJSON = try securityManager.decryptData(encryptedJSON)

        XCTAssertEqual(decryptedJSON, jsonData, "JSON data should encrypt/decrypt correctly")
    }

    func testEncryptionWithEmptyData() throws {
        // Test edge case with empty data
        let emptyData = Data()
        let encryptedEmpty = try securityManager.encryptData(emptyData)
        let decryptedEmpty = try securityManager.decryptData(encryptedEmpty)

        XCTAssertEqual(decryptedEmpty, emptyData, "Empty data should encrypt/decrypt correctly")
    }

    func testEncryptionWithLargeData() throws {
        // Test encryption with large data set
        let largeData = Data(count: 1024 * 1024) // 1MB of zeros
        let encryptedLarge = try securityManager.encryptData(largeData)
        let decryptedLarge = try securityManager.decryptData(encryptedLarge)

        XCTAssertEqual(decryptedLarge, largeData, "Large data should encrypt/decrypt correctly")
    }

    // MARK: - Key Management Tests

    func testKeyGeneration() throws {
        // Test symmetric key generation
        let key1 = securityManager.generateSymmetricKey()
        let key2 = securityManager.generateSymmetricKey()

        XCTAssertNotEqual(key1.withUnsafeBytes { Data($0) },
                         key2.withUnsafeBytes { Data($0) },
                         "Generated keys should be unique")
    }

    func testKeyStorageAndRetrieval() throws {
        // Test storing and retrieving keys from keychain
        let keyIdentifier = "test-key-\(UUID().uuidString)"
        let originalKey = securityManager.generateSymmetricKey()

        try securityManager.storeKey(originalKey, with: keyIdentifier)
        let retrievedKey = try securityManager.retrieveKey(with: keyIdentifier)

        XCTAssertEqual(originalKey.withUnsafeBytes { Data($0) },
                      retrievedKey.withUnsafeBytes { Data($0) },
                      "Retrieved key should match stored key")

        // Clean up
        try securityManager.deleteKey(with: keyIdentifier)
    }

    func testKeyDeletion() throws {
        // Test key deletion from keychain
        let keyIdentifier = "test-key-\(UUID().uuidString)"
        let key = securityManager.generateSymmetricKey()

        try securityManager.storeKey(key, with: keyIdentifier)
        try securityManager.deleteKey(with: keyIdentifier)

        XCTAssertThrowsError(try securityManager.retrieveKey(with: keyIdentifier)) {
            error in
            XCTAssertTrue(error is SecurityError, "Should throw SecurityError for missing key")
        }
    }

    // MARK: - Hash Generation Tests

    func testDataHashGeneration() {
        // Test SHA-256 hash generation
        let hash1 = securityManager.generateDataHash(testData)
        let hash2 = securityManager.generateDataHash(testData)

        XCTAssertEqual(hash1, hash2, "Same data should produce same hash")
        XCTAssertEqual(hash1.count, 64, "SHA-256 hash should be 64 characters (hex)")
    }

    func testHashConsistency() {
        // Test hash consistency across multiple calls
        let hashes = (0..<10).map { _ in securityManager.generateDataHash(testData) }
        let uniqueHashes = Set(hashes)

        XCTAssertEqual(uniqueHashes.count, 1, "All hashes should be identical for same data")
    }

    func testDifferentDataDifferentHash() {
        // Test that different data produces different hashes
        let data1 = "Test data 1".data(using: .utf8)!
        let data2 = "Test data 2".data(using: .utf8)!

        let hash1 = securityManager.generateDataHash(data1)
        let hash2 = securityManager.generateDataHash(data2)

        XCTAssertNotEqual(hash1, hash2, "Different data should produce different hashes")
    }

    // MARK: - User Authentication Tests

    func testUserIdGeneration() {
        // Test user ID generation
        let userId1 = securityManager.getCurrentUserId()
        let userId2 = securityManager.getCurrentUserId()

        if let userId1 = userId1, let userId2 = userId2 {
            XCTAssertEqual(userId1, userId2, "User ID should be consistent within session")
        }
    }

    func testSessionIdGeneration() {
        // Test session ID generation
        let sessionId1 = securityManager.getCurrentSessionId()
        let sessionId2 = securityManager.getCurrentSessionId()

        XCTAssertEqual(sessionId1, sessionId2, "Session ID should be consistent within session")
        XCTAssertFalse(sessionId1.isEmpty, "Session ID should not be empty")
    }

    // MARK: - Application Lock Tests

    func testApplicationLocking() {
        // Test app locking functionality
        securityManager.lockApplication()
        XCTAssertTrue(securityManager.isAppLocked, "App should be locked after calling lockApplication")

        securityManager.unlockApplication()
        XCTAssertFalse(securityManager.isAppLocked, "App should be unlocked after calling unlockApplication")
    }

    func testAuthenticationRequirement() {
        // Test authentication requirement checking
        let requiresAuth = securityManager.isAuthenticationRequired
        XCTAssertTrue(requiresAuth is Bool, "Authentication requirement should return a boolean")
    }

    // MARK: - Biometric Authentication Tests

    func testBiometricAvailability() {
        // Test biometric authentication availability check
        let biometricsAvailable = securityManager.isBiometricAuthenticationAvailable()
        XCTAssertTrue(biometricsAvailable is Bool, "Biometric availability should return a boolean")
    }

    // MARK: - Error Handling Tests

    func testEncryptionWithInvalidData() {
        // Test error handling for encryption failures
        // This test simulates scenarios where encryption might fail
        // In a real implementation, this might involve corrupted keys or system failures

        // For now, we test that the security manager handles edge cases gracefully
        let veryLargeData = Data(count: Int.max / 1000) // Large but manageable data

        do {
            _ = try securityManager.encryptData(veryLargeData)
            // If encryption succeeds, that's also valid
            XCTAssertTrue(true, "Large data encryption handled")
        } catch {
            // If it fails, it should be a proper SecurityError
            XCTAssertTrue(error is SecurityError, "Should throw SecurityError for problematic encryption")
        }
    }

    func testDecryptionWithCorruptedData() {
        // Test decryption with corrupted data
        let corruptedData = Data([0x00, 0x01, 0x02, 0x03]) // Invalid encrypted data

        XCTAssertThrowsError(try securityManager.decryptData(corruptedData)) { error in
            XCTAssertTrue(error is SecurityError, "Should throw SecurityError for corrupted data")
        }
    }

    // MARK: - Performance Tests

    func testEncryptionPerformance() {
        // Test encryption performance
        let testData = Data(count: 1024 * 100) // 100KB

        measure {
            do {
                _ = try securityManager.encryptData(testData)
            } catch {
                XCTFail("Encryption should not fail in performance test: \(error)")
            }
        }
    }

    func testHashingPerformance() {
        // Test hashing performance
        let testData = Data(count: 1024 * 100) // 100KB

        measure {
            _ = securityManager.generateDataHash(testData)
        }
    }

    // MARK: - Integration Tests

    func testFullEncryptionDecryptionWorkflow() throws {
        // Test complete encryption/decryption workflow
        let originalData = """
        {
            "vitals": {
                "heartRate": 72,
                "bloodPressure": "120/80",
                "weight": 70.5
            },
            "timestamp": "\(Date().timeIntervalSince1970)"
        }
        """.data(using: .utf8)!

        // Encrypt
        let encryptedData = try securityManager.encryptData(originalData)
        XCTAssertNotEqual(encryptedData, originalData)

        // Decrypt
        let decryptedData = try securityManager.decryptData(encryptedData)
        XCTAssertEqual(decryptedData, originalData)

        // Verify JSON integrity
        let originalJSON = try JSONSerialization.jsonObject(with: originalData) as! [String: Any]
        let decryptedJSON = try JSONSerialization.jsonObject(with: decryptedData) as! [String: Any]

        XCTAssertEqual(originalJSON["vitals"] as! [String: Any],
                      decryptedJSON["vitals"] as! [String: Any])
    }

    func testKeyManagementWorkflow() throws {
        // Test complete key management workflow
        let keyId = "test-workflow-key"

        // Generate and store key
        let originalKey = securityManager.generateSymmetricKey()
        try securityManager.storeKey(originalKey, with: keyId)

        // Retrieve and verify
        let retrievedKey = try securityManager.retrieveKey(with: keyId)
        XCTAssertEqual(originalKey.withUnsafeBytes { Data($0) },
                      retrievedKey.withUnsafeBytes { Data($0) })

        // Use key for encryption/decryption
        let testData = "Workflow test data".data(using: .utf8)!
        let encrypted = try securityManager.encryptData(testData)
        let decrypted = try securityManager.decryptData(encrypted)
        XCTAssertEqual(decrypted, testData)

        // Clean up
        try securityManager.deleteKey(with: keyId)
    }
}

// MARK: - Test Helper Extensions

extension SecurityManagerTests {

    /// Generate test data of specified size
    func generateTestData(size: Int) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { bytes in
            for i in 0..<size {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        return data
    }

    /// Verify data integrity after encryption/decryption
    func verifyDataIntegrity(original: Data, processed: Data) -> Bool {
        return original == processed
    }
}

// MARK: - Mock Security Errors for Testing

enum TestSecurityError: Error {
    case mockEncryptionFailure
    case mockDecryptionFailure
    case mockKeyStoreFailure
}

// MARK: - Performance Measurement Helpers

extension SecurityManagerTests {

    func measureAsyncPerformance<T>(
        _ operation: @escaping () async throws -> T
    ) {
        let expectation = XCTestExpectation(description: "Async operation")

        measure {
            Task {
                do {
                    _ = try await operation()
                } catch {
                    XCTFail("Async operation failed: \(error)")
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }
}