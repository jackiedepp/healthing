import Foundation
import UIKit
import UniformTypeIdentifiers
import CryptoKit
import CoreData

/// Secure document upload and local storage manager for medical documents
/// Implements REQ-026: Secure document upload and local storage (PDF, images, clinical documents)
@MainActor
class DocumentUploadManager: ObservableObject {
    static let shared = DocumentUploadManager()

    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var uploadedDocuments: [MedicalDocument] = []
    @Published var uploadError: DocumentUploadError?

    private let securityManager = SecurityManager.shared
    private let healthDataStore = HealthDataStore.shared
    private let ocrService = OCRService.shared
    private let documentProcessor = MedicalDocumentProcessor.shared

    // Supported document types
    private let supportedTypes: [UTType] = [
        .pdf,
        .jpeg, .png, .tiff, .heif,
        .text, .plainText,
        UTType(filenameExtension: "dcm") ?? .data, // DICOM files
        UTType(filenameExtension: "hl7") ?? .data  // HL7 files
    ]

    // Maximum file size (50MB)
    private let maxFileSize: Int64 = 50 * 1024 * 1024

    private init() {
        loadExistingDocuments()
    }

    // MARK: - Document Upload

    /// Upload a document from file URL with secure encryption and processing
    func uploadDocument(from url: URL, metadata: DocumentMetadata) async throws -> MedicalDocument {
        guard !isUploading else {
            throw DocumentUploadError.uploadInProgress
        }

        isUploading = true
        uploadProgress = 0.0
        uploadError = nil

        defer {
            isUploading = false
            uploadProgress = 0.0
        }

        do {
            // 1. Validate document
            try validateDocument(at: url)
            uploadProgress = 0.1

            // 2. Read and encrypt document data
            let encryptedDocument = try await securelyStoreDocument(from: url, metadata: metadata)
            uploadProgress = 0.4

            // 3. Process document (OCR, classification, etc.)
            let processedDocument = try await documentProcessor.processDocument(encryptedDocument)
            uploadProgress = 0.8

            // 4. Store in Core Data
            let medicalDocument = try await saveDocumentToStore(processedDocument)
            uploadProgress = 1.0

            // 5. Update local cache
            uploadedDocuments.append(medicalDocument)

            print("✅ DocumentUploadManager: Successfully uploaded document: \(medicalDocument.title)")
            return medicalDocument

        } catch {
            uploadError = error as? DocumentUploadError ?? .processingFailed(error.localizedDescription)
            print("❌ DocumentUploadManager: Upload failed: \(error)")
            throw error
        }
    }

