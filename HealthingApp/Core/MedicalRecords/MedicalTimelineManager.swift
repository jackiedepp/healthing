import Foundation
import CoreData
import Combine

/// Chronological health history timeline and categorization manager
/// Implements REQ-029: Medical history timeline and categorization
@MainActor
class MedicalTimelineManager: ObservableObject {
    static let shared = MedicalTimelineManager()

    @Published var timelineEvents: [TimelineEvent] = []
    @Published var timelineGroupings: [TimelineGroup] = []
    @Published var isLoadingTimeline = false
    @Published var selectedTimelineRange: TimelineRange = .lastYear

    private let healthDataStore = HealthDataStore.shared
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private init() {
        loadTimelineEvents()
    }

    // MARK: - Timeline Event Management

    /// Load and organize medical timeline events
    func loadTimelineEvents() {
        isLoadingTimeline = true

        Task {
            do {
                let events = try await fetchAllTimelineEvents()
                let groupedEvents = groupEventsByTimeAndCategory(events)

                await MainActor.run {
                    self.timelineEvents = events
                    self.timelineGroupings = groupedEvents
                    self.isLoadingTimeline = false
                }

                print("📅 MedicalTimelineManager: Loaded \(events.count) timeline events")
            } catch {
                await MainActor.run {
                    self.isLoadingTimeline = false
                }
                print("❌ MedicalTimelineManager: Failed to load timeline events: \(error)")
            }
        }
    }

    /// Add a medical document to the timeline
    func addDocumentToTimeline(_ document: MedicalDocument) async throws {
        let event = createTimelineEvent(from: document)

        // Insert in chronological order
        await MainActor.run {
            insertEventInOrder(event)
            regenerateTimelineGroupings()
        }

        print("📅 MedicalTimelineManager: Added document to timeline: \(document.title ?? "Unknown")")
    }

    /// Add a health observation to the timeline
    func addObservationToTimeline(_ observation: HealthingObservation) async throws {
        let event = createTimelineEvent(from: observation)

        await MainActor.run {
            insertEventInOrder(event)
            regenerateTimelineGroupings()
        }

        print("📅 MedicalTimelineManager: Added observation to timeline: \(observation.code)")
    }

    /// Remove event from timeline
    func removeEventFromTimeline(_ eventId: String) {
        timelineEvents.removeAll { $0.id == eventId }
        regenerateTimelineGroupings()
    }

    // MARK: - Timeline Event Creation

    private func createTimelineEvent(from document: MedicalDocument) -> TimelineEvent {
        let eventType: TimelineEventType

        if let documentType = document.documentType,
           let type = DocumentType(rawValue: documentType) {
            eventType = .document(type)
        } else {
            eventType = .document(.other)
        }

        return TimelineEvent(
            id: document.id!,
            title: document.title ?? document.originalFilename ?? "Medical Document",
            description: generateDocumentDescription(document),
            date: document.documentDate ?? document.uploadDate ?? Date(),
            eventType: eventType,
            severity: determineSeverity(from: document),
            category: categorizeDocument(document),
            sourceType: .document,
            sourceId: document.id!,
            metadata: createDocumentMetadata(document),
            tags: extractDocumentTags(document)
        )
    }

    private func createTimelineEvent(from observation: HealthingObservation) -> TimelineEvent {
        let eventType: TimelineEventType = .healthMetric(observation.category)

        return TimelineEvent(
            id: observation.id,
            title: formatObservationTitle(observation),
            description: formatObservationDescription(observation),
            date: observation.effectiveDateTime,
            eventType: eventType,
            severity: determineSeverity(from: observation),
            category: observation.category,
            sourceType: .healthData,
            sourceId: observation.id,
            metadata: createObservationMetadata(observation),
            tags: extractObservationTags(observation)
        )
    }

    // MARK: - Event Fetching

