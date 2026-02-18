import Foundation
import SwiftUI
import Combine

/// Multi-source data consolidation and deduplication processor
/// Implements REQ-025: Multi-device data consolidation and deduplication
/// Implements REQ-067: Device-specific data source identification
@MainActor
class WearableDataProcessor: ObservableObject {
    static let shared = WearableDataProcessor()

    @Published var processingStats = DataProcessingStats()
    @Published var consolidationRules = DataConsolidationRules()

    private let dataStore = HealthDataStore.shared
    private let conflictResolver = ConflictResolutionService.shared
    private let securityManager = SecurityManager.shared

    // Data source priorities for different measurement types
    private let dataSourcePriorities: [String: [WearableDataSource: Int]] = [
        "8867-4": [ // Heart Rate
            .appleWatch: 95,
            .garminDevice: 90,
            .fitbitDevice: 85,
            .manualEntry: 70
        ],
        "55423-8": [ // Step Count
            .appleWatch: 90,
            .garminDevice: 95, // Garmin often more accurate for steps
            .fitbitDevice: 90,
            .manualEntry: 60
        ],
        "41981-2": [ // Active Energy
            .appleWatch: 95,
            .garminDevice: 90,
            .fitbitDevice: 85,
            .manualEntry: 70
        ],
        "93832-4": [ // Sleep Analysis
            .appleWatch: 85,
            .garminDevice: 90, // Garmin often better for sleep tracking
            .fitbitDevice: 95,  // Fitbit typically best for sleep
            .manualEntry: 60
        ]
    ]

    private init() {
        setupProcessingRules()
    }

    // MARK: - Processing Setup

    private func setupProcessingRules() {
        // Configure default consolidation rules
        consolidationRules = DataConsolidationRules(
            duplicateTimeWindow: 300, // 5 minutes
            enableSmartAveraging: true,
            enableOutlierDetection: true,
            maxDeviationPercentage: 25.0,
            enableCrossPlatformValidation: true
        )

        print("📊 WearableDataProcessor: Processing rules configured")
    }

    // MARK: - Main Processing Pipeline

    /// Process wearable data through consolidation and deduplication pipeline
    func processWearableData(_ observation: HealthingObservation, from source: WearableDataSource) async {
        processingStats.totalProcessed += 1

        print("📊 WearableDataProcessor: Processing \(observation.code) from \(source.rawValue)")

        do {
            // Step 1: Identify and tag data source
            let taggedObservation = tagDataSource(observation, source: source)

            // Step 2: Detect duplicates and similar measurements
            let duplicates = await detectDuplicates(for: taggedObservation)

            // Step 3: Apply consolidation strategy
            let consolidatedObservation = try await consolidateData(
                taggedObservation,
                duplicates: duplicates,
                source: source
            )

            // Step 4: Quality validation and outlier detection
            let validatedObservation = try await validateDataQuality(consolidatedObservation)

            // Step 5: Store final processed observation
            try await dataStore.storeHealthObservation(validatedObservation)

            processingStats.successfullyProcessed += 1
            print("✅ Successfully processed \(observation.code) from \(source.rawValue)")

        } catch {
            processingStats.processingErrors += 1
            print("❌ Failed to process \(observation.code) from \(source.rawValue): \(error)")
        }
    }

    // MARK: - Data Source Tagging

    /// Tag observation with data source information
    private func tagDataSource(_ observation: HealthingObservation, source: WearableDataSource) -> HealthingObservation {
        var taggedObservation = observation

        // Update device information to reflect the specific source
        let sourceDevice = HealthingDevice(
            id: "\(source.rawValue)-\(UUID().uuidString)",
            identifier: source.deviceIdentifier,
            displayName: source.displayName,
            type: source.rawValue,
            manufacturer: source.manufacturer,
            modelNumber: source.modelNumber,
            version: source.version,
            status: "active"
        )

        taggedObservation.device = sourceDevice
        taggedObservation.performer = source.rawValue

        // Add source metadata to note
        let sourceMetadata = "Source: \(source.displayName) | Accuracy: \(source.accuracyRating)/100"
        taggedObservation.note = [taggedObservation.note, sourceMetadata].compactMap { $0 }.joined(separator: " | ")

        return taggedObservation
    }

