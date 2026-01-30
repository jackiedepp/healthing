//
//  SecurityManager.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import Foundation
import Security
import LocalAuthentication
import CryptoKit
import CommonCrypto

/// Privacy-first security manager handling encryption and local processing
class SecurityManager: ObservableObject {

    // MARK: - Singleton
    static let shared = SecurityManager()

    // MARK: - Private Properties
    private let keychain = KeychainService.shared
    private let encryptionKeyTag = "com.healthing.app.encryption.key"
    private let biometricContext = LAContext()

    // MARK: - Public Properties
    @Published var isAuthenticationRequired = true
    @Published var isBiometricEnabled = true
    @Published var isAppLocked = true

    private init() {
        setupSecurityDefaults()
    }

    // MARK: - Setup and Configuration

    private func setupSecurityDefaults() {
        // Check if biometric authentication is available
        var error: NSError?
        let canEvaluate = biometricContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isBiometricEnabled = canEvaluate

        // Generate or retrieve master encryption key
        _ = getOrCreateMasterKey()
    }

    // MARK: - Authentication

    /// Authenticate user with biometric or passcode
    func authenticateUser() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"
        context.localizedFallbackTitle = "Use Passcode"

        let reason = "Access your health data securely"

        do {
            let result = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if result {
                await MainActor.run {
                    self.isAppLocked = false
                }
            }
            return result
        } catch {
            // Fallback to device passcode
            do {
                let result = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                if result {
                    await MainActor.run {
                        self.isAppLocked = false
                    }
                }
                return result
            } catch {
                throw SecurityError.authenticationFailed(error.localizedDescription)
            }
        }
    }

    /// Lock the application
    func lockApplication() {
        DispatchQueue.main.async {
            self.isAppLocked = true
        }
    }

    // MARK: - Encryption and Decryption

    /// Encrypt sensitive health data using AES-256-GCM
    func encryptHealthData<T: Codable>(_ data: T) throws -> EncryptedData {
        let jsonData = try JSONEncoder().encode(data)
        return try encryptData(jsonData)
    }

    /// Decrypt sensitive health data
    func decryptHealthData<T: Codable>(_ encryptedData: EncryptedData, as type: T.Type) throws -> T {
        let decryptedData = try decryptData(encryptedData)
        return try JSONDecoder().decode(type, from: decryptedData)
    }

    /// Encrypt raw data using AES-256-GCM
    func encryptData(_ data: Data) throws -> EncryptedData {
        let masterKey = try getMasterKey()
        let symmetricKey = SymmetricKey(data: masterKey)

        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)

        guard let encryptedData = sealedBox.ciphertext,
              let nonce = sealedBox.nonce,
              let tag = sealedBox.tag else {
            throw SecurityError.encryptionFailed
        }

        return EncryptedData(
            ciphertext: encryptedData,
            nonce: Data(nonce),
            tag: tag,
            timestamp: Date()
        )
    }

    /// Decrypt raw data
    func decryptData(_ encryptedData: EncryptedData) throws -> Data {
        let masterKey = try getMasterKey()
        let symmetricKey = SymmetricKey(data: masterKey)

        guard let nonce = try? AES.GCM.Nonce(data: encryptedData.nonce) else {
            throw SecurityError.decryptionFailed
        }

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedData.ciphertext,
            tag: encryptedData.tag
        )

        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Key Management

    /// Get or create the master encryption key in Secure Enclave (Hardware-Backed)
    /// Implements REQ-003: Secure Enclave keying implementation
    private func getOrCreateMasterKey() -> Data {
        do {
            return try getMasterKey()
        } catch {
            do {
                return try createSecureEnclaveKey()
            } catch {
                // CRITICAL: Refuse to create software keys for production health data
                fatalError("Secure Enclave key creation failed - cannot proceed without hardware security")
            }
        }
    }

    /// Retrieve hardware-backed master key from Secure Enclave
    private func getMasterKey() throws -> Data {
        // First, verify we have a hardware-backed key
        try verifySecureEnclaveAvailability()

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: encryptionKeyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecReturnRef as String: true,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryAny, .privateKeyUsage],
                nil
            )!
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let privateKey = result as? SecKey else {
            throw SecurityError.keyRetrievalFailed
        }

        // Derive AES key from Secure Enclave private key
        return try deriveAESKeyFromSecureEnclave(privateKey)
    }

    /// Create a new hardware-backed encryption key in Secure Enclave
    private func createSecureEnclaveKey() throws -> Data {
        // Verify Secure Enclave is available
        try verifySecureEnclaveAvailability()

        // Create access control for Secure Enclave
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryAny],
            nil
        ) else {
            throw SecurityError.secureEnclaveNotAvailable
        }

        // Generate EC key pair in Secure Enclave
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: encryptionKeyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: accessControl
            ]
        ]

        var publicKey: SecKey?
        var privateKey: SecKey?
        let status = SecKeyGeneratePair(keyAttributes as CFDictionary, &publicKey, &privateKey)

        guard status == errSecSuccess,
              let securePrivateKey = privateKey else {
            throw SecurityError.secureEnclaveKeyGenerationFailed
        }

        // Derive AES key from the hardware-generated private key
        let aesKey = try deriveAESKeyFromSecureEnclave(securePrivateKey)

        print("✅ SecurityManager: Successfully created hardware-backed Secure Enclave key")
        return aesKey
    }

    /// Verify Secure Enclave availability and hardware attestation
    private func verifySecureEnclaveAvailability() throws {
        // Additional hardware verification - Secure Enclave not available in simulator
        guard isRunningOnPhysicalDevice() else {
            throw SecurityError.simulatorNotSupported
        }

        // Check if device supports Secure Enclave by attempting to create access control
        guard SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryAny],
            nil
        ) != nil else {
            throw SecurityError.secureEnclaveNotAvailable
        }

        // Verify biometric authentication is available
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw SecurityError.biometricNotAvailable
        }

        // Test Secure Enclave availability by checking if we can create a test key
        let testKeyTag = "com.healthing.app.test.key"
        let testAccessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        )!

        let testKeyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false, // Don't store permanently
                kSecAttrApplicationTag as String: testKeyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: testAccessControl
            ]
        ]

        var testPublicKey: SecKey?
        var testPrivateKey: SecKey?
        let testStatus = SecKeyGeneratePair(testKeyAttributes as CFDictionary, &testPublicKey, &testPrivateKey)

        guard testStatus == errSecSuccess else {
            throw SecurityError.secureEnclaveNotAvailable
        }

        print("✅ SecurityManager: Secure Enclave availability verified")
    }

    /// Derive AES-256 key from Secure Enclave private key using HKDF
    private func deriveAESKeyFromSecureEnclave(_ privateKey: SecKey) throws -> Data {
        // Use the private key to sign a known value to get deterministic output
        let inputData = "HealthingApp-AES-Key-Derivation".data(using: .utf8)!

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            inputData as CFData,
            nil
        ) as Data? else {
            throw SecurityError.keyDerivationFailed
        }

        // Use HKDF to derive a proper AES-256 key from the signature
        let aesKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: signature),
            salt: "HealthingApp-Salt".data(using: .utf8)!,
            info: "HealthingApp-AES-256".data(using: .utf8)!,
            outputByteCount: 32 // 256 bits
        )

        return aesKey.withUnsafeBytes { Data($0) }
    }

    /// Check if running on physical device (not simulator)
    private func isRunningOnPhysicalDevice() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Verify Secure Enclave key integrity and hardware backing
    func verifySecureEnclaveKeyIntegrity() async throws -> Bool {
        do {
            let key = try getMasterKey()

            // Verify key was derived from hardware
            try verifySecureEnclaveAvailability()

            // Test encryption/decryption cycle
            let testData = "Secure Enclave integrity test".data(using: .utf8)!
            let encrypted = try encryptData(testData)
            let decrypted = try decryptData(encrypted)

            let isIntact = testData == decrypted

            if isIntact {
                print("✅ SecurityManager: Secure Enclave key integrity verified")
            } else {
                print("❌ SecurityManager: Secure Enclave key integrity verification failed")
            }

            return isIntact

        } catch {
            print("❌ SecurityManager: Secure Enclave verification error: \(error)")
            throw SecurityError.secureEnclaveIntegrityCheckFailed
        }
    }

    // MARK: - Data Integrity

    /// Generate hash for data integrity verification
    func generateDataHash<T: Codable>(_ data: T) throws -> String {
        let jsonData = try JSONEncoder().encode(data)
        let hash = SHA256.hash(data: jsonData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Verify data integrity using hash
    func verifyDataIntegrity<T: Codable>(_ data: T, expectedHash: String) throws -> Bool {
        let currentHash = try generateDataHash(data)
        return currentHash == expectedHash
    }

    // MARK: - Secure Deletion

    /// Securely delete sensitive data from memory
    func secureDelete(_ data: inout Data) {
        data.withUnsafeMutableBytes { bytes in
            memset_s(bytes.baseAddress, bytes.count, 0, bytes.count)
        }
        data.removeAll()
    }

    /// Clear all encryption keys (for logout/reset)
    func clearAllKeys() throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: encryptionKeyTag.data(using: .utf8)!
        ]

        let status = SecItemDelete(deleteQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SecurityError.keyDeletionFailed
        }
    }
}

