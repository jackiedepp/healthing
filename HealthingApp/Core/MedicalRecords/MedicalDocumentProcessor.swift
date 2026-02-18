import Foundation
import UIKit
import CoreData

/// Integration layer for OCR → Search → Classification pipeline
/// Coordinates document processing workflow for medical documents
@MainActor
class MedicalDocumentProcessor: ObservableObject {
    static let shared = MedicalDocumentProcessor()

    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var currentProcessingStep: ProcessingStep = .idle

    private let ocrService = OCRService.shared
    private let documentSearchEngine = DocumentSearchEngine.shared
    private let documentClassifier = DocumentClassifier.shared
    private let timelineManager = MedicalTimelineManager.shared

    private init() {}

    // MARK: - Document Processing Pipeline

    /// Process an encrypted document through the complete pipeline
    func processDocument(_ encryptedDocument: EncryptedDocument) async throws -> ProcessedDocument {
        isProcessing = true
        processingProgress = 0.0
        currentProcessingStep = .starting

        defer {
            isProcessing = false
            processingProgress = 0.0
            currentProcessingStep = .idle
        }

        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Step 1: Decrypt and prepare document
            currentProcessingStep = .decrypting
            let decryptedData = try await decryptDocument(encryptedDocument)
            processingProgress = 0.1

            // Step 2: OCR Processing (if applicable)
            currentProcessingStep = .performingOCR
            let ocrResult = try await performOCRProcessing(
                data: decryptedData,
                mimeType: encryptedDocument.mimeType
            )
            processingProgress = 0.4

            // Step 3: Document Classification
            currentProcessingStep = .classifying
            let classificationResult = try await performClassification(
                ocrResult: ocrResult,
                metadata: encryptedDocument.metadata
            )
            processingProgress = 0.7

            // Step 4: Search Indexing
            currentProcessingStep = .indexingForSearch
            let searchKeywords = try await performSearchIndexing(
                ocrResult: ocrResult,
                classificationResult: classificationResult
            )
            processingProgress = 0.9

            // Step 5: Timeline Integration
            currentProcessingStep = .integratingTimeline
            await integrateWithTimeline(
                encryptedDocument: encryptedDocument,
                ocrResult: ocrResult,
                classificationResult: classificationResult
            )
            processingProgress = 1.0

            currentProcessingStep = .completed
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime

            let processedDocument = ProcessedDocument(
                encryptedDocument: encryptedDocument,
                metadata: encryptedDocument.metadata,
                ocrResult: ocrResult,
                classificationResult: classificationResult,
                searchKeywords: searchKeywords,
                isIndexed: true,
                processingTime: processingTime,
                processingSteps: [
                    ProcessingStepResult(step: .decrypting, success: true, duration: 0.1),
                    ProcessingStepResult(step: .performingOCR, success: ocrResult != nil, duration: processingTime * 0.3),
                    ProcessingStepResult(step: .classifying, success: true, duration: processingTime * 0.3),
                    ProcessingStepResult(step: .indexingForSearch, success: true, duration: processingTime * 0.2),
                    ProcessingStepResult(step: .integratingTimeline, success: true, duration: processingTime * 0.1)
                ]
            )

            print("✅ MedicalDocumentProcessor: Document processed successfully in \(processingTime)s")
            return processedDocument

        } catch {
            currentProcessingStep = .failed
            print("❌ MedicalDocumentProcessor: Document processing failed: \(error)")
            throw error
        }
    }

    // MARK: - Processing Steps

    private func decryptDocument(_ encryptedDocument: EncryptedDocument) async throws -> Data {
        let securityManager = SecurityManager.shared

        guard let encryptedFilePath = URL(string: encryptedDocument.encryptedFilePath) else {
            throw ProcessingError.invalidFilePath
        }

        let encryptedData = try Data(contentsOf: encryptedFilePath)
        let decryptedData = try securityManager.decryptData(encryptedData)

        // Verify file integrity
        let computedHash = securityManager.generateDataHash(decryptedData)
        guard computedHash == encryptedDocument.fileHash else {
            throw ProcessingError.integrityVerificationFailed
        }

        return decryptedData
    }

    private func performOCRProcessing(data: Data, mimeType: String) async throws -> OCRResult? {
        // Only perform OCR on supported image and document types
        guard shouldPerformOCR(for: mimeType) else {
            return nil
        }

        // Convert data to UIImage for OCR processing
        guard let image = UIImage(data: data) else {
            throw ProcessingError.imageConversionFailed
        }

        // Perform OCR using the enhanced OCR service
        let ocrResult = try await ocrService.performOCRWithIndexing(on: image)

        print("📖 MedicalDocumentProcessor: OCR completed with confidence \(ocrResult.confidence)")
        return ocrResult
    }

    private func performClassification(
        ocrResult: OCRResult?,
        metadata: DocumentMetadata
    ) async throws -> ClassificationResult {
        let extractedText = ocrResult?.extractedText ?? ""

        let classificationResult = try await documentClassifier.classifyDocument(
            extractedText: extractedText,
            metadata: metadata
        )

        print("🏷️ MedicalDocumentProcessor: Document classified as \(classificationResult.primaryCategory)")
        return classificationResult
    }

    private func performSearchIndexing(
        ocrResult: OCRResult?,
        classificationResult: ClassificationResult
    ) async throws -> [String] {
        var searchKeywords: [String] = []

        // Extract keywords from OCR text
        if let extractedText = ocrResult?.extractedText {
            searchKeywords.append(contentsOf: extractMedicalKeywords(from: extractedText))
        }

        // Add classification keywords
        searchKeywords.append(contentsOf: classificationResult.keywords)

        // Add category-specific keywords
        searchKeywords.append(classificationResult.primaryCategory)
        if let documentType = DocumentType(rawValue: classificationResult.primaryCategory) {
            searchKeywords.append(documentType.displayName)
        }

        // Remove duplicates and filter
        searchKeywords = Array(Set(searchKeywords))
            .filter { !$0.isEmpty && $0.count >= 2 }
            .prefix(20)
            .map { String($0) }

        print("🔍 MedicalDocumentProcessor: Extracted \(searchKeywords.count) search keywords")
        return searchKeywords
    }

    private func integrateWithTimeline(
        encryptedDocument: EncryptedDocument,
        ocrResult: OCRResult?,
        classificationResult: ClassificationResult
    ) async {
        // Create a temporary document representation for timeline integration
        let timelineMetadata = TimelineDocumentMetadata(
            id: encryptedDocument.id,
            title: encryptedDocument.metadata.title ?? encryptedDocument.originalFilename,
            documentType: classificationResult.primaryCategory,
            documentDate: encryptedDocument.metadata.documentDate ?? encryptedDocument.uploadDate,
            providerName: encryptedDocument.metadata.providerName,
            extractedText: ocrResult?.extractedText,
            classificationResult: classificationResult.primaryCategory
        )

        // Note: Timeline integration will happen after Core Data persistence
        print("📅 MedicalDocumentProcessor: Prepared document for timeline integration")
    }

    // MARK: - OCR Enhancement Integration

    private func shouldPerformOCR(for mimeType: String) -> Bool {
        let ocrSupportedTypes = [
            "image/jpeg", "image/png", "image/tiff", "image/heif",
            "application/pdf"
        ]
        return ocrSupportedTypes.contains(mimeType)
    }

    private func extractMedicalKeywords(from text: String) -> [String] {
        let medicalTermPatterns = [
            #"(?i)\b(blood pressure|heart rate|temperature|weight|height|bmi)\b"#,
            #"(?i)\b(diabetes|hypertension|cholesterol|glucose|insulin)\b"#,
            #"(?i)\b(medication|prescription|dosage|mg|ml|tablets?)\b"#,
            #"(?i)\b(doctor|physician|nurse|clinic|hospital)\b"#,
            #"(?i)\b(diagnosis|symptoms?|treatment|therapy)\b"#,
            #"(?i)\b(lab results?|test results?|blood test|x-ray)\b"#
        ]

        var keywords: Set<String> = []

        for pattern in medicalTermPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))

                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let keyword = String(text[range]).lowercased()
                        keywords.insert(keyword)
                    }
                }
            } catch {
                continue
            }
        }

        return Array(keywords)
    }

    // MARK: - Batch Processing

    /// Process multiple documents in batch
    func processDocuments(_ encryptedDocuments: [EncryptedDocument]) async throws -> [ProcessedDocument] {
        var processedDocuments: [ProcessedDocument] = []
        let totalDocuments = encryptedDocuments.count

        for (index, encryptedDocument) in encryptedDocuments.enumerated() {
            do {
                let processedDocument = try await processDocument(encryptedDocument)
                processedDocuments.append(processedDocument)

                // Update overall progress
                let overallProgress = Double(index + 1) / Double(totalDocuments)
                await MainActor.run {
                    self.processingProgress = overallProgress
                }

                print("📄 MedicalDocumentProcessor: Processed document \(index + 1)/\(totalDocuments)")

            } catch {
                print("❌ MedicalDocumentProcessor: Failed to process document \(index + 1): \(error)")
                // Continue with remaining documents
            }
        }

        return processedDocuments
    }

    // MARK: - Reprocessing

    /// Reprocess an existing document with updated algorithms
    func reprocessDocument(_ document: MedicalDocument) async throws -> ProcessedDocument {
        guard let documentId = document.id,
              let encryptedFilePath = document.encryptedFilePath else {
            throw ProcessingError.invalidDocumentData
        }

        // Recreate encrypted document structure
        let encryptedDocument = EncryptedDocument(
            id: documentId,
            originalFilename: document.originalFilename ?? "unknown",
            mimeType: document.mimeType ?? "application/octet-stream",
            encryptedFilePath: encryptedFilePath,
            fileSize: document.fileSize,
            encryptedSize: document.fileSize, // Approximation
            fileHash: document.fileHash ?? "",
            uploadDate: document.uploadDate ?? Date(),
            metadata: DocumentMetadata(
                title: document.title,
                documentType: DocumentType(rawValue: document.documentType ?? ""),
                providerName: document.providerName,
                patientName: document.patientName,
                documentDate: document.documentDate,
                notes: document.notes,
                originalFilename: document.originalFilename
            )
        )

        return try await processDocument(encryptedDocument)
    }

    // MARK: - Processing Analytics

    /// Get processing statistics
    func getProcessingStatistics() -> ProcessingStatistics {
        // This would typically track processing metrics over time
        // For now, return basic statistics
        return ProcessingStatistics(
            totalDocumentsProcessed: 0,
            averageProcessingTime: 0.0,
            ocrSuccessRate: 0.0,
            classificationAccuracy: 0.0
        )
    }
}

