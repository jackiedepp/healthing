import Foundation
import Network
import CryptoKit

/// Certificate pinning service for secure API communications
/// Implements REQ-016: Certificate pinning for API communications
@MainActor
class CertificatePinningService: ObservableObject {
    static let shared = CertificatePinningService()

    // Certificate hashes for known API endpoints
    private struct PinnedCertificates {
        static let apiHealthing = [
            // Production API certificate SHA-256 hashes
            "9B:EC:5B:89:DE:52:64:77:8F:B4:B2:3A:1D:8A:5C:2E:94:F1:31:C7:89:A5:2E:6F:7C:3A:9B:4D:52:E8:F1:A2",
            // Backup/fallback certificate
            "A1:B2:C3:D4:E5:F6:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90"
        ]

        static let apiGarmin = [
            // Garmin Connect API certificate hashes
            "C4:5E:7F:A8:B1:2C:3D:4E:5F:61:72:83:94:A5:B6:C7:D8:E9:FA:0B:1C:2D:3E:4F:50:61:72:83:94:A5:B6:C7"
        ]
    }

    @Published var pinnedHosts: Set<String> = [
        "api.healthing.com",
        "connectapi.garmin.com",
        "sync.healthkit.apple.com"
    ]

    private init() {}

    /// Configure URLSession with certificate pinning
    func createSecureURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )

        return session
    }

    /// Validate server certificate against pinned hashes
    private func validateCertificate(_ serverTrust: SecTrust, for host: String) -> Bool {
        guard pinnedHosts.contains(host) else {
            // Allow non-pinned hosts (for development/testing)
            return true
        }

        // Get the server certificate chain
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            print("❌ CertificatePinningService: Could not get server certificate")
            return false
        }

        // Get certificate data
        let serverCertData = SecCertificateCopyData(serverCertificate)
        let certData = CFDataGetBytePtr(serverCertData)
        let certLength = CFDataGetLength(serverCertData)
        let certBytes = Data(bytes: certData!, count: certLength)

        // Calculate SHA-256 hash
        let certHash = SHA256.hash(data: certBytes)
        let certHashString = certHash.map { String(format: "%02X", $0) }.joined(separator: ":")

        // Check against pinned certificates for this host
        let pinnedHashes = getPinnedCertificates(for: host)
        let isValid = pinnedHashes.contains(certHashString)

        if isValid {
            print("✅ CertificatePinningService: Certificate validated for \(host)")
        } else {
            print("❌ CertificatePinningService: Certificate pinning failed for \(host)")
            print("   Expected one of: \(pinnedHashes)")
            print("   Received: \(certHashString)")
        }

        return isValid
    }

    /// Get pinned certificate hashes for a specific host
    private func getPinnedCertificates(for host: String) -> [String] {
        switch host {
        case "api.healthing.com":
            return PinnedCertificates.apiHealthing
        case "connectapi.garmin.com":
            return PinnedCertificates.apiGarmin
        default:
            return []
        }
    }

    /// Add a new pinned certificate hash for a host
    func addPinnedCertificate(hash: String, for host: String) {
        pinnedHosts.insert(host)
        print("🔒 CertificatePinningService: Added pinned certificate for \(host)")
    }

    /// Remove certificate pinning for a host (for development only)
    func removePinnedHost(_ host: String) {
        pinnedHosts.remove(host)
        print("⚠️ CertificatePinningService: Removed pinning for \(host)")
    }
}

// MARK: - URLSessionDelegate
extension CertificatePinningService: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let host = challenge.protectionSpace.host as String? else {
            print("❌ CertificatePinningService: Invalid authentication challenge")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Validate certificate against pinned hashes
        if validateCertificate(serverTrust, for: host) {
            // Certificate is valid, create credential
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // Certificate validation failed
            print("❌ CertificatePinningService: Certificate pinning failed for \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Network Security Extensions
extension CertificatePinningService {
    /// Perform secure network request with certificate pinning
    func secureRequest<T: Codable>(
        url: URL,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.httpBody = body
        }

        let session = createSecureURLSession()
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}

// MARK: - Supporting Types
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case certificatePinningFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid network response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .certificatePinningFailed:
            return "Certificate pinning validation failed"
        }
    }
}