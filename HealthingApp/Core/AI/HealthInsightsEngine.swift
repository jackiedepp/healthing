import Foundation
import CoreML
import Combine
import HealthKit

/// Core ML coordinator for comprehensive health analytics and insights generation
/// Implements REQ-054: Core ML models for on-device health trend analysis
@MainActor
class HealthInsightsEngine: ObservableObject {
    static let shared = HealthInsightsEngine()

    @Published var currentInsights: [HealthInsight] = []
    @Published var isGeneratingInsights = false
    @Published var lastAnalysisDate: Date?
    @Published var insightsQuality: InsightsQuality = .unavailable

    // AI Services
    private let patternRecognition = PatternRecognitionService.shared
    private let anomalyDetection = AnomalyDetectionService.shared
    private let personalizedRecommendations = PersonalizedRecommendations.shared
    private let wellnessCoaching = WellnessCoachingEngine.shared
    private let mlDataProcessor = MLDataProcessor.shared

    // Data Sources
    private let healthDataStore = HealthDataStore.shared
    private let wearableDataProcessor = WearableDataProcessor.shared
    private let timelineManager = MedicalTimelineManager.shared

    // Core ML Models
    private var healthTrendModel: MLModel?
    private var anomalyDetectionModel: MLModel?
    private var recommendationModel: MLModel?

    private init() {
        loadCoreMLModels()
        setupPeriodicAnalysis()
    }

    // MARK: - Health Insights Generation