    private func fetchAllTimelineEvents() async throws -> [TimelineEvent] {
        return try await withCheckedThrowingContinuation { continuation in
            healthDataStore.persistentContainer.performBackgroundTask { context in
                do {
                    var allEvents: [TimelineEvent] = []

                    // Fetch medical documents
                    let documentRequest: NSFetchRequest<MedicalDocument> = MedicalDocument.fetchRequest()
                    documentRequest.sortDescriptors = [
                        NSSortDescriptor(keyPath: \MedicalDocument.documentDate, ascending: false),
                        NSSortDescriptor(keyPath: \MedicalDocument.uploadDate, ascending: false)
                    ]

                    let documents = try context.fetch(documentRequest)
                    for document in documents {
                        let event = self.createTimelineEvent(from: document)
                        allEvents.append(event)
                    }

                    // Fetch health observations (recent ones)
                    let observationRequest: NSFetchRequest<HealthObservation> = HealthObservation.fetchRequest()
                    observationRequest.sortDescriptors = [
                        NSSortDescriptor(keyPath: \HealthObservation.effectiveDateTime, ascending: false)
                    ]
                    observationRequest.fetchLimit = 500 // Limit to recent observations

                    let observations = try context.fetch(observationRequest)
                    for observationEntity in observations {
                        // Convert to HealthingObservation
                        let observation = HealthingObservation.fromCoreDataEntity(observationEntity)
                        let event = self.createTimelineEvent(from: observation)
                        allEvents.append(event)
                    }

                    // Sort all events by date
                    allEvents.sort { $0.date > $1.date }

                    continuation.resume(returning: allEvents)
                } catch {
                    continuation.resume(throwing: TimelineError.fetchFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Timeline Organization

    private func groupEventsByTimeAndCategory(_ events: [TimelineEvent]) -> [TimelineGroup] {
        let filteredEvents = filterEventsByTimeRange(events, range: selectedTimelineRange)

        var groups: [String: [TimelineEvent]] = [:]

        for event in filteredEvents {
            let groupKey = generateGroupKey(for: event.date, grouping: .monthly)
            groups[groupKey, default: []].append(event)
        }

        let timelineGroups = groups.map { key, events in
            TimelineGroup(
                id: key,
                title: formatGroupTitle(key),
                period: parsePeriodFromKey(key),
                events: events.sorted { $0.date > $1.date },
                eventCounts: calculateEventCounts(events),
                summary: generateGroupSummary(events)
            )
        }.sorted { $0.period.start > $1.period.start }

        return timelineGroups
    }

    private func filterEventsByTimeRange(_ events: [TimelineEvent], range: TimelineRange) -> [TimelineEvent] {
        let cutoffDate: Date

        switch range {
        case .lastWeek:
            cutoffDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        case .lastMonth:
            cutoffDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .lastThreeMonths:
            cutoffDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        case .lastSixMonths:
            cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        case .lastYear:
            cutoffDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        case .allTime:
            return events
        }

        return events.filter { $0.date >= cutoffDate }
    }

    private func generateGroupKey(for date: Date, grouping: TimelineGrouping) -> String {
        let calendar = Calendar.current

        switch grouping {
        case .daily:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            return dateFormatter.string(from: date)
        case .weekly:
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.year, from: date)
            return "\(year)-W\(weekOfYear)"
        case .monthly:
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            return "\(year)-M\(month)"
        case .yearly:
            let year = calendar.component(.year, from: date)
            return "\(year)"
        }
    }

    private func formatGroupTitle(_ key: String) -> String {
        if key.contains("-M") {
            // Monthly format: "2024-M3" -> "March 2024"
            let components = key.components(separatedBy: "-M")
            if components.count == 2,
               let year = Int(components[0]),
               let month = Int(components[1]) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMMM yyyy"
                let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? Date()
                return dateFormatter.string(from: date)
            }
        } else if key.contains("-W") {
            // Weekly format: "2024-W12" -> "Week 12, 2024"
            let components = key.components(separatedBy: "-W")
            if components.count == 2,
               let year = components[0] as String?,
               let week = components[1] as String? {
                return "Week \(week), \(year)"
            }
        } else if key.count == 4, Int(key) != nil {
            // Yearly format: "2024" -> "2024"
            return key
        } else if key.count == 10 {
            // Daily format: "2024-03-15" -> "March 15, 2024"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateFormatter.date(from: key) {
                dateFormatter.dateFormat = "MMMM d, yyyy"
                return dateFormatter.string(from: date)
            }
        }

        return key
    }

    private func parsePeriodFromKey(_ key: String) -> TimePeriod {
        let calendar = Calendar.current

        if key.contains("-M") {
            // Monthly
            let components = key.components(separatedBy: "-M")
            if components.count == 2,
               let year = Int(components[0]),
               let month = Int(components[1]) {
                let startDate = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
                let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) ?? Date()
                return TimePeriod(start: startDate, end: endDate)
            }
        }

        // Default to current month
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
        return TimePeriod(start: startOfMonth, end: endOfMonth)
    }

    private func calculateEventCounts(_ events: [TimelineEvent]) -> EventCounts {
        var counts = EventCounts()

        for event in events {
            switch event.eventType {
            case .document:
                counts.documents += 1
            case .healthMetric:
                counts.healthMetrics += 1
            case .appointment:
                counts.appointments += 1
            case .medication:
                counts.medications += 1
            case .emergency:
                counts.emergencies += 1
            }

            switch event.severity {
            case .low:
                counts.lowSeverity += 1
            case .medium:
                counts.mediumSeverity += 1
            case .high:
                counts.highSeverity += 1
            case .critical:
                counts.criticalSeverity += 1
            }
        }

        counts.total = events.count
        return counts
    }

    private func generateGroupSummary(_ events: [TimelineEvent]) -> String {
        let counts = calculateEventCounts(events)
        var summaryParts: [String] = []

        if counts.documents > 0 {
            summaryParts.append("\(counts.documents) document\(counts.documents == 1 ? "" : "s")")
        }

        if counts.healthMetrics > 0 {
            summaryParts.append("\(counts.healthMetrics) health metric\(counts.healthMetrics == 1 ? "" : "s")")
        }

        if counts.appointments > 0 {
            summaryParts.append("\(counts.appointments) appointment\(counts.appointments == 1 ? "" : "s")")
        }

        if summaryParts.isEmpty {
            return "No events"
        }

        return summaryParts.joined(separator: ", ")
    }

    // MARK: - Timeline Utilities

    private func insertEventInOrder(_ event: TimelineEvent) {
        // Find correct insertion point to maintain chronological order
        for (index, existingEvent) in timelineEvents.enumerated() {
            if event.date > existingEvent.date {
                timelineEvents.insert(event, at: index)
                return
            }
        }

        // Add to end if not inserted
        timelineEvents.append(event)
    }

    private func regenerateTimelineGroupings() {
        timelineGroupings = groupEventsByTimeAndCategory(timelineEvents)
    }

    // MARK: - Content Analysis

    private func generateDocumentDescription(_ document: MedicalDocument) -> String {
        var description = ""

        if let providerName = document.providerName {
            description += "Provider: \(providerName)"
        }

        if let documentType = document.documentType,
           let type = DocumentType(rawValue: documentType) {
            if !description.isEmpty { description += " • " }
            description += "Type: \(type.displayName)"
        }

        if let notes = document.notes, !notes.isEmpty {
            if !description.isEmpty { description += "\n" }
            description += notes
        } else if let extractedText = document.extractedText, !extractedText.isEmpty {
            if !description.isEmpty { description += "\n" }
            let preview = String(extractedText.prefix(100))
            description += "\(preview)\(extractedText.count > 100 ? "..." : "")"
        }

        return description.isEmpty ? "Medical document" : description
    }

    private func formatObservationTitle(_ observation: HealthingObservation) -> String {
        // Try to get a human-readable name for the observation
        let loincMapping = [
            "8867-4": "Heart Rate",
            "55423-8": "Step Count",
            "41981-2": "Active Energy Burned",
            "9279-1": "Respiratory Rate",
            "8310-5": "Body Temperature",
            "39156-5": "Body Mass Index",
            "29463-7": "Body Weight",
            "8302-2": "Body Height"
        ]

        if let title = loincMapping[observation.code] {
            return title
        }

        // Fallback to formatted category and code
        return observation.category.capitalized.replacingOccurrences(of: "-", with: " ")
    }

    private func formatObservationDescription(_ observation: HealthingObservation) -> String {
        var description = ""

        if let quantity = observation.valueQuantity {
            description = "\(quantity.value) \(quantity.unit)"
        }

        if let device = observation.device, !device.type.isEmpty {
            if !description.isEmpty { description += " • " }
            description += "Source: \(device.type.capitalized)"
        }

        return description
    }

    private func determineSeverity(from document: MedicalDocument) -> TimelineEventSeverity {
        // Analyze document type and content to determine severity
        guard let documentType = document.documentType,
              let type = DocumentType(rawValue: documentType) else {
            return .low
        }

        switch type {
        case .surgicalReport:
            return .high
        case .dischargeSummary:
            return .medium
        case .prescription:
            return .medium
        case .labResults:
            return analyzLabResultsSeverity(document)
        case .imagingReport:
            return .medium
        case .diagnostic:
            return .medium
        default:
            return .low
        }
    }

    private func analyzLabResultsSeverity(_ document: MedicalDocument) -> TimelineEventSeverity {
        guard let extractedText = document.extractedText?.lowercased() else {
            return .low
        }

        let criticalKeywords = ["critical", "urgent", "abnormal", "high", "low", "out of range"]
        let highKeywords = ["elevated", "decreased", "borderline"]

        for keyword in criticalKeywords {
            if extractedText.contains(keyword) {
                return .critical
            }
        }

        for keyword in highKeywords {
            if extractedText.contains(keyword) {
                return .high
            }
        }

        return .low
    }

    private func determineSeverity(from observation: HealthingObservation) -> TimelineEventSeverity {
        // Analyze observation values to determine severity
        switch observation.code {
        case "8867-4": // Heart Rate
            if let value = observation.valueQuantity?.value {
                if value < 60 || value > 100 {
                    return .medium
                } else if value < 40 || value > 120 {
                    return .high
                }
            }
        case "8310-5": // Body Temperature
            if let value = observation.valueQuantity?.value {
                if value > 100.4 { // Fahrenheit
                    return .medium
                } else if value > 102 {
                    return .high
                }
            }
        default:
            break
        }

        return .low
    }

    private func categorizeDocument(_ document: MedicalDocument) -> String {
        if let documentType = document.documentType {
            return documentType
        }

        // Try to categorize based on content
        if let extractedText = document.extractedText?.lowercased() {
            if extractedText.contains("lab") || extractedText.contains("test") {
                return DocumentType.labResults.rawValue
            } else if extractedText.contains("prescription") || extractedText.contains("medication") {
                return DocumentType.prescription.rawValue
            } else if extractedText.contains("x-ray") || extractedText.contains("mri") || extractedText.contains("ct") {
                return DocumentType.imagingReport.rawValue
            }
        }

        return "general"
    }

    private func createDocumentMetadata(_ document: MedicalDocument) -> [String: Any] {
        var metadata: [String: Any] = [:]

        metadata["originalFilename"] = document.originalFilename
        metadata["fileSize"] = document.fileSize
        metadata["mimeType"] = document.mimeType
        metadata["uploadDate"] = document.uploadDate
        metadata["ocrConfidence"] = document.ocrConfidence

        if let providerName = document.providerName {
            metadata["providerName"] = providerName
        }

        return metadata
    }

    private func createObservationMetadata(_ observation: HealthingObservation) -> [String: Any] {
        var metadata: [String: Any] = [:]

        metadata["code"] = observation.code
        metadata["status"] = observation.status
        metadata["category"] = observation.category

        if let device = observation.device {
            metadata["deviceType"] = device.type
            metadata["deviceVersion"] = device.version
        }

        return metadata
    }

    private func extractDocumentTags(_ document: MedicalDocument) -> [String] {
        var tags: [String] = []

        if let documentType = document.documentType {
            tags.append(documentType)
        }

        if let providerName = document.providerName {
            tags.append(providerName)
        }

        // Extract tags from content
        if let extractedText = document.extractedText {
            tags.append(contentsOf: extractMedicalTags(from: extractedText))
        }

        return Array(Set(tags)) // Remove duplicates
    }

    private func extractObservationTags(_ observation: HealthingObservation) -> [String] {
        var tags = [observation.category, observation.code]

        if let device = observation.device {
            tags.append(device.type)
        }

        return tags
    }

    private func extractMedicalTags(from text: String) -> [String] {
        let medicalKeywords = [
            "blood", "pressure", "heart", "rate", "temperature", "weight", "height",
            "cholesterol", "glucose", "diabetes", "medication", "prescription",
            "surgery", "operation", "treatment", "therapy", "diagnosis",
            "symptoms", "condition", "disease", "infection", "virus", "bacteria"
        ]

        return medicalKeywords.filter { text.lowercased().contains($0) }
    }

    // MARK: - Public Interface

    /// Change timeline range filter
    func setTimelineRange(_ range: TimelineRange) {
        selectedTimelineRange = range
        regenerateTimelineGroupings()
    }

    /// Get events for a specific date
    func getEventsForDate(_ date: Date) -> [TimelineEvent] {
        let calendar = Calendar.current
        return timelineEvents.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Get events by category
    func getEventsByCategory(_ category: String) -> [TimelineEvent] {
        return timelineEvents.filter { $0.category == category }
    }

    /// Get timeline statistics
    func getTimelineStatistics() -> TimelineStatistics {
        let totalEvents = timelineEvents.count
        let eventCounts = calculateEventCounts(timelineEvents)

        let dateRange: (start: Date?, end: Date?) = {
            guard !timelineEvents.isEmpty else { return (nil, nil) }
            let sortedEvents = timelineEvents.sorted { $0.date < $1.date }
            return (sortedEvents.first?.date, sortedEvents.last?.date)
        }()

        return TimelineStatistics(
            totalEvents: totalEvents,
            eventCounts: eventCounts,
            dateRange: dateRange,
            averageEventsPerMonth: calculateAverageEventsPerMonth()
        )
    }

    private func calculateAverageEventsPerMonth() -> Double {
        guard !timelineEvents.isEmpty else { return 0.0 }

        let sortedEvents = timelineEvents.sorted { $0.date < $1.date }
        guard let firstDate = sortedEvents.first?.date,
              let lastDate = sortedEvents.last?.date else { return 0.0 }

        let monthsDifference = Calendar.current.dateComponents([.month], from: firstDate, to: lastDate).month ?? 1
        return Double(timelineEvents.count) / max(Double(monthsDifference), 1.0)
    }
}

// MARK: - Supporting Types

struct TimelineEvent {
    let id: String
    let title: String
    let description: String
    let date: Date
    let eventType: TimelineEventType
    let severity: TimelineEventSeverity
    let category: String
    let sourceType: TimelineSourceType
    let sourceId: String
    let metadata: [String: Any]
    let tags: [String]
}

enum TimelineEventType {
    case document(DocumentType)
    case healthMetric(String)
    case appointment
    case medication
    case emergency
}

enum TimelineEventSeverity: CaseIterable {
    case low
    case medium
    case high
    case critical

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

enum TimelineSourceType {
    case document
    case healthData
    case manual
}

struct TimelineGroup {
    let id: String
    let title: String
    let period: TimePeriod
    let events: [TimelineEvent]
    let eventCounts: EventCounts
    let summary: String
}

struct TimePeriod {
    let start: Date
    let end: Date
}

struct EventCounts {
    var total: Int = 0
    var documents: Int = 0
    var healthMetrics: Int = 0
    var appointments: Int = 0
    var medications: Int = 0
    var emergencies: Int = 0
    var lowSeverity: Int = 0
    var mediumSeverity: Int = 0
    var highSeverity: Int = 0
    var criticalSeverity: Int = 0
}

enum TimelineRange: CaseIterable {
    case lastWeek
    case lastMonth
    case lastThreeMonths
    case lastSixMonths
    case lastYear
    case allTime

    var displayName: String {
        switch self {
        case .lastWeek: return "Last Week"
        case .lastMonth: return "Last Month"
        case .lastThreeMonths: return "Last 3 Months"
        case .lastSixMonths: return "Last 6 Months"
        case .lastYear: return "Last Year"
        case .allTime: return "All Time"
        }
    }
}

enum TimelineGrouping {
    case daily
    case weekly
    case monthly
    case yearly
}

struct TimelineStatistics {
    let totalEvents: Int
    let eventCounts: EventCounts
    let dateRange: (start: Date?, end: Date?)
    let averageEventsPerMonth: Double
}

enum TimelineError: LocalizedError {
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch timeline events: \(message)"
        }
    }
}