    // MARK: - Duplicate Detection

    /// Detect duplicate and similar measurements from different sources
    private func detectDuplicates(for observation: HealthingObservation) async -> [HealthingObservation] {
        let timeWindow = consolidationRules.duplicateTimeWindow
        let startTime = observation.effectiveDateTime.addingTimeInterval(-timeWindow)
        let endTime = observation.effectiveDateTime.addingTimeInterval(timeWindow)

        do {
            // Fetch observations in the time window with same measurement type
            let existingObservations = try await dataStore.fetchHealthObservations(
                category: observation.category,
                dateRange: startTime...endTime,
                limit: 50
            )

            // Filter for same LOINC code (measurement type)
            let duplicates = existingObservations.filter { existing in
                existing.id != observation.id &&
                existing.code == observation.code &&
                abs(existing.effectiveDateTime.timeIntervalSince(observation.effectiveDateTime)) < timeWindow
            }

            if !duplicates.isEmpty {
                processingStats.duplicatesDetected += duplicates.count
                print("🔍 Detected \(duplicates.count) potential duplicates for \(observation.code)")
            }

            return duplicates

        } catch {
            print("❌ Failed to detect duplicates: \(error)")
            return []
        }
    }

    // MARK: - Data Consolidation

    /// Consolidate data using various strategies based on source and data type
    private func consolidateData(
        _ observation: HealthingObservation,
        duplicates: [HealthingObservation],
        source: WearableDataSource
    ) async throws -> HealthingObservation {

        guard !duplicates.isEmpty else {
            return observation // No duplicates, return as-is
        }

        let allObservations = [observation] + duplicates

        // Choose consolidation strategy based on data type and sources
        let strategy = getConsolidationStrategy(for: observation.code, observations: allObservations)

        switch strategy {
        case .prioritizeSource:
            return consolidateBySourcePriority(allObservations, currentSource: source)

        case .averageValues:
            return try consolidateByAveraging(allObservations, primaryObservation: observation)

        case .smartWeighting:
            return try consolidateBySmartWeighting(allObservations, currentSource: source)

        case .crossValidation:
            return try consolidateByCrossValidation(allObservations, currentSource: source)

        case .keepMostRecent:
            return consolidateByRecency(allObservations)

        case .useHighestAccuracy:
            return consolidateByAccuracy(allObservations)
        }
    }

    /// Determine the best consolidation strategy for the data type and sources
    private func getConsolidationStrategy(for loincCode: String, observations: [HealthingObservation]) -> ConsolidationStrategy {
        let sources = Set(observations.compactMap { $0.performer })

        // High-precision measurements - prioritize most accurate source
        if ["8867-4", "8480-6", "8462-4"].contains(loincCode) { // Heart rate, blood pressure
            return .prioritizeSource
        }

        // Activity measurements - smart weighting works well
        if ["55423-8", "41981-2", "41953-1"].contains(loincCode) { // Steps, energy, distance
            return sources.count > 2 ? .smartWeighting : .averageValues
        }

        // Sleep and wellness - cross-validation for accuracy
        if ["93832-4"].contains(loincCode) { // Sleep analysis
            return .crossValidation
        }

        // Body measurements - use most recent from reliable source
        if ["29463-7", "8302-2", "39156-5"].contains(loincCode) { // Weight, height, BMI
            return .useHighestAccuracy
        }

        // Default strategy
        return consolidationRules.enableSmartAveraging ? .smartWeighting : .prioritizeSource
    }