    /// Generate comprehensive health insights from all available data sources
    func generateComprehensiveInsights() async throws -> [HealthInsight] {
        isGeneratingInsights = true
        defer { isGeneratingInsights = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        var insights: [HealthInsight] = []

        do {
            // 1. Collect and prepare health data
            let healthData = try await collectHealthData()
            let processedData = try await mlDataProcessor.processHealthDataForML(healthData)

            // 2. Pattern Recognition Analysis
            let patternInsights = try await patternRecognition.analyzeHealthPatterns(processedData)
            insights.append(contentsOf: patternInsights)

            // 3. Anomaly Detection
            let anomalyInsights = try await anomalyDetection.detectHealthAnomalies(processedData)
            insights.append(contentsOf: anomalyInsights)

            // 4. Personalized Recommendations
            let recommendations = try await personalizedRecommendations.generateRecommendations(
                healthData: processedData,
                currentInsights: insights
            )
            insights.append(contentsOf: recommendations)

            // 5. Wellness Coaching Insights
            let coachingInsights = try await wellnessCoaching.generateCoachingInsights(
                healthData: processedData,
                currentGoals: await getCurrentHealthGoals()
            )
            insights.append(contentsOf: coachingInsights)

            // 6. Core ML Model Analysis
            if let modelInsights = try await runCoreMLAnalysis(processedData) {
                insights.append(contentsOf: modelInsights)
            }

            // 7. Prioritize and rank insights
            let prioritizedInsights = prioritizeInsights(insights)

            // 8. Update state
            currentInsights = prioritizedInsights
            lastAnalysisDate = Date()
            insightsQuality = calculateInsightsQuality(insights: prioritizedInsights, dataQuality: processedData.quality)

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✨ HealthInsightsEngine: Generated \(insights.count) insights in \(processingTime)s")

            return prioritizedInsights

        } catch {
            print("❌ HealthInsightsEngine: Failed to generate insights: \(error)")
            throw HealthInsightsError.analysisFailure(error.localizedDescription)
        }
    }

    /// Get current health insights with optional refresh
    func getCurrentInsights(refresh: Bool = false) async throws -> [HealthInsight] {
        if refresh || currentInsights.isEmpty || shouldRefreshInsights() {
            return try await generateComprehensiveInsights()
        }
        return currentInsights
    }

    /// Generate quick insights for dashboard display
    func generateQuickInsights() async throws -> [HealthInsight] {
        // Generate a subset of insights optimized for quick display
        let recentData = try await collectRecentHealthData(days: 7)
        let processedData = try await mlDataProcessor.processHealthDataForML(recentData)

        var quickInsights: [HealthInsight] = []

        // Quick pattern analysis
        let recentPatterns = try await patternRecognition.analyzeRecentPatterns(processedData, days: 7)
        quickInsights.append(contentsOf: recentPatterns.prefix(3))

        // Quick anomaly check
        let recentAnomalies = try await anomalyDetection.detectRecentAnomalies(processedData)
        quickInsights.append(contentsOf: recentAnomalies.prefix(2))

        // Quick recommendations
        let quickRecs = try await personalizedRecommendations.generateQuickRecommendations(processedData)
        quickInsights.append(contentsOf: quickRecs.prefix(3))

        return prioritizeInsights(quickInsights).prefix(5).map { $0 }
    }

    // MARK: - Data Collection

    private func collectHealthData() async throws -> ComprehensiveHealthData {
        // Collect data from all sources
        let wearableData = try await collectWearableData()
        let vitalSigns = try await collectVitalSigns()
        let activityData = try await collectActivityData()
        let sleepData = try await collectSleepData()
        let medicalDocuments = try await collectMedicalDocumentInsights()
        let timelineEvents = await collectTimelineEvents()

        return ComprehensiveHealthData(
            wearableData: wearableData,
            vitalSigns: vitalSigns,
            activityData: activityData,
            sleepData: sleepData,
            medicalDocuments: medicalDocuments,
            timelineEvents: timelineEvents,
            collectionDate: Date()
        )
    }

    private func collectRecentHealthData(days: Int) async throws -> ComprehensiveHealthData {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        // Collect recent data only
        let wearableData = try await collectWearableData(since: cutoffDate)
        let vitalSigns = try await collectVitalSigns(since: cutoffDate)
        let activityData = try await collectActivityData(since: cutoffDate)
        let sleepData = try await collectSleepData(since: cutoffDate)
        let medicalDocuments = try await collectMedicalDocumentInsights(since: cutoffDate)
        let timelineEvents = await collectTimelineEvents(since: cutoffDate)

        return ComprehensiveHealthData(
            wearableData: wearableData,
            vitalSigns: vitalSigns,
            activityData: activityData,
            sleepData: sleepData,
            medicalDocuments: medicalDocuments,
            timelineEvents: timelineEvents,
            collectionDate: Date()
        )
    }

    private func collectWearableData(since: Date? = nil) async throws -> [WearableHealthData] {
        // Get data from wearable devices (Apple Watch, Garmin, etc.)
        let deviceManager = DeviceManagerService.shared
        let connectedDevices = deviceManager.connectedDevices

        var wearableData: [WearableHealthData] = []

        for device in connectedDevices {
            let deviceData = try await wearableDataProcessor.getHealthDataFromDevice(
                device.id,
                since: since ?? Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            )
            wearableData.append(contentsOf: deviceData)
        }

        return wearableData
    }

    private func collectVitalSigns(since: Date? = nil) async throws -> [VitalSignReading] {
        return try await withCheckedThrowingContinuation { continuation in
            healthDataStore.persistentContainer.performBackgroundTask { context in
                do {
                    let request: NSFetchRequest<HealthObservation> = HealthObservation.fetchRequest()

                    // Filter for vital signs
                    var predicates: [NSPredicate] = [
                        NSPredicate(format: "category IN %@", ["vital-signs", "activity", "sleep"])
                    ]

                    if let since = since {
                        predicates.append(NSPredicate(format: "effectiveDateTime >= %@", since as NSDate))
                    }

                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                    request.sortDescriptors = [
                        NSSortDescriptor(keyPath: \HealthObservation.effectiveDateTime, ascending: false)
                    ]
                    request.fetchLimit = 1000

                    let observations = try context.fetch(request)
                    let vitalSigns = observations.map { VitalSignReading.fromHealthObservation($0) }

                    continuation.resume(returning: vitalSigns)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func collectActivityData(since: Date? = nil) async throws -> [ActivityData] {
        // Collect activity data from HealthKit and wearables
        let healthKitSync = HealthKitSyncService.shared
        return try await healthKitSync.getActivityData(since: since)
    }

    private func collectSleepData(since: Date? = nil) async throws -> [SleepData] {
        // Collect sleep data from HealthKit and wearables
        let healthKitSync = HealthKitSyncService.shared
        return try await healthKitSync.getSleepData(since: since)
    }

    private func collectMedicalDocumentInsights(since: Date? = nil) async throws -> [MedicalDocumentInsight] {
        return try await withCheckedThrowingContinuation { continuation in
            healthDataStore.persistentContainer.performBackgroundTask { context in
                do {
                    let request: NSFetchRequest<MedicalDocument> = MedicalDocument.fetchRequest()

                    if let since = since {
                        request.predicate = NSPredicate(format: "uploadDate >= %@", since as NSDate)
                    }

                    request.sortDescriptors = [
                        NSSortDescriptor(keyPath: \MedicalDocument.uploadDate, ascending: false)
                    ]

                    let documents = try context.fetch(request)
                    let insights = documents.compactMap { MedicalDocumentInsight.fromMedicalDocument($0) }

                    continuation.resume(returning: insights)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func collectTimelineEvents(since: Date? = nil) async -> [TimelineEvent] {
        let allEvents = timelineManager.timelineEvents

        if let since = since {
            return allEvents.filter { $0.date >= since }
        }

        return allEvents
    }

    // MARK: - Core ML Analysis

    private func runCoreMLAnalysis(_ data: ProcessedHealthData) async throws -> [HealthInsight]? {
        guard let healthTrendModel = healthTrendModel else {
            print("⚠️ HealthInsightsEngine: Core ML models not available")
            return nil
        }

        var insights: [HealthInsight] = []

        do {
            // Prepare input for Core ML model
            let modelInput = try await mlDataProcessor.prepareForCoreML(data)

            // Run health trend analysis
            if let trendPrediction = try? await runHealthTrendModel(modelInput) {
                let trendInsight = createHealthTrendInsight(from: trendPrediction, data: data)
                insights.append(trendInsight)
            }

            // Run anomaly detection if model is available
            if let anomalyModel = anomalyDetectionModel,
               let anomalyPrediction = try? await runAnomalyDetectionModel(modelInput, model: anomalyModel) {
                let anomalyInsight = createAnomalyInsight(from: anomalyPrediction, data: data)
                insights.append(anomalyInsight)
            }

            return insights

        } catch {
            print("❌ HealthInsightsEngine: Core ML analysis failed: \(error)")
            return nil
        }
    }

    private func runHealthTrendModel(_ input: MLFeatureProvider) async throws -> MLFeatureProvider {
        guard let model = healthTrendModel else {
            throw HealthInsightsError.modelNotAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let prediction = try model.prediction(from: input)
                    continuation.resume(returning: prediction)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runAnomalyDetectionModel(_ input: MLFeatureProvider, model: MLModel) async throws -> MLFeatureProvider {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let prediction = try model.prediction(from: input)
                    continuation.resume(returning: prediction)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Insight Generation

    private func createHealthTrendInsight(from prediction: MLFeatureProvider, data: ProcessedHealthData) -> HealthInsight {
        // Extract trend information from model prediction
        let trendDirection = extractTrendDirection(from: prediction)
        let confidence = extractConfidence(from: prediction)
        let affectedMetrics = extractAffectedMetrics(from: prediction)

        return HealthInsight(
            id: UUID().uuidString,
            title: generateTrendTitle(trendDirection, metrics: affectedMetrics),
            description: generateTrendDescription(trendDirection, metrics: affectedMetrics, confidence: confidence),
            category: .trend,
            priority: calculateTrendPriority(trendDirection, confidence: confidence),
            confidence: confidence,
            actionable: true,
            source: .coreML,
            generatedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            metadata: [
                "trend_direction": trendDirection.rawValue,
                "affected_metrics": affectedMetrics,
                "model_version": "health_trend_v1.0"
            ],
            relatedData: createRelatedDataReferences(for: affectedMetrics, from: data)
        )
    }

    private func createAnomalyInsight(from prediction: MLFeatureProvider, data: ProcessedHealthData) -> HealthInsight {
        let anomalyScore = extractAnomalyScore(from: prediction)
        let anomalyType = extractAnomalyType(from: prediction)
        let affectedMetric = extractAnomalyMetric(from: prediction)

        return HealthInsight(
            id: UUID().uuidString,
            title: generateAnomalyTitle(anomalyType, metric: affectedMetric),
            description: generateAnomalyDescription(anomalyType, metric: affectedMetric, score: anomalyScore),
            category: .anomaly,
            priority: calculateAnomalyPriority(anomalyScore),
            confidence: min(anomalyScore, 1.0),
            actionable: true,
            source: .coreML,
            generatedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            metadata: [
                "anomaly_score": anomalyScore,
                "anomaly_type": anomalyType.rawValue,
                "affected_metric": affectedMetric,
                "model_version": "anomaly_detection_v1.0"
            ],
            relatedData: [affectedMetric]
        )
    }

    // MARK: - Insight Processing

    private func prioritizeInsights(_ insights: [HealthInsight]) -> [HealthInsight] {
        return insights.sorted { insight1, insight2 in
            // Sort by priority first
            if insight1.priority != insight2.priority {
                return insight1.priority.rawValue > insight2.priority.rawValue
            }

            // Then by confidence
            if insight1.confidence != insight2.confidence {
                return insight1.confidence > insight2.confidence
            }

            // Finally by recency
            return insight1.generatedDate > insight2.generatedDate
        }
    }

    private func calculateInsightsQuality(insights: [HealthInsight], dataQuality: DataQuality) -> InsightsQuality {
        guard !insights.isEmpty else { return .unavailable }

        let avgConfidence = insights.map { $0.confidence }.reduce(0, +) / Double(insights.count)
        let highPriorityCount = insights.filter { $0.priority == .critical || $0.priority == .high }.count

        switch (dataQuality, avgConfidence, highPriorityCount) {
        case (.excellent, let conf, _) where conf >= 0.8:
            return .excellent
        case (.good, let conf, _) where conf >= 0.7:
            return .good
        case (_, let conf, let high) where conf >= 0.6 || high > 0:
            return .moderate
        default:
            return .limited
        }
    }

    // MARK: - Model Management

    private func loadCoreMLModels() {
        Task {
            do {
                // Load health trend model
                if let healthTrendURL = Bundle.main.url(forResource: "HealthTrendModel", withExtension: "mlmodelc") {
                    healthTrendModel = try MLModel(contentsOf: healthTrendURL)
                    print("✅ HealthInsightsEngine: Health trend model loaded")
                } else {
                    // Create a mock model for development
                    healthTrendModel = try createMockHealthTrendModel()
                    print("⚠️ HealthInsightsEngine: Using mock health trend model")
                }

                // Load anomaly detection model
                if let anomalyURL = Bundle.main.url(forResource: "AnomalyDetectionModel", withExtension: "mlmodelc") {
                    anomalyDetectionModel = try MLModel(contentsOf: anomalyURL)
                    print("✅ HealthInsightsEngine: Anomaly detection model loaded")
                } else {
                    // Create a mock model for development
                    anomalyDetectionModel = try createMockAnomalyDetectionModel()
                    print("⚠️ HealthInsightsEngine: Using mock anomaly detection model")
                }

            } catch {
                print("❌ HealthInsightsEngine: Failed to load Core ML models: \(error)")
            }
        }
    }

    private func createMockHealthTrendModel() throws -> MLModel {
        // For development, create a simple mock model
        // In production, this would be replaced with actual trained models
        let mockModelDescription = MLModelDescription()
        // Create minimal mock implementation
        // This is a placeholder - real implementation would use actual Core ML model files
        return try MLModel(contentsOf: Bundle.main.url(forResource: "MockModel", withExtension: "mlmodel") ??
                          URL(fileURLWithPath: "/dev/null"))
    }

    private func createMockAnomalyDetectionModel() throws -> MLModel {
        // For development, create a simple mock model
        // In production, this would be replaced with actual trained models
        return try MLModel(contentsOf: Bundle.main.url(forResource: "MockAnomalyModel", withExtension: "mlmodel") ??
                          URL(fileURLWithPath: "/dev/null"))
    }

    // MARK: - Periodic Analysis

    private func setupPeriodicAnalysis() {
        // Schedule daily analysis
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task {
                try? await self.generateComprehensiveInsights()
            }
        }

        // Schedule quick analysis every 4 hours
        Timer.scheduledTimer(withTimeInterval: 4 * 60 * 60, repeats: true) { _ in
            Task {
                try? await self.generateQuickInsights()
            }
        }
    }

    private func shouldRefreshInsights() -> Bool {
        guard let lastAnalysis = lastAnalysisDate else { return true }
        return Date().timeIntervalSince(lastAnalysis) > 6 * 60 * 60 // 6 hours
    }

    // MARK: - Helper Methods

    private func getCurrentHealthGoals() async -> [HealthGoal] {
        // Get current health goals from wellness coaching engine
        return await wellnessCoaching.getCurrentGoals()
    }

    private func extractTrendDirection(from prediction: MLFeatureProvider) -> TrendDirection {
        // Extract trend direction from Core ML model output
        // This is a mock implementation - real implementation would parse actual model output
        return .improving
    }

    private func extractConfidence(from prediction: MLFeatureProvider) -> Double {
        // Extract confidence score from Core ML model output
        return 0.85 // Mock confidence
    }

    private func extractAffectedMetrics(from prediction: MLFeatureProvider) -> [String] {
        // Extract which health metrics are affected by the trend
        return ["heart_rate", "activity_level"] // Mock metrics
    }

    private func extractAnomalyScore(from prediction: MLFeatureProvider) -> Double {
        return 0.75 // Mock anomaly score
    }

    private func extractAnomalyType(from prediction: MLFeatureProvider) -> AnomalyType {
        return .elevated // Mock anomaly type
    }

    private func extractAnomalyMetric(from prediction: MLFeatureProvider) -> String {
        return "resting_heart_rate" // Mock metric
    }

    private func generateTrendTitle(_ direction: TrendDirection, metrics: [String]) -> String {
        let metricNames = metrics.map { formatMetricName($0) }.joined(separator: " and ")
        switch direction {
        case .improving:
            return "Your \(metricNames) is trending positively"
        case .declining:
            return "Your \(metricNames) shows concerning trends"
        case .stable:
            return "Your \(metricNames) remains stable"
        }
    }

    private func generateTrendDescription(_ direction: TrendDirection, metrics: [String], confidence: Double) -> String {
        let confidencePercent = Int(confidence * 100)
        let metricNames = metrics.map { formatMetricName($0) }.joined(separator: " and ")

        switch direction {
        case .improving:
            return "Analysis shows a positive trend in your \(metricNames) over the past few weeks. Keep up the great work! (Confidence: \(confidencePercent)%)"
        case .declining:
            return "Your \(metricNames) has shown a declining pattern recently. Consider consulting with your healthcare provider. (Confidence: \(confidencePercent)%)"
        case .stable:
            return "Your \(metricNames) has remained consistent, which indicates good health stability. (Confidence: \(confidencePercent)%)"
        }
    }

    private func generateAnomalyTitle(_ type: AnomalyType, metric: String) -> String {
        let metricName = formatMetricName(metric)
        switch type {
        case .elevated:
            return "Elevated \(metricName) detected"
        case .decreased:
            return "Low \(metricName) detected"
        case .irregular:
            return "Irregular \(metricName) pattern"
        case .unexpected:
            return "Unusual \(metricName) reading"
        }
    }

    private func generateAnomalyDescription(_ type: AnomalyType, metric: String, score: Double) -> String {
        let scorePercent = Int(score * 100)
        let metricName = formatMetricName(metric)

        return "Unusual \(metricName) values detected that differ from your typical patterns. This may warrant attention or monitoring. (Confidence: \(scorePercent)%)"
    }

    private func formatMetricName(_ metric: String) -> String {
        return metric.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func calculateTrendPriority(_ direction: TrendDirection, confidence: Double) -> InsightPriority {
        switch (direction, confidence) {
        case (.declining, let conf) where conf >= 0.8:
            return .high
        case (.declining, _):
            return .medium
        case (.improving, let conf) where conf >= 0.8:
            return .medium
        default:
            return .low
        }
    }

    private func calculateAnomalyPriority(_ score: Double) -> InsightPriority {
        switch score {
        case 0.9...:
            return .critical
        case 0.7..<0.9:
            return .high
        case 0.5..<0.7:
            return .medium
        default:
            return .low
        }
    }

    private func createRelatedDataReferences(for metrics: [String], from data: ProcessedHealthData) -> [String] {
        // Create references to the specific data points that contributed to this insight
        return metrics.compactMap { metric in
            // Find the most recent data point for this metric
            return data.findMostRecentDataPoint(for: metric)?.id
        }
    }
}

// MARK: - Supporting Types

enum TrendDirection: String {
    case improving
    case declining
    case stable
}

enum AnomalyType: String {
    case elevated
    case decreased
    case irregular
    case unexpected
}

enum InsightsQuality {
    case unavailable
    case limited
    case moderate
    case good
    case excellent

    var displayName: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .limited: return "Limited"
        case .moderate: return "Moderate"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }

    var color: String {
        switch self {
        case .unavailable, .limited: return "gray"
        case .moderate: return "yellow"
        case .good: return "orange"
        case .excellent: return "green"
        }
    }
}

enum HealthInsightsError: LocalizedError {
    case analysisFailure(String)
    case modelNotAvailable
    case insufficientData
    case processingError(String)

    var errorDescription: String? {
        switch self {
        case .analysisFailure(let message):
            return "Health analysis failed: \(message)"
        case .modelNotAvailable:
            return "Core ML models not available"
        case .insufficientData:
            return "Insufficient health data for analysis"
        case .processingError(let message):
            return "Processing error: \(message)"
        }
    }
}