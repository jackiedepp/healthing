import Foundation
import NaturalLanguage
import CreateML
import CoreML

/// AI-based document classification using Natural Language Processing
/// Implements REQ-041: Smart document classification based on extracted content
@MainActor
class DocumentClassifier: ObservableObject {
    static let shared = DocumentClassifier()

    @Published var isClassifying = false
    @Published var classificationModel: MLModel?

    private let nlProcessor = NLLanguageRecognizer()
    private let sentimentAnalyzer = NLSentimentPredictor()

    // Pre-trained classification rules
    private let medicalClassificationRules: [ClassificationRule]
    private let medicalTerminology: [String: [String]]

    private init() {
        self.medicalClassificationRules = DocumentClassifier.buildClassificationRules()
        self.medicalTerminology = DocumentClassifier.buildMedicalTerminology()
        setupNaturalLanguageProcessing()
        loadOrCreateMLModel()
    }

    // MARK: - Document Classification

    /// Classify a medical document based on its content
    func classifyDocument(
        extractedText: String,
        metadata: DocumentMetadata
    ) async throws -> ClassificationResult {
        isClassifying = true
        defer { isClassifying = false }

        // Perform multiple classification approaches
        let ruleBasedResult = performRuleBasedClassification(extractedText: extractedText, metadata: metadata)
        let nlpResult = await performNLPClassification(extractedText: extractedText)
        let contentAnalysisResult = performContentAnalysis(extractedText: extractedText)
        let metadataResult = classifyFromMetadata(metadata)

        // Combine classification results
        let finalResult = combineClassificationResults([
            ruleBasedResult,
            nlpResult,
            contentAnalysisResult,
            metadataResult
        ])

        print("🤖 DocumentClassifier: Classified document as \(finalResult.primaryCategory) with confidence \(finalResult.confidence)")

        return finalResult
    }

    // MARK: - Rule-Based Classification

    private func performRuleBasedClassification(
        extractedText: String,
        metadata: DocumentMetadata
    ) -> ClassificationResult {
        let text = extractedText.lowercased()
        var categoryScores: [String: Double] = [:]

        // Apply classification rules
        for rule in medicalClassificationRules {
            var ruleScore = 0.0
            var matchedKeywords = 0

            for keyword in rule.keywords {
                if text.contains(keyword.lowercased()) {
                    ruleScore += rule.weight
                    matchedKeywords += 1
                }
            }

            // Bonus for multiple keyword matches
            if matchedKeywords > 1 {
                ruleScore *= 1.5
            }

            categoryScores[rule.category.rawValue, default: 0.0] += ruleScore
        }

        // Find best category
        let bestCategory = categoryScores.max { $0.value < $1.value }
        let category = bestCategory?.key ?? DocumentType.other.rawValue
        let confidence = min(bestCategory?.value ?? 0.0, 1.0)

        return ClassificationResult(
            primaryCategory: category,
            confidence: confidence,
            alternativeCategories: getAlternativeCategories(from: categoryScores, excluding: category),
            classificationMethod: .ruleBased,
            keywords: extractMatchedKeywords(text: extractedText, category: category),
            processingTime: 0.0 // Rule-based is nearly instant
        )
    }

    // MARK: - NLP Classification

    private func performNLPClassification(extractedText: String) async -> ClassificationResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Language detection
        nlProcessor.string = extractedText
        let dominantLanguage = nlProcessor.dominantLanguage ?? .english

        // Text classification using NL framework
        let categoryScores = await classifyTextWithNLP(extractedText, language: dominantLanguage)

        // Entity recognition for medical entities
        let medicalEntities = extractMedicalEntities(from: extractedText)

        // Sentiment analysis (useful for determining severity)
        let sentiment = try? sentimentAnalyzer.predict(extractedText)