    /// Consolidate by data source priority
    private func consolidateBySourcePriority(_ observations: [HealthingObservation], currentSource: WearableDataSource) -> HealthingObservation {
        let loincCode = observations.first?.code ?? ""
        let sourcePriorities = dataSourcePriorities[loincCode] ?? [:]

        let sortedObservations = observations.sorted { obs1, obs2 in
            let source1 = WearableDataSource(rawValue: obs1.performer ?? "unknown") ?? .unknown
            let source2 = WearableDataSource(rawValue: obs2.performer ?? "unknown") ?? .unknown

            let priority1 = sourcePriorities[source1] ?? 0
            let priority2 = sourcePriorities[source2] ?? 0

            return priority1 > priority2
        }

        let winner = sortedObservations.first!
        print("📊 Consolidated by source priority - winner: \(winner.performer ?? "unknown")")

        processingStats.consolidatedByPriority += 1
        return winner
    }

    /// Consolidate by averaging values
    private func consolidateByAveraging(_ observations: [HealthingObservation], primaryObservation: HealthingObservation) throws -> HealthingObservation {
        guard observations.allSatisfy({ $0.valueQuantity != nil }) else {
            throw DataProcessingError.invalidDataForAveraging
        }

        let values = observations.compactMap { $0.valueQuantity?.value }
        guard !values.isEmpty else {
            throw DataProcessingError.noValuesToAverage
        }

        let averageValue = values.reduce(0, +) / Double(values.count)
        let standardDeviation = calculateStandardDeviation(values)

        var consolidatedObservation = primaryObservation
        consolidatedObservation.valueQuantity?.value = averageValue

        // Add consolidation metadata
        let sourceNames = observations.compactMap { $0.performer }.joined(separator: ", ")
        consolidatedObservation.note = "Averaged from \(values.count) sources: \(sourceNames) | StdDev: \(String(format: "%.2f", standardDeviation))"

        print("📊 Consolidated by averaging - result: \(averageValue) (±\(String(format: "%.2f", standardDeviation)))")

        processingStats.consolidatedByAveraging += 1
        return consolidatedObservation
    }

    /// Consolidate using smart weighting based on source accuracy and recency
    private func consolidateBySmartWeighting(_ observations: [HealthingObservation], currentSource: WearableDataSource) throws -> HealthingObservation {
        guard observations.allSatisfy({ $0.valueQuantity != nil }) else {
            throw DataProcessingError.invalidDataForAveraging
        }

        var weightedSum = 0.0
        var totalWeight = 0.0

        let now = Date()

        for observation in observations {
            guard let value = observation.valueQuantity?.value else { continue }

            let source = WearableDataSource(rawValue: observation.performer ?? "unknown") ?? .unknown

            // Calculate weight based on source accuracy
            let accuracyWeight = Double(source.accuracyRating) / 100.0

            // Calculate recency weight (more recent = higher weight)
            let timeAgo = now.timeIntervalSince(observation.effectiveDateTime)
            let recencyWeight = max(0.1, 1.0 - (timeAgo / 3600.0)) // Decay over 1 hour

            let finalWeight = accuracyWeight * recencyWeight

            weightedSum += value * finalWeight
            totalWeight += finalWeight
        }

        guard totalWeight > 0 else {
            throw DataProcessingError.noValuesToAverage
        }

        let weightedAverage = weightedSum / totalWeight

        var consolidatedObservation = observations.first!
        consolidatedObservation.valueQuantity?.value = weightedAverage

        let sourceNames = observations.compactMap { $0.performer }.joined(separator: ", ")
        consolidatedObservation.note = "Weighted average from \(observations.count) sources: \(sourceNames)"

        print("📊 Consolidated by smart weighting - result: \(weightedAverage)")

        processingStats.consolidatedByWeighting += 1
        return consolidatedObservation
    }