// MARK: - Enhanced OCR Service Extension

extension OCRService {
    /// Enhanced OCR with search indexing integration
    func performOCRWithIndexing(on image: UIImage) async throws -> OCRResult {
        // Use existing OCR functionality
        let result = try await performOCR(on: image, language: .english)

        // Enhance with medical-specific post-processing
        let enhancedText = enhanceExtractedText(result.extractedText)
        let medicalEntities = extractMedicalEntities(from: enhancedText)

        return OCRResult(
            extractedText: enhancedText,
            confidence: result.confidence,
            language: result.language,
            boundingBoxes: result.boundingBoxes,
            recognizedBlocks: result.recognizedBlocks,
            medicalEntities: medicalEntities,
            processingTime: result.processingTime
        )
    }

    private func enhanceExtractedText(_ text: String) -> String {
        var enhancedText = text

        // Common OCR error corrections for medical documents
        let medicalCorrections = [
            ("rnyocardial", "myocardial"),
            ("hlood", "blood"),
            ("hean", "heart"),
            ("pressue", "pressure"),
            ("patint", "patient"),
            ("medicaton", "medication"),
            ("dosge", "dosage")
        ]

        for (incorrect, correct) in medicalCorrections {
            enhancedText = enhancedText.replacingOccurrences(
                of: incorrect,
                with: correct,
                options: .caseInsensitive
            )
        }

        return enhancedText
    }