    /// Upload a document from UIImage with secure encryption and processing
    func uploadDocument(from image: UIImage, metadata: DocumentMetadata) async throws -> MedicalDocument {
        guard !isUploading else {
            throw DocumentUploadError.uploadInProgress
        }

        isUploading = true
        uploadProgress = 0.0
        uploadError = nil

        defer {
            isUploading = false
            uploadProgress = 0.0
        }

        do {
            // 1. Convert image to data
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw DocumentUploadError.invalidFormat
            }
            uploadProgress = 0.1

            // 2. Validate size
            if Int64(imageData.count) > maxFileSize {
                throw DocumentUploadError.fileTooLarge
            }
            uploadProgress = 0.2

            // 3. Create encrypted document from image data
            let encryptedDocument = try await createEncryptedDocument(
                from: imageData,
                filename: metadata.originalFilename ?? "medical_image.jpg",
                mimeType: "image/jpeg",
                metadata: metadata
            )
            uploadProgress = 0.5

            // 4. Process document
            let processedDocument = try await documentProcessor.processDocument(encryptedDocument)
            uploadProgress = 0.8

            // 5. Store in Core Data
            let medicalDocument = try await saveDocumentToStore(processedDocument)
            uploadProgress = 1.0

            // 6. Update local cache
            uploadedDocuments.append(medicalDocument)

            print("✅ DocumentUploadManager: Successfully uploaded image document: \(medicalDocument.title)")
            return medicalDocument

        } catch {
            uploadError = error as? DocumentUploadError ?? .processingFailed(error.localizedDescription)
            print("❌ DocumentUploadManager: Image upload failed: \(error)")
            throw error
        }
    }

    // MARK: - Document Validation

    private func validateDocument(at url: URL) throws {
        // Check file accessibility
        guard url.startAccessingSecurityScopedResource() else {
            throw DocumentUploadError.fileNotAccessible
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Check file existence
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentUploadError.fileNotFound
        }

        // Check file size
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0

            if fileSize > maxFileSize {
                throw DocumentUploadError.fileTooLarge
            }

            if fileSize == 0 {
                throw DocumentUploadError.emptyFile
            }
        } catch {
            throw DocumentUploadError.validationFailed(error.localizedDescription)
        }

        // Check file type
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
            guard let utType = resourceValues.contentType,
                  supportedTypes.contains(where: { utType.conforms(to: $0) }) else {
                throw DocumentUploadError.unsupportedFormat
            }
        } catch {
            throw DocumentUploadError.validationFailed(error.localizedDescription)
        }
    }

    // MARK: - Secure Storage

    private func securelyStoreDocument(from url: URL, metadata: DocumentMetadata) async throws -> EncryptedDocument {
        guard url.startAccessingSecurityScopedResource() else {
            throw DocumentUploadError.fileNotAccessible
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Read file data
        let data = try Data(contentsOf: url)

        // Get MIME type
        let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
        let mimeType = resourceValues.contentType?.preferredMIMEType ?? "application/octet-stream"

        return try await createEncryptedDocument(
            from: data,
            filename: url.lastPathComponent,
            mimeType: mimeType,
            metadata: metadata
        )
    }

    private func createEncryptedDocument(
        from data: Data,
        filename: String,
        mimeType: String,
        metadata: DocumentMetadata
    ) async throws -> EncryptedDocument {
        // Generate unique document ID
        let documentId = UUID().uuidString

        // Calculate file hash for integrity verification
        let fileHash = SHA256.hash(data: data)
        let fileHashString = fileHash.compactMap { String(format: "%02x", $0) }.joined()

        // Encrypt document data using SecurityManager
        let encryptedData = try securityManager.encryptData(data)

        // Create secure storage path
        let documentsDirectory = getSecureDocumentsDirectory()
        let encryptedFilePath = documentsDirectory.appendingPathComponent("\(documentId).enc")

        // Write encrypted data to secure location
        try encryptedData.write(to: encryptedFilePath)

        // Create encrypted document metadata
        return EncryptedDocument(
            id: documentId,
            originalFilename: filename,
            mimeType: mimeType,
            encryptedFilePath: encryptedFilePath.path,
            fileSize: Int64(data.count),
            encryptedSize: Int64(encryptedData.count),
            fileHash: fileHashString,
            uploadDate: Date(),
            metadata: metadata
        )
    }

    private func getSecureDocumentsDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let secureDocumentsPath = documentsPath.appendingPathComponent("SecureMedicalDocuments", isDirectory: true)

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: secureDocumentsPath.path) {
            try? FileManager.default.createDirectory(
                at: secureDocumentsPath,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }

        return secureDocumentsPath
    }

    // MARK: - Core Data Storage

    private func saveDocumentToStore(_ processedDocument: ProcessedDocument) async throws -> MedicalDocument {
        return try await withCheckedThrowingContinuation { continuation in
            healthDataStore.persistentContainer.performBackgroundTask { context in
                do {
                    let medicalDocument = NSEntityDescription.insertNewObject(
                        forEntityName: "MedicalDocument",
                        into: context
                    ) as! MedicalDocument

                    // Basic document information
                    medicalDocument.id = processedDocument.encryptedDocument.id
                    medicalDocument.title = processedDocument.metadata.title ?? processedDocument.encryptedDocument.originalFilename
                    medicalDocument.originalFilename = processedDocument.encryptedDocument.originalFilename
                    medicalDocument.mimeType = processedDocument.encryptedDocument.mimeType
                    medicalDocument.fileSize = processedDocument.encryptedDocument.fileSize
                    medicalDocument.uploadDate = processedDocument.encryptedDocument.uploadDate
                    medicalDocument.createdDate = Date()

                    // Document metadata
                    medicalDocument.documentType = processedDocument.metadata.documentType?.rawValue
                    medicalDocument.providerName = processedDocument.metadata.providerName
                    medicalDocument.patientName = processedDocument.metadata.patientName
                    medicalDocument.documentDate = processedDocument.metadata.documentDate
                    medicalDocument.notes = processedDocument.metadata.notes

                    // Processing results
                    medicalDocument.extractedText = processedDocument.ocrResult?.extractedText
                    medicalDocument.ocrConfidence = processedDocument.ocrResult?.confidence ?? 0.0
                    medicalDocument.classificationResult = processedDocument.classificationResult?.primaryCategory
                    medicalDocument.classificationConfidence = processedDocument.classificationResult?.confidence ?? 0.0

                    // Security information
                    medicalDocument.encryptedFilePath = processedDocument.encryptedDocument.encryptedFilePath
                    medicalDocument.fileHash = processedDocument.encryptedDocument.fileHash

                    // Search and indexing
                    medicalDocument.searchKeywords = processedDocument.searchKeywords?.joined(separator: ",")
                    medicalDocument.isIndexed = processedDocument.isIndexed

                    try context.save()

                    // Return the document on the main context
                    let mainContextDocument = try self.healthDataStore.persistentContainer.viewContext.existingObject(with: medicalDocument.objectID) as! MedicalDocument

                    continuation.resume(returning: mainContextDocument)
                } catch {
                    continuation.resume(throwing: DocumentUploadError.storeFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Document Retrieval

    /// Load existing documents from Core Data
    private func loadExistingDocuments() {
        let request: NSFetchRequest<MedicalDocument> = MedicalDocument.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MedicalDocument.uploadDate, ascending: false)]

        do {
            uploadedDocuments = try healthDataStore.persistentContainer.viewContext.fetch(request)
            print("📚 DocumentUploadManager: Loaded \(uploadedDocuments.count) existing documents")
        } catch {
            print("❌ DocumentUploadManager: Failed to load existing documents: \(error)")
        }
    }

    /// Retrieve and decrypt document data
    func getDocumentData(for document: MedicalDocument) async throws -> Data {
        guard let encryptedFilePath = document.encryptedFilePath,
              FileManager.default.fileExists(atPath: encryptedFilePath) else {
            throw DocumentUploadError.fileNotFound
        }

        let encryptedData = try Data(contentsOf: URL(fileURLWithPath: encryptedFilePath))
        let decryptedData = try securityManager.decryptData(encryptedData)

        // Verify file integrity
        let fileHash = SHA256.hash(data: decryptedData)
        let fileHashString = fileHash.compactMap { String(format: "%02x", $0) }.joined()

        guard fileHashString == document.fileHash else {
            throw DocumentUploadError.integrityCheckFailed
        }

        return decryptedData
    }

    /// Delete document and its encrypted file
    func deleteDocument(_ document: MedicalDocument) async throws {
        // Remove encrypted file
        if let encryptedFilePath = document.encryptedFilePath {
            try? FileManager.default.removeItem(atPath: encryptedFilePath)
        }

        // Remove from Core Data
        let context = healthDataStore.persistentContainer.viewContext
        context.delete(document)
        try context.save()

        // Remove from local cache
        uploadedDocuments.removeAll { $0.id == document.id }

        print("🗑️ DocumentUploadManager: Deleted document: \(document.title ?? "Unknown")")
    }

    // MARK: - Batch Operations

    /// Upload multiple documents in batch
    func uploadDocuments(from urls: [URL], metadata: [DocumentMetadata]) async throws -> [MedicalDocument] {
        guard urls.count == metadata.count else {
            throw DocumentUploadError.invalidParameters
        }

        var uploadedDocs: [MedicalDocument] = []

        for (index, url) in urls.enumerated() {
            do {
                let document = try await uploadDocument(from: url, metadata: metadata[index])
                uploadedDocs.append(document)
            } catch {
                print("❌ DocumentUploadManager: Failed to upload document \(index): \(error)")
                // Continue with remaining documents
            }
        }

        return uploadedDocs
    }

    /// Get storage statistics
    func getStorageStatistics() -> DocumentStorageStats {
        let totalDocuments = uploadedDocuments.count
        let totalSize = uploadedDocuments.reduce(0) { $0 + $1.fileSize }
        let documentTypes = uploadedDocuments.compactMap { $0.documentType }.reduce(into: [String: Int]()) {
            $0[$1, default: 0] += 1
        }

        return DocumentStorageStats(
            totalDocuments: totalDocuments,
            totalSizeBytes: totalSize,
            documentTypeBreakdown: documentTypes,
            averageDocumentSize: totalDocuments > 0 ? totalSize / Int64(totalDocuments) : 0
        )
    }
}

// MARK: - Supporting Types

struct DocumentMetadata {
    let title: String?
    let documentType: DocumentType?
    let providerName: String?
    let patientName: String?
    let documentDate: Date?
    let notes: String?
    let originalFilename: String?
}

enum DocumentType: String, CaseIterable {
    case labResults = "lab_results"
    case imagingReport = "imaging_report"
    case dischargeSummary = "discharge_summary"
    case prescription = "prescription"
    case vaccinationRecord = "vaccination_record"
    case surgicalReport = "surgical_report"
    case consultation = "consultation"
    case diagnostic = "diagnostic"
    case insurance = "insurance"
    case other = "other"

    var displayName: String {
        switch self {
        case .labResults: return "Lab Results"
        case .imagingReport: return "Imaging Report"
        case .dischargeSummary: return "Discharge Summary"
        case .prescription: return "Prescription"
        case .vaccinationRecord: return "Vaccination Record"
        case .surgicalReport: return "Surgical Report"
        case .consultation: return "Consultation Notes"
        case .diagnostic: return "Diagnostic Report"
        case .insurance: return "Insurance Document"
        case .other: return "Other"
        }
    }
}

struct EncryptedDocument {
    let id: String
    let originalFilename: String
    let mimeType: String
    let encryptedFilePath: String
    let fileSize: Int64
    let encryptedSize: Int64
    let fileHash: String
    let uploadDate: Date
    let metadata: DocumentMetadata
}

struct ProcessedDocument {
    let encryptedDocument: EncryptedDocument
    let metadata: DocumentMetadata
    let ocrResult: OCRResult?
    let classificationResult: ClassificationResult?
    let searchKeywords: [String]?
    let isIndexed: Bool
}

struct DocumentStorageStats {
    let totalDocuments: Int
    let totalSizeBytes: Int64
    let documentTypeBreakdown: [String: Int]
    let averageDocumentSize: Int64

    var totalSizeMB: Double {
        return Double(totalSizeBytes) / (1024 * 1024)
    }
}

enum DocumentUploadError: LocalizedError {
    case uploadInProgress
    case fileNotFound
    case fileNotAccessible
    case fileTooLarge
    case emptyFile
    case unsupportedFormat
    case invalidFormat
    case validationFailed(String)
    case encryptionFailed
    case processingFailed(String)
    case storeFailed(String)
    case integrityCheckFailed
    case invalidParameters

    var errorDescription: String? {
        switch self {
        case .uploadInProgress:
            return "Another upload is already in progress"
        case .fileNotFound:
            return "File not found"
        case .fileNotAccessible:
            return "Cannot access file"
        case .fileTooLarge:
            return "File size exceeds 50MB limit"
        case .emptyFile:
            return "File is empty"
        case .unsupportedFormat:
            return "Unsupported file format"
        case .invalidFormat:
            return "Invalid file format"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .encryptionFailed:
            return "Failed to encrypt document"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .storeFailed(let message):
            return "Storage failed: \(message)"
        case .integrityCheckFailed:
            return "Document integrity check failed"
        case .invalidParameters:
            return "Invalid parameters provided"
        }
    }
}