    /// Consolidate using cross-validation between sources
    private func consolidateByCrossValidation(_ observations: [HealthingObservation], currentSource: WearableDataSource) throws -> HealthingObservation {
        guard observations.count >= 2,
              observations.allSatisfy({ $0.valueQuantity != nil }) else {
            return observations.first!
        }

        let values = observations.compactMap { $0.valueQuantity?.value }
        let mean = values.reduce(0, +) / Double(values.count)
        let stdDev = calculateStandardDeviation(values)

        // Filter out outliers beyond 2 standard deviations
        let validObservations = observations.filter { observation in
            guard let value = observation.valueQuantity?.value else { return false }
            return abs(value - mean) <= 2.0 * stdDev
        }

        if validObservations.count < observations.count {
            print("📊 Cross-validation removed \(observations.count - validObservations.count) outliers")
            processingStats.outliersRemoved += observations.count - validObservations.count
        }

        // Use the most accurate source from validated observations
        return consolidateByAccuracy(validObservations.isEmpty ? observations : validObservations)
    }

    /// Consolidate by keeping the most recent observation
    private func consolidateByRecency(_ observations: [HealthingObservation]) -> HealthingObservation {
        let mostRecent = observations.max(by: { $0.effectiveDateTime < $1.effectiveDateTime })!

        print("📊 Consolidated by recency - selected: \(mostRecent.effectiveDateTime)")

        processingStats.consolidatedByRecency += 1
        return mostRecent
    }

    /// Consolidate by using the highest accuracy source
    private func consolidateByAccuracy(_ observations: [HealthingObservation]) -> HealthingObservation {
        let sortedByAccuracy = observations.sorted { obs1, obs2 in
            let source1 = WearableDataSource(rawValue: obs1.performer ?? "unknown") ?? .unknown
            let source2 = WearableDataSource(rawValue: obs2.performer ?? "unknown") ?? .unknown

            return source1.accuracyRating > source2.accuracyRating
        }

        let winner = sortedByAccuracy.first!
        print("📊 Consolidated by accuracy - winner: \(winner.performer ?? "unknown")")

        processingStats.consolidatedByAccuracy += 1
        return winner
    }

    // MARK: - Data Quality Validation

    /// Validate data quality and detect outliers
    private func validateDataQuality(_ observation: HealthingObservation) async throws -> HealthingObservation {
        guard consolidationRules.enableOutlierDetection,
              let value = observation.valueQuantity?.value else {
            return observation
        }

        // Get historical data for comparison
        let historicalData = try await getHistoricalData(for: observation.code, days: 30)

        if historicalData.isEmpty {
            return observation // No historical data to compare against
        }

        let historicalValues = historicalData.compactMap { $0.valueQuantity?.value }
        let historicalMean = historicalValues.reduce(0, +) / Double(historicalValues.count)
        let historicalStdDev = calculateStandardDeviation(historicalValues)

        // Check if current value is an outlier
        let deviationFromMean = abs(value - historicalMean) / historicalMean * 100.0

        if deviationFromMean > consolidationRules.maxDeviationPercentage {
            print("⚠️ Potential outlier detected: \(value) vs historical mean \(historicalMean) (deviation: \(deviationFromMean)%)")

            // Add outlier flag to observation
            var validatedObservation = observation
            validatedObservation.note = (validatedObservation.note ?? "") + " | OUTLIER_DETECTED: \(String(format: "%.1f", deviationFromMean))% deviation"

            processingStats.outliersDetected += 1
            return validatedObservation
        }

        return observation
    }

    /// Get historical data for comparison
    private func getHistoricalData(for loincCode: String, days: Int) async throws -> [HealthingObservation] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let endDate = Date()

        return try await dataStore.fetchHealthObservations(
            category: nil,
            dateRange: startDate...endDate,
            limit: 100
        ).filter { $0.code == loincCode }
    }

    // MARK: - Utility Functions

    /// Calculate standard deviation
    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDeviations = values.map { pow($0 - mean, 2) }
        let variance = squaredDeviations.reduce(0, +) / Double(values.count - 1)

        return sqrt(variance)
    }

    // MARK: - Configuration

    /// Update consolidation rules
    func updateConsolidationRules(_ rules: DataConsolidationRules) {
        consolidationRules = rules
        print("📊 WearableDataProcessor: Consolidation rules updated")
    }

    /// Get processing statistics
    func getProcessingStats() -> DataProcessingStats {
        return processingStats
    }

    /// Reset processing statistics
    func resetProcessingStats() {
        processingStats = DataProcessingStats()
        print("📊 WearableDataProcessor: Processing statistics reset")
    }
}

