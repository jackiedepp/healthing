import Foundation
import CoreSpotlight
import MobileCoreServices
import CoreData
import NaturalLanguage

/// Full-text search engine for medical documents with Core Spotlight integration
/// Implements REQ-027: Document search and organization capabilities
/// Implements REQ-045: Searchable text from processed documents
@MainActor
class DocumentSearchEngine: ObservableObject {
    static let shared = DocumentSearchEngine()

    @Published var searchResults: [DocumentSearchResult] = []
    @Published var isSearching = false
    @Published var searchSuggestions: [String] = []

    private let healthDataStore = HealthDataStore.shared
    private let nlProcessor = NLLanguageRecognizer()

    // Search index domain identifier
    private let searchDomainIdentifier = "com.healthingapp.medicaldocuments"

    private init() {
        setupNaturalLanguageProcessing()
    }

    // MARK: - Core Spotlight Integration

    /// Index document in Core Spotlight for system-wide search
    func indexDocument(_ document: MedicalDocument) async throws {
        let searchableItem = createSearchableItem(from: document)

        try await withCheckedThrowingContinuation { continuation in
            CSSearchableIndex.default().indexSearchableItems([searchableItem]) { error in
                if let error = error {
                    continuation.resume(throwing: DocumentSearchError.indexingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        print("🔍 DocumentSearchEngine: Indexed document: \(document.title ?? "Unknown")")
    }

    /// Index multiple documents in batch
    func indexDocuments(_ documents: [MedicalDocument]) async throws {
        let searchableItems = documents.map { createSearchableItem(from: $0) }

        try await withCheckedThrowingContinuation { continuation in
            CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
                if let error = error {
                    continuation.resume(throwing: DocumentSearchError.indexingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        print("🔍 DocumentSearchEngine: Indexed \(documents.count) documents")
    }

    /// Remove document from search index
    func removeDocumentFromIndex(_ documentId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [documentId]) { error in
                if let error = error {
                    continuation.resume(throwing: DocumentSearchError.indexRemovalFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        print("🗑️ DocumentSearchEngine: Removed document from index: \(documentId)")
    }

    private func createSearchableItem(from document: MedicalDocument) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(itemContentType: kUTTypeData as String)

        // Basic document information
        attributeSet.title = document.title
        attributeSet.displayName = document.title
        attributeSet.identifier = document.id
        attributeSet.contentDescription = document.notes

        // Document metadata
        attributeSet.creator = document.providerName
        attributeSet.creationDate = document.documentDate ?? document.uploadDate
        attributeSet.contentModificationDate = document.createdDate

        // Medical-specific attributes
        attributeSet.subject = document.documentType
        attributeSet.textContent = document.extractedText
        attributeSet.keywords = extractKeywords(from: document)

        // File information
        attributeSet.contentType = document.mimeType
        attributeSet.contentSize = NSNumber(value: document.fileSize)

        // Custom attributes for medical documents
        attributeSet.setValue(document.documentType, forCustomKey: CSCustomAttributeKey(keyName: "documentType")!)
        attributeSet.setValue(document.providerName, forCustomKey: CSCustomAttributeKey(keyName: "providerName")!)
        attributeSet.setValue(document.patientName, forCustomKey: CSCustomAttributeKey(keyName: "patientName")!)
        attributeSet.setValue(document.classificationResult, forCustomKey: CSCustomAttributeKey(keyName: "classificationResult")!)

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: document.id!,
            domainIdentifier: searchDomainIdentifier,
            attributeSet: attributeSet
        )

        return searchableItem
    }

    // MARK: - Search Functionality

    /// Perform full-text search across medical documents
    func searchDocuments(
        query: String,
        filters: SearchFilters = SearchFilters(),
        sortBy: SearchSortOption = .relevance,
        limit: Int = 50
    ) async throws -> [DocumentSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        isSearching = true
        defer { isSearching = false }

        // Perform both Core Spotlight search and local database search
        let spotlightResults = try await performSpotlightSearch(query: query, limit: limit)
        let databaseResults = try await performDatabaseSearch(query: query, filters: filters, limit: limit)

        // Merge and deduplicate results
        let mergedResults = mergeSearchResults(spotlightResults, databaseResults)

        // Sort results
        let sortedResults = sortSearchResults(mergedResults, by: sortBy, query: query)

        // Update published results
        searchResults = Array(sortedResults.prefix(limit))

        print("🔍 DocumentSearchEngine: Found \(searchResults.count) results for query: '\(query)'")
        return searchResults
    }

    /// Perform Core Spotlight search
    private func performSpotlightSearch(query: String, limit: Int) async throws -> [DocumentSearchResult] {
        let searchQuery = CSSearchQuery(queryString: query, attributes: ["title", "textContent", "keywords"])
        searchQuery.maxCount = limit

        return try await withCheckedThrowingContinuation { continuation in
            var results: [DocumentSearchResult] = []

            searchQuery.foundItemsHandler = { items in
                for item in items {
                    if let documentId = item.uniqueIdentifier,
                       let title = item.attributeSet.title {
                        let result = DocumentSearchResult(
                            documentId: documentId,
                            title: title,
                            snippet: item.attributeSet.contentDescription ?? "",
                            relevanceScore: Double(item.rankingHint),
                            searchSource: .spotlight,
                            highlightedText: self.extractHighlightedText(from: item, query: query),
                            documentType: item.attributeSet.subject,
                            documentDate: item.attributeSet.creationDate,
                            providerName: item.attributeSet.creator
                        )
                        results.append(result)
                    }
                }
            }

            searchQuery.completionHandler = { error in
                if let error = error {
                    continuation.resume(throwing: DocumentSearchError.searchFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: results)
                }
            }

            searchQuery.start()
        }
    }

    /// Perform local database search
    private func performDatabaseSearch(
        query: String,
        filters: SearchFilters,
        limit: Int
    ) async throws -> [DocumentSearchResult] {
        return try await withCheckedThrowingContinuation { continuation in
            healthDataStore.persistentContainer.performBackgroundTask { context in
                do {
                    let request: NSFetchRequest<MedicalDocument> = MedicalDocument.fetchRequest()

                    // Build search predicates
                    var predicates: [NSPredicate] = []

                    // Text search predicate
                    let textPredicate = self.buildTextSearchPredicate(query: query)
                    predicates.append(textPredicate)

                    // Apply filters
                    if let documentTypes = filters.documentTypes, !documentTypes.isEmpty {
                        let typePredicate = NSPredicate(format: "documentType IN %@", documentTypes)
                        predicates.append(typePredicate)
                    }

                    if let dateRange = filters.dateRange {
                        let datePredicate = NSPredicate(
                            format: "documentDate >= %@ AND documentDate <= %@",
                            dateRange.start as NSDate,
                            dateRange.end as NSDate
                        )
                        predicates.append(datePredicate)
                    }

                    if let providerNames = filters.providerNames, !providerNames.isEmpty {
                        let providerPredicate = NSPredicate(format: "providerName IN %@", providerNames)
                        predicates.append(providerPredicate)
                    }

                    // Combine predicates
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                    request.fetchLimit = limit

                    let documents = try context.fetch(request)

                    let results = documents.map { document in
                        DocumentSearchResult(
                            documentId: document.id!,
                            title: document.title ?? document.originalFilename ?? "Unknown",
                            snippet: self.generateSnippet(from: document, query: query),
                            relevanceScore: self.calculateRelevanceScore(document: document, query: query),
                            searchSource: .database,
                            highlightedText: self.highlightQueryInText(document.extractedText, query: query),
                            documentType: document.documentType,
                            documentDate: document.documentDate ?? document.uploadDate,
                            providerName: document.providerName
                        )
                    }

                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: DocumentSearchError.searchFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Search Query Building

    private func buildTextSearchPredicate(query: String) -> NSPredicate {
        let searchTerms = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        var predicates: [NSPredicate] = []

        for term in searchTerms {
            let termPredicates = [
                NSPredicate(format: "title CONTAINS[cd] %@", term),
                NSPredicate(format: "extractedText CONTAINS[cd] %@", term),
                NSPredicate(format: "notes CONTAINS[cd] %@", term),
                NSPredicate(format: "searchKeywords CONTAINS[cd] %@", term),
                NSPredicate(format: "providerName CONTAINS[cd] %@", term),
                NSPredicate(format: "classificationResult CONTAINS[cd] %@", term)
            ]

            let orPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: termPredicates)
            predicates.append(orPredicate)
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    // MARK: - Search Suggestions

    /// Generate search suggestions based on query
    func generateSearchSuggestions(for query: String) async -> [String] {
        guard query.count >= 2 else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            healthDataStore.persistentContainer.performBackgroundTask { context in
                do {
                    // Get distinct values from relevant fields
                    var suggestions: Set<String> = []

                    // Search in document titles
                    let titleRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "MedicalDocument")
                    titleRequest.resultType = .dictionaryResultType
                    titleRequest.propertiesToFetch = ["title"]
                    titleRequest.predicate = NSPredicate(format: "title CONTAINS[cd] %@", query)

                    let titleResults = try context.fetch(titleRequest) as! [NSDictionary]
                    for result in titleResults {
                        if let title = result["title"] as? String {
                            suggestions.insert(title)
                        }
                    }

                    // Search in document types
                    let typeRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "MedicalDocument")
                    typeRequest.resultType = .dictionaryResultType
                    typeRequest.propertiesToFetch = ["documentType"]
                    typeRequest.predicate = NSPredicate(format: "documentType CONTAINS[cd] %@", query)

                    let typeResults = try context.fetch(typeRequest) as! [NSDictionary]
                    for result in typeResults {
                        if let type = result["documentType"] as? String {
                            suggestions.insert(DocumentType(rawValue: type)?.displayName ?? type)
                        }
                    }

                    // Search in provider names
                    let providerRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "MedicalDocument")
                    providerRequest.resultType = .dictionaryResultType
                    providerRequest.propertiesToFetch = ["providerName"]
                    providerRequest.predicate = NSPredicate(format: "providerName CONTAINS[cd] %@", query)

                    let providerResults = try context.fetch(providerRequest) as! [NSDictionary]
                    for result in providerResults {
                        if let provider = result["providerName"] as? String {
                            suggestions.insert(provider)
                        }
                    }

                    // Add medical terminology suggestions
                    suggestions.formUnion(self.getMedicalTermSuggestions(for: query))

                    let sortedSuggestions = Array(suggestions)
                        .filter { $0.localizedCaseInsensitiveContains(query) }
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                        .prefix(10)

                    continuation.resume(returning: Array(sortedSuggestions))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func getMedicalTermSuggestions(for query: String) -> [String] {
        let medicalTerms = [
            "Blood test", "X-ray", "MRI", "CT scan", "Ultrasound",
            "Blood pressure", "Heart rate", "Temperature", "Weight",
            "Prescription", "Medication", "Dosage", "Treatment",
            "Diagnosis", "Symptoms", "Consultation", "Follow-up",
            "Lab results", "Pathology", "Radiology", "Cardiology",
            "Neurology", "Oncology", "Pediatrics", "Surgery",
            "Emergency", "Urgent care", "Primary care", "Specialist"
        ]

        return medicalTerms.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Natural Language Processing

    private func setupNaturalLanguageProcessing() {
        nlProcessor.languageHints = [.english, .chinese]
    }

    /// Extract keywords from document for search indexing
    private func extractKeywords(from document: MedicalDocument) -> [String] {
        var keywords: [String] = []

        // Add document type
        if let documentType = document.documentType {
            keywords.append(documentType)
            if let type = DocumentType(rawValue: documentType) {
                keywords.append(type.displayName)
            }
        }

        // Add provider name
        if let providerName = document.providerName {
            keywords.append(providerName)
        }

        // Extract keywords from extracted text
        if let extractedText = document.extractedText {
            keywords.append(contentsOf: extractMedicalKeywords(from: extractedText))
        }

        // Add classification result
        if let classification = document.classificationResult {
            keywords.append(classification)
        }

        return Array(Set(keywords)) // Remove duplicates
    }

    private func extractMedicalKeywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var keywords: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag, tag == .personalName || tag == .organizationName {
                let keyword = String(text[tokenRange])
                keywords.append(keyword)
            }
            return true
        }

        // Add medical-specific terms
        keywords.append(contentsOf: extractMedicalTerms(from: text))

        return keywords.filter { $0.count >= 3 } // Filter out very short terms
    }

    private func extractMedicalTerms(from text: String) -> [String] {
        let medicalPatterns = [
            #"\b\d+\s*(mg|ml|mcg|g|kg|lbs|mmHg|bpm)\b"#, // Measurements
            #"\b(Dr\.|Doctor|MD|PhD|RN|PA)\s+[A-Z][a-z]+"#, // Medical titles
            #"\b[A-Z]{2,}\b"#, // Medical abbreviations
            #"\b\d{1,3}\/\d{1,3}\b"#, // Blood pressure readings
            #"\b\d+\.\d+\b"#, // Decimal numbers (lab values)
        ]

        var terms: [String] = []

        for pattern in medicalPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

                for match in matches {
                    if let range = Range(match.range, in: text) {
                        terms.append(String(text[range]))
                    }
                }
            } catch {
                continue
            }
        }

        return terms
    }

    // MARK: - Search Result Processing

    private func mergeSearchResults(
        _ spotlightResults: [DocumentSearchResult],
        _ databaseResults: [DocumentSearchResult]
    ) -> [DocumentSearchResult] {
        var mergedResults: [String: DocumentSearchResult] = [:]

        // Add Spotlight results
        for result in spotlightResults {
            mergedResults[result.documentId] = result
        }

        // Add or update with database results
        for result in databaseResults {
            if let existing = mergedResults[result.documentId] {
                // Merge scores (use higher score)
                let updatedResult = DocumentSearchResult(
                    documentId: result.documentId,
                    title: result.title,
                    snippet: result.snippet.isEmpty ? existing.snippet : result.snippet,
                    relevanceScore: max(existing.relevanceScore, result.relevanceScore),
                    searchSource: .combined,
                    highlightedText: result.highlightedText ?? existing.highlightedText,
                    documentType: result.documentType,
                    documentDate: result.documentDate,
                    providerName: result.providerName
                )
                mergedResults[result.documentId] = updatedResult
            } else {
                mergedResults[result.documentId] = result
            }
        }

        return Array(mergedResults.values)
    }

    private func sortSearchResults(
        _ results: [DocumentSearchResult],
        by sortOption: SearchSortOption,
        query: String
    ) -> [DocumentSearchResult] {
        switch sortOption {
        case .relevance:
            return results.sorted { $0.relevanceScore > $1.relevanceScore }
        case .dateNewest:
            return results.sorted { ($0.documentDate ?? Date.distantPast) > ($1.documentDate ?? Date.distantPast) }
        case .dateOldest:
            return results.sorted { ($0.documentDate ?? Date.distantPast) < ($1.documentDate ?? Date.distantPast) }
        case .title:
            return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .documentType:
            return results.sorted { ($0.documentType ?? "").localizedCaseInsensitiveCompare($1.documentType ?? "") == .orderedAscending }
        }
    }

    private func generateSnippet(from document: MedicalDocument, query: String) -> String {
        guard let text = document.extractedText, !text.isEmpty else {
            return document.notes ?? ""
        }

        let queryTerms = query.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let sentences = text.components(separatedBy: .newlines)

        for sentence in sentences {
            let lowercaseSentence = sentence.lowercased()
            for term in queryTerms {
                if lowercaseSentence.contains(term) {
                    let maxSnippetLength = 150
                    if sentence.count <= maxSnippetLength {
                        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        let startIndex = max(0, sentence.count - maxSnippetLength)
                        let snippet = String(sentence.suffix(maxSnippetLength))
                        return "..." + snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        // Fallback to first 150 characters
        let maxLength = 150
        if text.count <= maxLength {
            return text
        } else {
            return String(text.prefix(maxLength)) + "..."
        }
    }

    private func calculateRelevanceScore(document: MedicalDocument, query: String) -> Double {
        var score = 0.0
        let queryTerms = query.lowercased().components(separatedBy: .whitespacesAndNewlines)

        // Title match gets highest score
        if let title = document.title?.lowercased() {
            for term in queryTerms {
                if title.contains(term) {
                    score += 3.0
                }
            }
        }

        // Document type match
        if let documentType = document.documentType?.lowercased() {
            for term in queryTerms {
                if documentType.contains(term) {
                    score += 2.0
                }
            }
        }

        // Provider name match
        if let providerName = document.providerName?.lowercased() {
            for term in queryTerms {
                if providerName.contains(term) {
                    score += 1.5
                }
            }
        }

        // Extracted text match
        if let extractedText = document.extractedText?.lowercased() {
            for term in queryTerms {
                if extractedText.contains(term) {
                    score += 1.0
                }
            }
        }

        // OCR confidence bonus
        score += Double(document.ocrConfidence) * 0.1

        // Classification confidence bonus
        score += Double(document.classificationConfidence) * 0.1

        return score
    }

    private func extractHighlightedText(from item: CSSearchableItem, query: String) -> String? {
        return item.attributeSet.textContent
    }

    private func highlightQueryInText(_ text: String?, query: String) -> String? {
        guard let text = text else { return nil }

        let queryTerms = query.components(separatedBy: .whitespacesAndNewlines)
        var highlightedText = text

        for term in queryTerms {
            highlightedText = highlightedText.replacingOccurrences(
                of: term,
                with: "**\(term)**",
                options: .caseInsensitive
            )
        }

        return highlightedText
    }

    // MARK: - Public Interface

    /// Clear all search results
    func clearSearchResults() {
        searchResults.removeAll()
        searchSuggestions.removeAll()
    }

    /// Get recent searches
    func getRecentSearches() -> [String] {
        // This would typically load from UserDefaults or Core Data
        return []
    }

    /// Save search query to recent searches
    func saveSearchQuery(_ query: String) {
        // Implementation would save to UserDefaults or Core Data
    }
}

// MARK: - Supporting Types

struct DocumentSearchResult {
    let documentId: String
    let title: String
    let snippet: String
    let relevanceScore: Double
    let searchSource: SearchSource
    let highlightedText: String?
    let documentType: String?
    let documentDate: Date?
    let providerName: String?
}

enum SearchSource {
    case spotlight
    case database
    case combined
}

struct SearchFilters {
    let documentTypes: [String]?
    let dateRange: DateRange?
    let providerNames: [String]?
    let minConfidence: Double?

    init(
        documentTypes: [String]? = nil,
        dateRange: DateRange? = nil,
        providerNames: [String]? = nil,
        minConfidence: Double? = nil
    ) {
        self.documentTypes = documentTypes
        self.dateRange = dateRange
        self.providerNames = providerNames
        self.minConfidence = minConfidence
    }
}

struct DateRange {
    let start: Date
    let end: Date
}

enum SearchSortOption {
    case relevance
    case dateNewest
    case dateOldest
    case title
    case documentType
}

enum DocumentSearchError: LocalizedError {
    case indexingFailed(String)
    case indexRemovalFailed(String)
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .indexingFailed(let message):
            return "Failed to index document: \(message)"
        case .indexRemovalFailed(let message):
            return "Failed to remove document from index: \(message)"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        }
    }
}