        // Combine NLP results
        let bestCategory = categoryScores.max { $0.value < $1.value }
        let category = bestCategory?.key ?? DocumentType.other.rawValue
        let confidence = bestCategory?.value ?? 0.0

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return ClassificationResult(
            primaryCategory: category,
            confidence: confidence,
            alternativeCategories: getAlternativeCategories(from: categoryScores, excluding: category),
            classificationMethod: .naturalLanguageProcessing,
            keywords: medicalEntities,
            processingTime: processingTime,
            metadata: [
                "language": dominantLanguage.rawValue,
                "sentiment": sentiment ?? 0.0,
                "entityCount": medicalEntities.count
            ]
        )
    }

    private func classifyTextWithNLP(_ text: String, language: NLLanguage) async -> [String: Double] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var categoryScores: [String: Double] = [:]

                // Use NL framework for text classification
                let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
                tagger.string = text

                // Medical-specific entity recognition
                tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
                    if let tag = tag {
                        let word = String(text[tokenRange]).lowercased()

                        // Check against medical terminology
                        for (category, terms) in self.medicalTerminology {
                            if terms.contains { word.contains($0) } {
                                categoryScores[category, default: 0.0] += 0.1
                            }
                        }
                    }
                    return true
                }

                // Pattern-based classification
                categoryScores.merge(self.performPatternMatching(text)) { $0 + $1 }

                continuation.resume(returning: categoryScores)
            }
        }
    }

    // MARK: - Content Analysis

    private func performContentAnalysis(extractedText: String) -> ClassificationResult {
        let text = extractedText.lowercased()

        // Analyze document structure and content patterns
        let structureScore = analyzeDocumentStructure(text)
        let contentTypeScore = analyzeContentType(text)
        let medicalContextScore = analyzeMedicalContext(text)

        // Combine analysis scores
        var categoryScores: [String: Double] = [:]

        // Merge all scoring approaches
        for (category, score) in structureScore {
            categoryScores[category, default: 0.0] += score * 0.3
        }

        for (category, score) in contentTypeScore {
            categoryScores[category, default: 0.0] += score * 0.4
        }

        for (category, score) in medicalContextScore {
            categoryScores[category, default: 0.0] += score * 0.3
        }

        let bestCategory = categoryScores.max { $0.value < $1.value }
        let category = bestCategory?.key ?? DocumentType.other.rawValue
        let confidence = min(bestCategory?.value ?? 0.0, 1.0)

        return ClassificationResult(
            primaryCategory: category,
            confidence: confidence,
            alternativeCategories: getAlternativeCategories(from: categoryScores, excluding: category),
            classificationMethod: .contentAnalysis,
            keywords: extractContentKeywords(text: extractedText),
            processingTime: 0.01
        )
    }

    private func analyzeDocumentStructure(_ text: String) -> [String: Double] {
        var scores: [String: Double] = [:]

        // Lab results typically have numerical values and ranges
        let labPattern = #"\d+\.?\d*\s*(mg/dL|mmol/L|%|U/L|ng/mL|mEq/L)"#
        if hasPattern(text, pattern: labPattern) {
            scores[DocumentType.labResults.rawValue] = 0.8
        }

        // Prescriptions have medication names and dosages
        let prescriptionPattern = #"\d+\s*(mg|ml|tablets?|capsules?|times?\s+daily|bid|tid|qid)"#
        if hasPattern(text, pattern: prescriptionPattern) {
            scores[DocumentType.prescription.rawValue] = 0.7
        }

        // Imaging reports have specific terminology
        let imagingKeywords = ["radiograph", "mri", "ct scan", "ultrasound", "x-ray", "impression", "findings"]
        if containsAnyKeyword(text, keywords: imagingKeywords) {
            scores[DocumentType.imagingReport.rawValue] = 0.6
        }

        return scores
    }

    private func analyzeContentType(_ text: String) -> [String: Double] {
        var scores: [String: Double] = [:]

        // Discharge summaries have specific sections
        let dischargeSections = ["discharge diagnosis", "hospital course", "discharge medications", "follow-up"]
        if containsMultipleKeywords(text, keywords: dischargeSections, threshold: 2) {
            scores[DocumentType.dischargeSummary.rawValue] = 0.9
        }

        // Surgical reports have surgical terminology
        let surgicalTerms = ["procedure", "incision", "anesthesia", "operative", "surgeon", "postoperative"]
        if containsMultipleKeywords(text, keywords: surgicalTerms, threshold: 3) {
            scores[DocumentType.surgicalReport.rawValue] = 0.8
        }

        // Consultation notes have specific format
        let consultationTerms = ["chief complaint", "history of present illness", "assessment", "plan"]
        if containsMultipleKeywords(text, keywords: consultationTerms, threshold: 2) {
            scores[DocumentType.consultation.rawValue] = 0.7
        }

        return scores
    }

    private func analyzeMedicalContext(_ text: String) -> [String: Double] {
        var scores: [String: Double] = [:]

        // Vaccination records
        let vaccinationTerms = ["vaccine", "vaccination", "immunization", "dose", "series"]
        if containsAnyKeyword(text, keywords: vaccinationTerms) {
            scores[DocumentType.vaccinationRecord.rawValue] = 0.8
        }

        // Insurance documents
        let insuranceTerms = ["coverage", "copay", "deductible", "claim", "policy", "authorization"]
        if containsMultipleKeywords(text, keywords: insuranceTerms, threshold: 2) {
            scores[DocumentType.insurance.rawValue] = 0.9
        }

        // Diagnostic reports
        let diagnosticTerms = ["diagnosis", "differential", "rule out", "consistent with", "suggestive of"]
        if containsAnyKeyword(text, keywords: diagnosticTerms) {
            scores[DocumentType.diagnostic.rawValue] = 0.6
        }

        return scores
    }

    // MARK: - Metadata Classification

    private func classifyFromMetadata(_ metadata: DocumentMetadata) -> ClassificationResult {
        var categoryScores: [String: Double] = [:]

        // Use explicit document type if provided
        if let documentType = metadata.documentType {
            categoryScores[documentType.rawValue] = 1.0
        }

        // Analyze filename for clues
        if let filename = metadata.originalFilename?.lowercased() {
            if filename.contains("lab") || filename.contains("test") {
                categoryScores[DocumentType.labResults.rawValue] = 0.7
            } else if filename.contains("prescription") || filename.contains("rx") {
                categoryScores[DocumentType.prescription.rawValue] = 0.7
            } else if filename.contains("discharge") {
                categoryScores[DocumentType.dischargeSummary.rawValue] = 0.7
            }
        }

        // Analyze provider name for specialty clues
        if let providerName = metadata.providerName?.lowercased() {
            if providerName.contains("lab") || providerName.contains("laboratory") {
                categoryScores[DocumentType.labResults.rawValue] = 0.6
            } else if providerName.contains("radiology") || providerName.contains("imaging") {
                categoryScores[DocumentType.imagingReport.rawValue] = 0.6
            } else if providerName.contains("pharmacy") {
                categoryScores[DocumentType.prescription.rawValue] = 0.6
            }
        }

        let bestCategory = categoryScores.max { $0.value < $1.value }
        let category = bestCategory?.key ?? DocumentType.other.rawValue
        let confidence = bestCategory?.value ?? 0.0

        return ClassificationResult(
            primaryCategory: category,
            confidence: confidence,
            alternativeCategories: getAlternativeCategories(from: categoryScores, excluding: category),
            classificationMethod: .metadata,
            keywords: [],
            processingTime: 0.001
        )
    }

    // MARK: - Result Combination

    private func combineClassificationResults(_ results: [ClassificationResult]) -> ClassificationResult {
        var combinedScores: [String: Double] = [:]
        var allKeywords: Set<String> = []
        var totalProcessingTime = 0.0

        // Weight different classification methods
        let methodWeights: [ClassificationMethod: Double] = [
            .ruleBased: 0.4,
            .naturalLanguageProcessing: 0.3,
            .contentAnalysis: 0.2,
            .metadata: 0.1
        ]

        for result in results {
            let weight = methodWeights[result.classificationMethod] ?? 0.1

            // Add primary category score
            combinedScores[result.primaryCategory, default: 0.0] += result.confidence * weight

            // Add alternative category scores
            for (category, score) in result.alternativeCategories {
                combinedScores[category, default: 0.0] += score * weight * 0.5
            }

            allKeywords.formUnion(result.keywords)
            totalProcessingTime += result.processingTime
        }

        // Find best combined category
        let bestCategory = combinedScores.max { $0.value < $1.value }
        let category = bestCategory?.key ?? DocumentType.other.rawValue
        let confidence = min(bestCategory?.value ?? 0.0, 1.0)

        return ClassificationResult(
            primaryCategory: category,
            confidence: confidence,
            alternativeCategories: getAlternativeCategories(from: combinedScores, excluding: category),
            classificationMethod: .combined,
            keywords: Array(allKeywords),
            processingTime: totalProcessingTime
        )
    }

    // MARK: - Utility Methods

    private func extractMedicalEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag, tag == .personalName || tag == .organizationName {
                let entity = String(text[tokenRange])
                entities.append(entity)
            }
            return true
        }

        return entities
    }

    private func performPatternMatching(_ text: String) -> [String: Double] {
        var scores: [String: Double] = [:]

        let patterns: [(DocumentType, String)] = [
            (.labResults, #"(?i)(complete blood count|cbc|basic metabolic panel|bmp|lipid panel)"#),
            (.prescription, #"(?i)(take \d+.*daily|sig:|dispense:|\d+\s+tabs?)"#),
            (.imagingReport, #"(?i)(chest x-ray|mri of|ct scan|ultrasound|radiologist)"#),
            (.dischargeSummary, #"(?i)(discharge.*diagnosis|discharge.*date|admitted.*for)"#),
            (.surgicalReport, #"(?i)(operative report|procedure performed|surgeon:|anesthesia)"#)
        ]

        for (documentType, pattern) in patterns {
            if hasPattern(text, pattern: pattern) {
                scores[documentType.rawValue, default: 0.0] += 0.6
            }
        }

        return scores
    }

    private func hasPattern(_ text: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    private func containsAnyKeyword(_ text: String, keywords: [String]) -> Bool {
        return keywords.contains { text.lowercased().contains($0.lowercased()) }
    }

    private func containsMultipleKeywords(_ text: String, keywords: [String], threshold: Int) -> Bool {
        let lowercasedText = text.lowercased()
        let matchCount = keywords.filter { lowercasedText.contains($0.lowercased()) }.count
        return matchCount >= threshold
    }

    private func extractMatchedKeywords(text: String, category: String) -> [String] {
        guard let documentType = DocumentType(rawValue: category) else { return [] }

        let rule = medicalClassificationRules.first { $0.category == documentType }
        return rule?.keywords.filter { text.lowercased().contains($0.lowercased()) } ?? []
    }

    private func extractContentKeywords(text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var keywords: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if let tag = tag, tag == .noun || tag == .verb {
                let word = String(text[tokenRange])
                if word.count >= 4 && !isCommonWord(word) {
                    keywords.append(word)
                }
            }
            return true
        }

        return Array(Set(keywords)).prefix(10).map { String($0) }
    }

    private func isCommonWord(_ word: String) -> Bool {
        let commonWords = ["that", "with", "have", "this", "will", "your", "from", "they", "know", "want", "been", "good", "much", "some", "time"]
        return commonWords.contains(word.lowercased())
    }

    private func getAlternativeCategories(from scores: [String: Double], excluding primary: String) -> [String: Double] {
        return scores.filter { $0.key != primary }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .reduce(into: [String: Double]()) { result, element in
                result[element.key] = element.value
            }
    }

    // MARK: - Setup and Configuration

    private func setupNaturalLanguageProcessing() {
        nlProcessor.languageHints = [.english, .chinese]
    }

    private func loadOrCreateMLModel() {
        // In a production app, you would load a pre-trained Core ML model
        // For now, we'll rely on the rule-based and NLP approaches
        print("🤖 DocumentClassifier: Using rule-based and NLP classification")
    }

    // MARK: - Static Configuration

    private static func buildClassificationRules() -> [ClassificationRule] {
        return [
            ClassificationRule(
                category: .labResults,
                keywords: ["blood test", "lab results", "cbc", "complete blood count", "glucose", "cholesterol", "hemoglobin", "white blood cell", "red blood cell", "platelet"],
                weight: 1.0
            ),
            ClassificationRule(
                category: .prescription,
                keywords: ["prescription", "medication", "drug", "dosage", "mg", "ml", "tablets", "capsules", "take", "daily", "twice daily", "pharmacy"],
                weight: 1.0
            ),
            ClassificationRule(
                category: .imagingReport,
                keywords: ["x-ray", "mri", "ct scan", "ultrasound", "mammogram", "radiologist", "imaging", "scan", "contrast", "radiology"],
                weight: 1.0
            ),
            ClassificationRule(
                category: .dischargeSummary,
                keywords: ["discharge", "admission", "hospital course", "diagnosis", "treatment", "follow-up", "discharge date"],
                weight: 1.0
            ),
            ClassificationRule(
                category: .surgicalReport,
                keywords: ["surgery", "operation", "procedure", "surgeon", "anesthesia", "operative", "incision", "postoperative"],
                weight: 1.0
            ),
            ClassificationRule(
                category: .consultation,
                keywords: ["consultation", "chief complaint", "history", "assessment", "plan", "consultant", "specialist"],
                weight: 0.8
            ),
            ClassificationRule(
                category: .vaccinationRecord,
                keywords: ["vaccine", "vaccination", "immunization", "shot", "dose", "series", "booster"],
                weight: 1.0
            ),
            ClassificationRule(
                category: .diagnostic,
                keywords: ["diagnosis", "diagnostic", "test", "result", "findings", "conclusion", "impression"],
                weight: 0.7
            ),
            ClassificationRule(
                category: .insurance,
                keywords: ["insurance", "coverage", "copay", "deductible", "claim", "policy", "benefit", "authorization"],
                weight: 1.0
            )
        ]
    }

    private static func buildMedicalTerminology() -> [String: [String]] {
        return [
            DocumentType.labResults.rawValue: [
                "hemoglobin", "hematocrit", "glucose", "cholesterol", "triglycerides",
                "creatinine", "bun", "ast", "alt", "bilirubin", "albumin"
            ],
            DocumentType.prescription.rawValue: [
                "aspirin", "ibuprofen", "acetaminophen", "lisinopril", "metformin",
                "atorvastatin", "amlodipine", "metoprolol", "omeprazole", "simvastatin"
            ],
            DocumentType.imagingReport.rawValue: [
                "frontal", "lateral", "anterior", "posterior", "opacity", "consolidation",
                "atelectasis", "pneumonia", "effusion", "nodule", "mass"
            ],
            DocumentType.surgicalReport.rawValue: [
                "laparoscopic", "arthroscopic", "endoscopic", "minimally invasive",
                "general anesthesia", "local anesthesia", "sutures", "staples"
            ]
        ]
    }
}

// MARK: - Supporting Types

struct ClassificationRule {
    let category: DocumentType
    let keywords: [String]
    let weight: Double
}

struct ClassificationResult {
    let primaryCategory: String
    let confidence: Double
    let alternativeCategories: [String: Double]
    let classificationMethod: ClassificationMethod
    let keywords: [String]
    let processingTime: Double
    let metadata: [String: Any]

    init(
        primaryCategory: String,
        confidence: Double,
        alternativeCategories: [String: Double],
        classificationMethod: ClassificationMethod,
        keywords: [String],
        processingTime: Double,
        metadata: [String: Any] = [:]
    ) {
        self.primaryCategory = primaryCategory
        self.confidence = confidence
        self.alternativeCategories = alternativeCategories
        self.classificationMethod = classificationMethod
        self.keywords = keywords
        self.processingTime = processingTime
        self.metadata = metadata
    }
}

enum ClassificationMethod {
    case ruleBased
    case naturalLanguageProcessing
    case contentAnalysis
    case metadata
    case combined

    var displayName: String {
        switch self {
        case .ruleBased: return "Rule-Based"
        case .naturalLanguageProcessing: return "NLP"
        case .contentAnalysis: return "Content Analysis"
        case .metadata: return "Metadata"
        case .combined: return "Combined"
        }
    }
}