// MARK: - Supporting Types

enum WearableDataSource: String, CaseIterable {
    case appleWatch = "apple-watch"
    case garminDevice = "garmin-device"
    case fitbitDevice = "fitbit-device"
    case manualEntry = "manual-entry"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .garminDevice: return "Garmin Device"
        case .fitbitDevice: return "Fitbit Device"
        case .manualEntry: return "Manual Entry"
        case .unknown: return "Unknown"
        }
    }

    var manufacturer: String {
        switch self {
        case .appleWatch: return "Apple Inc."
        case .garminDevice: return "Garmin Ltd."
        case .fitbitDevice: return "Fitbit Inc."
        case .manualEntry: return "User"
        case .unknown: return "Unknown"
        }
    }

    var deviceIdentifier: String {
        switch self {
        case .appleWatch: return "com.apple.watch"
        case .garminDevice: return "com.garmin.device"
        case .fitbitDevice: return "com.fitbit.device"
        case .manualEntry: return "com.healthing.manual"
        case .unknown: return "com.unknown.device"
        }
    }

    var modelNumber: String? {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .garminDevice: return "Garmin"
        case .fitbitDevice: return "Fitbit"
        case .manualEntry: return nil
        case .unknown: return nil
        }
    }

    var version: String? {
        switch self {
        case .appleWatch: return "watchOS"
        case .garminDevice: return "Garmin Connect"
        case .fitbitDevice: return "Fitbit OS"
        case .manualEntry: return nil
        case .unknown: return nil
        }
    }

    var accuracyRating: Int {
        switch self {
        case .appleWatch: return 95
        case .garminDevice: return 90
        case .fitbitDevice: return 85
        case .manualEntry: return 70
        case .unknown: return 50
        }
    }
}

enum ConsolidationStrategy {
    case prioritizeSource
    case averageValues
    case smartWeighting
    case crossValidation
    case keepMostRecent
    case useHighestAccuracy
}

struct DataConsolidationRules {
    var duplicateTimeWindow: TimeInterval = 300 // 5 minutes
    var enableSmartAveraging = true
    var enableOutlierDetection = true
    var maxDeviationPercentage: Double = 25.0
    var enableCrossPlatformValidation = true
}

struct DataProcessingStats {
    var totalProcessed = 0
    var successfullyProcessed = 0
    var processingErrors = 0
    var duplicatesDetected = 0
    var consolidatedByPriority = 0
    var consolidatedByAveraging = 0
    var consolidatedByWeighting = 0
    var consolidatedByRecency = 0
    var consolidatedByAccuracy = 0
    var outliersDetected = 0
    var outliersRemoved = 0

    var successRate: Double {
        guard totalProcessed > 0 else { return 0.0 }
        return Double(successfullyProcessed) / Double(totalProcessed) * 100.0
    }

    var consolidationRate: Double {
        guard totalProcessed > 0 else { return 0.0 }
        let totalConsolidations = consolidatedByPriority + consolidatedByAveraging + consolidatedByWeighting + consolidatedByRecency + consolidatedByAccuracy
        return Double(totalConsolidations) / Double(totalProcessed) * 100.0
    }
}

enum DataProcessingError: LocalizedError {
    case invalidDataForAveraging
    case noValuesToAverage
    case outlierDetectionFailed
    case consolidationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDataForAveraging:
            return "Invalid data for averaging - missing numeric values"
        case .noValuesToAverage:
            return "No values available for averaging"
        case .outlierDetectionFailed:
            return "Outlier detection failed"
        case .consolidationFailed(let message):
            return "Consolidation failed: \(message)"
        }
    }
}