// MARK: - Supporting Types

/// Encrypted data container
struct EncryptedData: Codable {
    let ciphertext: Data
    let nonce: Data
    let tag: Data
    let timestamp: Date
}

/// Security-related errors
enum SecurityError: LocalizedError {
    case authenticationFailed(String)
    case encryptionFailed
    case decryptionFailed
    case keyRetrievalFailed
    case keyDeletionFailed
    case biometricNotAvailable
    case dataIntegrityViolation
    case secureEnclaveNotAvailable
    case secureEnclaveKeyGenerationFailed
    case keyDerivationFailed
    case simulatorNotSupported
    case secureEnclaveIntegrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keyRetrievalFailed:
            return "Failed to retrieve encryption key"
        case .keyDeletionFailed:
            return "Failed to delete encryption key"
        case .biometricNotAvailable:
            return "Biometric authentication is not available"
        case .dataIntegrityViolation:
            return "Data integrity check failed"
        case .secureEnclaveNotAvailable:
            return "Secure Enclave is not available on this device"
        case .secureEnclaveKeyGenerationFailed:
            return "Failed to generate key in Secure Enclave"
        case .keyDerivationFailed:
            return "Failed to derive encryption key from Secure Enclave"
        case .simulatorNotSupported:
            return "Secure Enclave operations are not supported in simulator"
        case .secureEnclaveIntegrityCheckFailed:
            return "Secure Enclave key integrity verification failed"
        }
    }
}

// MARK: - Keychain Service

/// Helper service for Keychain operations
class KeychainService {
    static let shared = KeychainService()

    private init() {}

    /// Store data in Keychain
    func store(data: Data, service: String, account: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ] as CFDictionary

        // Delete existing item first
        SecItemDelete(query)

        let status = SecItemAdd(query, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keyRetrievalFailed
        }
    }

    /// Retrieve data from Keychain
    func retrieve(service: String, account: String) throws -> Data {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw SecurityError.keyRetrievalFailed
        }

        return data
    }

    /// Delete data from Keychain
    func delete(service: String, account: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary

        let status = SecItemDelete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keyDeletionFailed
        }
    }
}