    private func extractMedicalEntities(from text: String) -> [MedicalEntity] {
        var entities: [MedicalEntity] = []

        // Extract medication names
        let medicationPattern = #"(?i)\b([A-Z][a-z]+(?:in|ol|ide|ine|ate|ium))\s+\d+\s*(mg|ml)"#
        entities.append(contentsOf: extractEntities(from: text, pattern: medicationPattern, type: .medication))

        // Extract vital signs
        let vitalsPattern = #"(?i)(blood pressure|BP):\s*(\d+/\d+)|heart rate:\s*(\d+)"#
        entities.append(contentsOf: extractEntities(from: text, pattern: vitalsPattern, type: .vitalSign))

        // Extract lab values
        let labPattern = #"(?i)(glucose|cholesterol|hemoglobin):\s*(\d+\.?\d*)"#
        entities.append(contentsOf: extractEntities(from: text, pattern: labPattern, type: .labValue))

        return entities
    }

    private func extractEntities(from text: String, pattern: String, type: MedicalEntityType) -> [MedicalEntity] {
        var entities: [MedicalEntity] = []

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))

            for match in matches {
                if let range = Range(match.range, in: text) {
                    let entityText = String(text[range])
                    entities.append(MedicalEntity(text: entityText, type: type, confidence: 0.8))
                }
            }
        } catch {
            print("❌ Failed to extract entities with pattern \(pattern): \(error)")
        }

        return entities
    }
}

