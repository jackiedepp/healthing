//
//  OCRService.swift
//  HealthingApp
//
//  Created on 2026-01-27.
//

import Foundation
import Vision
import UIKit
import OSLog
import CoreSpotlight
import MobileCoreServices

/// OCR Service for processing medical documents with support for English and Chinese text
class OCRService: ObservableObject {

    // MARK: - Singleton
    static let shared = OCRService()

    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "OCRService")

    // MARK: - Public Properties
    @Published var isProcessing = false
    @Published var processingProgress: Float = 0.0

    private init() {}

    // MARK: - OCR Processing

    /// Process an image to extract text using Vision framework
    func processImage(_ image: UIImage, supportedLanguages: [String] = ["en-US", "zh-Hans", "zh-Hant"]) async throws -> OCRResult {
        isProcessing = true
        processingProgress = 0.0

        defer {
            Task { @MainActor in
                isProcessing = false
                processingProgress = 0.0
            }
        }

        guard let cgImage = image.cgImage else {
            throw OCRError.imageProcessingFailed
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)

        return try await withCheckedThrowingContinuation { continuation in
            // Create text recognition request with multiple language support
            let request = VNRecognizeTextRequest { request, error in
                Task { @MainActor in
                    self.processingProgress = 0.8
                }

                if let error = error {
                    self.logger.error("OCR processing failed: \(error.localizedDescription)")
                    continuation.resume(throwing: OCRError.textRecognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }

                let result = self.processTextObservations(observations)
                continuation.resume(returning: result)
            }

            // Configure text recognition for multiple languages
            request.recognitionLanguages = supportedLanguages
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            // Set custom words for medical terminology
            request.customWords = self.getMedicalTerminology(for: supportedLanguages)

            Task { @MainActor in
                self.processingProgress = 0.2
            }

            do {
                try requestHandler.perform([request])

                Task { @MainActor in
                    self.processingProgress = 0.6
                }
            } catch {
                self.logger.error("Failed to perform OCR request: \(error.localizedDescription)")
                continuation.resume(throwing: OCRError.imageProcessingFailed)
            }
        }
    }

    /// Process multiple images for batch OCR
    func processBatchImages(_ images: [UIImage], supportedLanguages: [String] = ["en-US", "zh-Hans", "zh-Hant"]) async throws -> [OCRResult] {
        var results: [OCRResult] = []

        for (index, image) in images.enumerated() {
            let progress = Float(index) / Float(images.count)
            await MainActor.run {
                self.processingProgress = progress
            }

            let result = try await processImage(image, supportedLanguages: supportedLanguages)
            results.append(result)
        }

        return results
    }

    // MARK: - Enhanced OCR with Search Indexing

    /// Enhanced OCR processing with automatic search indexing
    func performOCR(on image: UIImage, language: NLLanguage = .english) async throws -> EnhancedOCRResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Perform standard OCR processing
        let standardResult = try await processImage(image)

        // Extract search-optimized content
        let searchableContent = extractSearchableContent(from: standardResult)

        // Generate search keywords
        let searchKeywords = generateSearchKeywords(from: standardResult, content: searchableContent)

        // Create enhanced result
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return EnhancedOCRResult(
            extractedText: standardResult.fullText,
            confidence: calculateOverallConfidence(from: standardResult.detectedTexts),
            language: mapLanguageCode(language),
            boundingBoxes: standardResult.detectedTexts.map { $0.boundingBox },
            recognizedBlocks: createTextBlocks(from: standardResult.detectedTexts),
            searchableContent: searchableContent,
            searchKeywords: searchKeywords,
            medicalEntities: extractMedicalEntitiesForSearch(from: standardResult),
            processingTime: processingTime
        )
    }

    /// Create search index for OCR result
    func createSearchIndex(for ocrResult: EnhancedOCRResult, documentId: String, metadata: [String: Any] = [:]) async throws {
        let attributeSet = CSSearchableItemAttributeSet(itemContentType: kUTTypeText as String)

        // Basic content
        attributeSet.textContent = ocrResult.extractedText
        attributeSet.title = metadata["title"] as? String ?? "Medical Document"
        attributeSet.contentDescription = generateContentDescription(from: ocrResult)

        // Keywords and search terms
        attributeSet.keywords = ocrResult.searchKeywords

        // Medical-specific attributes
        let medicalKeywords = ocrResult.medicalEntities.map { $0.text }
        attributeSet.setValue(medicalKeywords, forCustomKey: CSCustomAttributeKey(keyName: "medicalTerms")!)
        attributeSet.setValue(ocrResult.confidence, forCustomKey: CSCustomAttributeKey(keyName: "ocrConfidence")!)

        // Language and processing metadata
        attributeSet.setValue(ocrResult.language, forCustomKey: CSCustomAttributeKey(keyName: "documentLanguage")!)
        attributeSet.setValue(Date(), forCustomKey: CSCustomAttributeKey(keyName: "ocrProcessingDate")!)

        // Create searchable item
        let searchableItem = CSSearchableItem(
            uniqueIdentifier: "ocr-\(documentId)",
            domainIdentifier: "com.healthingapp.medicaldocuments.ocr",
            attributeSet: attributeSet
        )

        // Index the item
        try await withCheckedThrowingContinuation { continuation in
            CSSearchableIndex.default().indexSearchableItems([searchableItem]) { error in
                if let error = error {
                    continuation.resume(throwing: OCRError.searchIndexingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        logger.info("Created search index for document \(documentId)")
    }

    /// Extract searchable content optimized for medical document search
    private func extractSearchableContent(from result: OCRResult) -> SearchableContent {
        let fullText = result.fullText

        // Extract structured medical information
        let vitalsInfo = extractVitalSigns(from: fullText)
        let medicationInfo = extractMedicationDetails(from: fullText)
        let dateInfo = extractDateInformation(from: fullText)
        let diagnosticInfo = extractDiagnosticInformation(from: fullText)

        return SearchableContent(
            fullText: fullText,
            medicalTerms: result.medicalInformation.medications + result.medicalInformation.diagnoses,
            vitalSigns: vitalsInfo,
            medications: medicationInfo,
            dates: dateInfo,
            diagnosticTerms: diagnosticInfo,
            extractedEntities: result.medicalInformation
        )
    }

    private func generateSearchKeywords(from result: OCRResult, content: SearchableContent) -> [String] {
        var keywords: Set<String> = []

        // Add medical terminology
        keywords.formUnion(content.medicalTerms)

        // Add vital signs keywords
        for vital in content.vitalSigns {
            keywords.insert(vital.type)
            keywords.insert("\(vital.value) \(vital.unit)")
        }

        // Add medication keywords
        for medication in content.medications {
            keywords.insert(medication.name)
            if let dosage = medication.dosage {
                keywords.insert(dosage)
            }
        }

        // Add diagnostic keywords
        keywords.formUnion(content.diagnosticTerms)

        // Extract general medical keywords from text
        let medicalKeywords = extractMedicalKeywordsFromText(content.fullText)
        keywords.formUnion(medicalKeywords)

        // Filter and clean keywords
        return keywords
            .filter { $0.count >= 2 && !isCommonWord($0) }
            .prefix(50)
            .map { String($0) }
    }

    private func extractVitalSigns(from text: String) -> [VitalSign] {
        var vitals: [VitalSign] = []

        let vitalPatterns = [
            (type: "blood_pressure", pattern: #"(?i)(blood pressure|BP):?\s*(\d+/\d+)\s*(mmHg)?"#),
            (type: "heart_rate", pattern: #"(?i)(heart rate|HR|pulse):?\s*(\d+)\s*(bpm|beats)"#),
            (type: "temperature", pattern: #"(?i)(temperature|temp):?\s*(\d+\.?\d*)\s*°?([CF])"#),
            (type: "weight", pattern: #"(?i)(weight):?\s*(\d+\.?\d*)\s*(kg|lbs|pounds)"#),
            (type: "height", pattern: #"(?i)(height):?\s*(\d+\.?\d*)\s*(cm|ft|inches)"#),
            (type: "oxygen_saturation", pattern: #"(?i)(O2 sat|oxygen saturation|SpO2):?\s*(\d+)\s*%"#)
        ]

        for (type, pattern) in vitalPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))

                for match in matches {
                    if match.numberOfRanges >= 3 {
                        if let valueRange = Range(match.range(at: 2), in: text) {
                            let value = String(text[valueRange])
                            let unit = match.numberOfRanges >= 4 ? String(text[Range(match.range(at: 3), in: text)!]) : ""

                            vitals.append(VitalSign(type: type, value: value, unit: unit))
                        }
                    }
                }
            } catch {
                continue
            }
        }

        return vitals
    }

    private func extractMedicationDetails(from text: String) -> [MedicationInfo] {
        var medications: [MedicationInfo] = []

        // Pattern for medications with dosage
        let medicationPattern = #"(?i)([A-Z][a-z]+(?:in|ol|ide|ine|ate|ium|cillin|mycin))\s+(\d+\s*(?:mg|ml|tablets?|capsules?))"#

        do {
            let regex = try NSRegularExpression(pattern: medicationPattern, options: .caseInsensitive)
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))

            for match in matches {
                if match.numberOfRanges >= 3 {
                    if let nameRange = Range(match.range(at: 1), in: text),
                       let dosageRange = Range(match.range(at: 2), in: text) {
                        let name = String(text[nameRange])
                        let dosage = String(text[dosageRange])

                        medications.append(MedicationInfo(name: name, dosage: dosage, frequency: nil))
                    }
                }
            }
        } catch {
            // Fallback to simple medication extraction
            let medTerms = extractEnglishMedications(from: text) + extractChineseMedications(from: text)
            medications.append(contentsOf: medTerms.map { MedicationInfo(name: $0, dosage: nil, frequency: nil) })
        }

        return medications
    }

    private func extractDateInformation(from text: String) -> [DateInfo] {
        let dates = extractDates(from: text)
        return dates.map { DateInfo(dateString: $0, context: extractDateContext(for: $0, in: text)) }
    }

    private func extractDiagnosticInformation(from text: String) -> [String] {
        let diagnosticKeywords = [
            "diagnosis", "impression", "findings", "conclusion", "assessment",
            "condition", "disease", "disorder", "syndrome", "infection",
            "inflammation", "abnormal", "normal", "negative", "positive"
        ]

        var diagnosticTerms: [String] = []
        let lowercaseText = text.lowercased()

        for keyword in diagnosticKeywords {
            if lowercaseText.contains(keyword) {
                diagnosticTerms.append(keyword)
            }
        }

        return diagnosticTerms
    }

    private func extractDateContext(for date: String, in text: String) -> String {
        // Find the date in text and extract surrounding context
        guard let range = text.range(of: date) else { return "" }

        let beforeStart = max(text.startIndex, text.index(range.lowerBound, offsetBy: -20))
        let afterEnd = min(text.endIndex, text.index(range.upperBound, offsetBy: 20))

        let contextRange = beforeStart..<afterEnd
        return String(text[contextRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMedicalKeywordsFromText(_ text: String) -> Set<String> {
        let medicalTermCategories = [
            // Body systems
            "cardiovascular", "respiratory", "gastrointestinal", "neurological", "endocrine",
            "musculoskeletal", "dermatological", "genitourinary", "hematological",

            // Common medical terms
            "patient", "treatment", "therapy", "medication", "prescription", "dosage",
            "symptom", "diagnosis", "prognosis", "chronic", "acute", "severe", "mild",
            "laboratory", "radiology", "pathology", "biopsy", "screening",

            // Procedures
            "surgery", "operation", "procedure", "intervention", "consultation",
            "examination", "assessment", "evaluation", "follow-up", "monitoring"
        ]

        var keywords: Set<String> = []
        let lowercaseText = text.lowercased()

        for term in medicalTermCategories {
            if lowercaseText.contains(term) {
                keywords.insert(term)
            }
        }

        return keywords
    }

    private func extractMedicalEntitiesForSearch(from result: OCRResult) -> [MedicalEntityInfo] {
        var entities: [MedicalEntityInfo] = []

        // Convert medications to entities
        for medication in result.medicalInformation.medications {
            entities.append(MedicalEntityInfo(text: medication, type: .medication, confidence: 0.8))
        }

        // Convert diagnoses to entities
        for diagnosis in result.medicalInformation.diagnoses {
            entities.append(MedicalEntityInfo(text: diagnosis, type: .diagnosis, confidence: 0.7))
        }

        // Convert vitals to entities
        for vital in result.medicalInformation.vitals {
            entities.append(MedicalEntityInfo(text: vital, type: .vitalSign, confidence: 0.9))
        }

        return entities
    }

    private func calculateOverallConfidence(from detectedTexts: [DetectedText]) -> Double {
        guard !detectedTexts.isEmpty else { return 0.0 }

        let totalConfidence = detectedTexts.map { Double($0.confidence) }.reduce(0, +)
        return totalConfidence / Double(detectedTexts.count)
    }

    private func mapLanguageCode(_ language: NLLanguage) -> String {
        switch language {
        case .english: return "en-US"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        default: return "en-US"
        }
    }

    private func createTextBlocks(from detectedTexts: [DetectedText]) -> [TextBlock] {
        return detectedTexts.map { detected in
            TextBlock(
                text: detected.text,
                confidence: Double(detected.confidence),
                boundingBox: detected.boundingBox
            )
        }
    }

    private func generateContentDescription(from ocrResult: EnhancedOCRResult) -> String {
        let textLength = ocrResult.extractedText.count
        let entityCount = ocrResult.medicalEntities.count
        let confidence = String(format: "%.1f", ocrResult.confidence * 100)

        return "Medical document with \(textLength) characters, \(entityCount) medical entities, \(confidence)% confidence"
    }

    private func isCommonWord(_ word: String) -> Bool {
        let commonWords = [
            "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with",
            "by", "from", "is", "are", "was", "were", "be", "been", "have", "has",
            "had", "do", "does", "did", "will", "would", "could", "should", "may",
            "might", "can", "this", "that", "these", "those", "a", "an"
        ]
        return commonWords.contains(word.lowercased())
    }

    // MARK: - Private Methods

    private func processTextObservations(_ observations: [VNRecognizedTextObservation]) -> OCRResult {
        var detectedTexts: [DetectedText] = []
        var fullText = ""
        var detectedLanguages: Set<String> = []

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }

            let text = topCandidate.string
            let confidence = topCandidate.confidence
            let boundingBox = observation.boundingBox

            // Detect language of the text
            let language = detectLanguage(for: text)
            detectedLanguages.insert(language)

            let detectedText = DetectedText(
                text: text,
                confidence: confidence,
                boundingBox: boundingBox,
                language: language
            )

            detectedTexts.append(detectedText)
            fullText += text + "\n"
        }

        // Extract medical information
        let medicalInfo = extractMedicalInformation(from: fullText, languages: Array(detectedLanguages))

        return OCRResult(
            fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedTexts: detectedTexts,
            detectedLanguages: Array(detectedLanguages),
            medicalInformation: medicalInfo,
            processingDate: Date()
        )
    }

    private func detectLanguage(for text: String) -> String {
        let recognizer = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        recognizer.string = text

        let language = recognizer.dominantLanguage ?? "en"

        // Map language codes to our supported languages
        switch language {
        case "zh-Hans", "zh-CN":
            return "zh-Hans"
        case "zh-Hant", "zh-TW", "zh-HK":
            return "zh-Hant"
        default:
            return "en-US"
        }
    }

    private func extractMedicalInformation(from text: String, languages: [String]) -> MedicalInformation {
        var extractedInfo = MedicalInformation()

        // Extract dates
        extractedInfo.dates = extractDates(from: text)

        // Extract medical terms based on language
        for language in languages {
            switch language {
            case "zh-Hans", "zh-Hant":
                extractedInfo.medications.append(contentsOf: extractChineseMedications(from: text))
                extractedInfo.diagnoses.append(contentsOf: extractChineseDiagnoses(from: text))
                extractedInfo.vitals.append(contentsOf: extractChineseVitals(from: text))
            default:
                extractedInfo.medications.append(contentsOf: extractEnglishMedications(from: text))
                extractedInfo.diagnoses.append(contentsOf: extractEnglishDiagnoses(from: text))
                extractedInfo.vitals.append(contentsOf: extractEnglishVitals(from: text))
            }
        }

        return extractedInfo
    }

    // MARK: - Medical Term Extraction

    private func extractDates(from text: String) -> [String] {
        let dateRegexPatterns = [
            // English formats
            "\\d{1,2}/\\d{1,2}/\\d{4}",
            "\\d{1,2}-\\d{1,2}-\\d{4}",
            "\\d{4}-\\d{1,2}-\\d{1,2}",
            // Chinese formats
            "\\d{4}年\\d{1,2}月\\d{1,2}日",
            "\\d{1,2}月\\d{1,2}日"
        ]

        var dates: [String] = []

        for pattern in dateRegexPatterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []

            for match in matches {
                if let range = Range(match.range, in: text) {
                    dates.append(String(text[range]))
                }
            }
        }

        return Array(Set(dates)) // Remove duplicates
    }

    private func extractEnglishMedications(from text: String) -> [String] {
        let medicationPatterns = [
            "\\b\\w+cillin\\b", // Antibiotics ending in -cillin
            "\\b\\w+mycin\\b",  // Antibiotics ending in -mycin
            "\\bibuprofen\\b",
            "\\baspirin\\b",
            "\\bmetformin\\b",
            "\\blisinopril\\b",
            "\\batorvastatin\\b",
            "\\bamoxicillin\\b",
            "\\bomeprazole\\b"
        ]

        return extractTermsWithPatterns(text, patterns: medicationPatterns)
    }

    private func extractChineseMedications(from text: String) -> [String] {
        let chineseMedicationTerms = [
            "阿司匹林", "布洛芬", "对乙酰氨基酚", "头孢", "青霉素",
            "甲硝唑", "左氧氟沙星", "阿莫西林", "感冒灵", "板蓝根",
            "金银花", "连翘", "甘草", "当归", "人参", "黄芪"
        ]

        return extractChineseTerms(text, terms: chineseMedicationTerms)
    }

    private func extractEnglishDiagnoses(from text: String) -> [String] {
        let diagnosisPatterns = [
            "\\bhypertension\\b",
            "\\bdiabetes\\b",
            "\\bhyperlipidemia\\b",
            "\\bpneumonia\\b",
            "\\bbronchitis\\b",
            "\\binfection\\b",
            "\\bflu\\b",
            "\\bcold\\b"
        ]

        return extractTermsWithPatterns(text, patterns: diagnosisPatterns)
    }

    private func extractChineseDiagnoses(from text: String) -> [String] {
        let chineseDiagnosisTerms = [
            "高血压", "糖尿病", "高血脂", "肺炎", "支气管炎",
            "感冒", "发烧", "咳嗽", "头痛", "胃炎", "肠炎",
            "关节炎", "过敏", "哮喘", "心脏病"
        ]

        return extractChineseTerms(text, terms: chineseDiagnosisTerms)
    }

    private func extractEnglishVitals(from text: String) -> [String] {
        let vitalsPatterns = [
            "\\d+/\\d+\\s*mmHg", // Blood pressure
            "\\d+\\s*bpm",       // Heart rate
            "\\d+\\.?\\d*°?[CF]", // Temperature
            "\\d+\\.?\\d*\\s*kg", // Weight
            "\\d+\\.?\\d*\\s*cm"  // Height
        ]

        return extractTermsWithPatterns(text, patterns: vitalsPatterns)
    }

    private func extractChineseVitals(from text: String) -> [String] {
        let chineseVitalsPatterns = [
            "\\d+/\\d+\\s*毫米汞柱", // Blood pressure
            "\\d+\\s*次/分",        // Heart rate
            "\\d+\\.?\\d*°?[℃℉]", // Temperature
            "\\d+\\.?\\d*\\s*公斤", // Weight
            "\\d+\\.?\\d*\\s*厘米"  // Height
        ]

        return extractTermsWithPatterns(text, patterns: chineseVitalsPatterns)
    }

    private func extractTermsWithPatterns(_ text: String, patterns: [String]) -> [String] {
        var terms: [String] = []

        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []

            for match in matches {
                if let range = Range(match.range, in: text) {
                    terms.append(String(text[range]))
                }
            }
        }

        return terms
    }

    private func extractChineseTerms(_ text: String, terms: [String]) -> [String] {
        var foundTerms: [String] = []

        for term in terms {
            if text.contains(term) {
                foundTerms.append(term)
            }
        }

        return foundTerms
    }

    private func getMedicalTerminology(for languages: [String]) -> [String] {
        var terms: [String] = []

        // English medical terms
        if languages.contains("en-US") {
            terms.append(contentsOf: [
                "prescription", "medication", "diagnosis", "treatment",
                "blood pressure", "heart rate", "temperature", "weight",
                "height", "BMI", "cholesterol", "glucose"
            ])
        }

        // Chinese medical terms
        if languages.contains("zh-Hans") || languages.contains("zh-Hant") {
            terms.append(contentsOf: [
                "处方", "药物", "诊断", "治疗",
                "血压", "心率", "体温", "体重",
                "身高", "胆固醇", "血糖", "化验"
            ])
        }

        return terms
    }
}

// MARK: - Supporting Types

/// OCR processing result
struct OCRResult {
    let fullText: String
    let detectedTexts: [DetectedText]
    let detectedLanguages: [String]
    let medicalInformation: MedicalInformation
    let processingDate: Date
}

/// Individual detected text with metadata
struct DetectedText {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    let language: String
}

/// Extracted medical information
struct MedicalInformation {
    var medications: [String] = []
    var diagnoses: [String] = []
    var vitals: [String] = []
    var dates: [String] = []
    var doctorNames: [String] = []
    var hospitalNames: [String] = []
}

// MARK: - Enhanced OCR Types

/// Enhanced OCR result with search indexing capabilities
struct EnhancedOCRResult {
    let extractedText: String
    let confidence: Double
    let language: String
    let boundingBoxes: [CGRect]
    let recognizedBlocks: [TextBlock]
    let searchableContent: SearchableContent
    let searchKeywords: [String]
    let medicalEntities: [MedicalEntityInfo]
    let processingTime: TimeInterval
}

/// Searchable content extracted from OCR
struct SearchableContent {
    let fullText: String
    let medicalTerms: [String]
    let vitalSigns: [VitalSign]
    let medications: [MedicationInfo]
    let dates: [DateInfo]
    let diagnosticTerms: [String]
    let extractedEntities: MedicalInformation
}

/// Vital sign information
struct VitalSign {
    let type: String
    let value: String
    let unit: String
}

/// Medication information
struct MedicationInfo {
    let name: String
    let dosage: String?
    let frequency: String?
}

/// Date information with context
struct DateInfo {
    let dateString: String
    let context: String
}

/// Medical entity for search indexing
struct MedicalEntityInfo {
    let text: String
    let type: MedicalEntityType
    let confidence: Double
}

/// Medical entity types
enum MedicalEntityType {
    case medication
    case diagnosis
    case vitalSign
    case procedure
    case provider
    case date
    case labValue
}

/// Text block with positioning information
struct TextBlock {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}

/// OCR processing errors
enum OCRError: LocalizedError {
    case imageProcessingFailed
    case textRecognitionFailed(String)
    case noTextFound
    case unsupportedLanguage
    case searchIndexingFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return NSLocalizedString("Failed to process image", comment: "OCR image processing error")
        case .textRecognitionFailed(let message):
            return NSLocalizedString("Text recognition failed: \(message)", comment: "OCR text recognition error")
        case .noTextFound:
            return NSLocalizedString("No text found in image", comment: "OCR no text error")
        case .unsupportedLanguage:
            return NSLocalizedString("Unsupported language", comment: "OCR unsupported language error")
        case .searchIndexingFailed(let message):
            return NSLocalizedString("Search indexing failed: \(message)", comment: "OCR search indexing error")
        }
    }
}