// MARK: - Supporting Types

enum ProcessingStep {
    case idle
    case starting
    case decrypting
    case performingOCR
    case classifying
    case indexingForSearch
    case integratingTimeline
    case completed
    case failed

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .starting: return "Starting..."
        case .decrypting: return "Decrypting Document"
        case .performingOCR: return "Extracting Text"
        case .classifying: return "Classifying Document"
        case .indexingForSearch: return "Indexing for Search"
        case .integratingTimeline: return "Adding to Timeline"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

struct ProcessingStepResult {
    let step: ProcessingStep
    let success: Bool
    let duration: TimeInterval
    let error: Error?

    init(step: ProcessingStep, success: Bool, duration: TimeInterval, error: Error? = nil) {
        self.step = step
        self.success = success
        self.duration = duration
        self.error = error
    }
}

struct ProcessedDocument {
    let encryptedDocument: EncryptedDocument
    let metadata: DocumentMetadata
    let ocrResult: OCRResult?
    let classificationResult: ClassificationResult?
    let searchKeywords: [String]?
    let isIndexed: Bool
    let processingTime: TimeInterval
    let processingSteps: [ProcessingStepResult]

    var hasOCR: Bool {
        return ocrResult != nil
    }

    var isClassified: Bool {
        return classificationResult != nil
    }

    var processingQuality: ProcessingQuality {
        guard let ocrResult = ocrResult,
              let classificationResult = classificationResult else {
            return .low
        }

        let avgConfidence = (ocrResult.confidence + classificationResult.confidence) / 2.0

        if avgConfidence >= 0.8 {
            return .high
        } else if avgConfidence >= 0.6 {
            return .medium
        } else {
            return .low
        }
    }
}

enum ProcessingQuality {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Low Quality"
        case .medium: return "Medium Quality"
        case .high: return "High Quality"
        }
    }

    var color: String {
        switch self {
        case .low: return "red"
        case .medium: return "orange"
        case .high: return "green"
        }
    }
}

struct TimelineDocumentMetadata {
    let id: String
    let title: String?
    let documentType: String
    let documentDate: Date?
    let providerName: String?
    let extractedText: String?
    let classificationResult: String?
}

struct ProcessingStatistics {
    let totalDocumentsProcessed: Int
    let averageProcessingTime: TimeInterval
    let ocrSuccessRate: Double
    let classificationAccuracy: Double
}

struct MedicalEntity {
    let text: String
    let type: MedicalEntityType
    let confidence: Double
}

enum MedicalEntityType {
    case medication
    case vitalSign
    case labValue
    case diagnosis
    case procedure
    case provider
}

enum ProcessingError: LocalizedError {
    case invalidFilePath
    case integrityVerificationFailed
    case imageConversionFailed
    case invalidDocumentData

    var errorDescription: String? {
        switch self {
        case .invalidFilePath:
            return "Invalid file path"
        case .integrityVerificationFailed:
            return "Document integrity verification failed"
        case .imageConversionFailed:
            return "Failed to convert data to image"
        case .invalidDocumentData:
            return "Invalid document data"
        }
    }
}