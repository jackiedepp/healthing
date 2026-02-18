import Foundation
import CoreML
import HealthKit

// MARK: - Health Insight Model

struct HealthInsight: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let category: InsightCategory
    let priority: InsightPriority
    let confidence: Double
    let actionable: Bool
    let source: InsightSource
    let generatedDate: Date
    let expirationDate: Date?
    let metadata: [String: Any]
    let relatedData: [String]

    // Custom coding to handle metadata
    enum CodingKeys: String, CodingKey {
        case id, title, description, category, priority, confidence
        case actionable, source, generatedDate, expirationDate, relatedData
        case metadata
    }

    init(id: String, title: String, description: String, category: InsightCategory,
         priority: InsightPriority, confidence: Double, actionable: Bool,
         source: InsightSource, generatedDate: Date, expirationDate: Date?,
         metadata: [String: Any] = [:], relatedData: [String] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.confidence = confidence
        self.actionable = actionable
        self.source = source
        self.generatedDate = generatedDate
        self.expirationDate = expirationDate
        self.metadata = metadata
        self.relatedData = relatedData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(InsightCategory.self, forKey: .category)
        priority = try container.decode(InsightPriority.self, forKey: .priority)
        confidence = try container.decode(Double.self, forKey: .confidence)
        actionable = try container.decode(Bool.self, forKey: .actionable)
        source = try container.decode(InsightSource.self, forKey: .source)
        generatedDate = try container.decode(Date.self, forKey: .generatedDate)
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
        relatedData = try container.decode([String].self, forKey: .relatedData)

        // Handle metadata with type erasure
        if let metadataData = try? container.decodeIfPresent(Data.self, forKey: .metadata),
           let decodedMetadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
            metadata = decodedMetadata
        } else {
            metadata = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(category, forKey: .category)
        try container.encode(priority, forKey: .priority)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(actionable, forKey: .actionable)
        try container.encode(source, forKey: .source)
        try container.encode(generatedDate, forKey: .generatedDate)
        try container.encodeIfPresent(expirationDate, forKey: .expirationDate)
        try container.encode(relatedData, forKey: .relatedData)

        // Encode metadata as Data
        if let metadataData = try? JSONSerialization.data(withJSONObject: metadata) {
            try container.encode(metadataData, forKey: .metadata)
        }
    }

    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }

    var priorityColor: String {
        return priority.color
    }

    var categoryIcon: String {
        return category.icon
    }
}

enum InsightCategory: String, Codable, CaseIterable {
    case trend = "trend"
    case anomaly = "anomaly"
    case recommendation = "recommendation"
    case warning = "warning"
    case achievement = "achievement"
    case goal = "goal"
    case coaching = "coaching"
    case prediction = "prediction"

    var displayName: String {
        switch self {
        case .trend: return "Health Trend"
        case .anomaly: return "Health Anomaly"
        case .recommendation: return "Recommendation"
        case .warning: return "Health Warning"
        case .achievement: return "Achievement"
        case .goal: return "Health Goal"
        case .coaching: return "Wellness Coaching"
        case .prediction: return "Health Prediction"
        }
    }

    var icon: String {
        switch self {
        case .trend: return "chart.line.uptrend.xyaxis"
        case .anomaly: return "exclamationmark.triangle"
        case .recommendation: return "lightbulb"
        case .warning: return "exclamationmark.circle"
        case .achievement: return "star.fill"
        case .goal: return "target"
        case .coaching: return "person.circle"
        case .prediction: return "crystal.ball"
        }
    }
}

enum InsightPriority: Int, Codable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
}

enum InsightSource: String, Codable {
    case coreML = "core_ml"
    case patternRecognition = "pattern_recognition"
    case anomalyDetection = "anomaly_detection"
    case personalizedRecommendations = "personalized_recommendations"
    case wellnessCoaching = "wellness_coaching"
    case wearableData = "wearable_data"
    case medicalDocuments = "medical_documents"
    case userInput = "user_input"

    var displayName: String {
        switch self {
        case .coreML: return "AI Analysis"
        case .patternRecognition: return "Pattern Analysis"
        case .anomalyDetection: return "Anomaly Detection"
        case .personalizedRecommendations: return "Personalized AI"
        case .wellnessCoaching: return "Wellness Coach"
        case .wearableData: return "Wearable Devices"
        case .medicalDocuments: return "Medical Records"
        case .userInput: return "User Input"
        }
    }
}

// MARK: - Comprehensive Health Data Model

struct ComprehensiveHealthData {
    let wearableData: [WearableHealthData]
    let vitalSigns: [VitalSignReading]
    let activityData: [ActivityData]
    let sleepData: [SleepData]
    let medicalDocuments: [MedicalDocumentInsight]
    let timelineEvents: [TimelineEvent]
    let collectionDate: Date

    var quality: DataQuality {
        let totalDataPoints = wearableData.count + vitalSigns.count + activityData.count + sleepData.count + medicalDocuments.count

        switch totalDataPoints {
        case 100...:
            return .excellent
        case 50..<100:
            return .good
        case 20..<50:
            return .moderate
        case 5..<20:
            return .limited
        default:
            return .insufficient
        }
    }

    var timeRange: DateInterval? {
        let allDates = getAllDates()
        guard let earliest = allDates.min(), let latest = allDates.max() else { return nil }
        return DateInterval(start: earliest, end: latest)
    }

    private func getAllDates() -> [Date] {
        var dates: [Date] = []
        dates.append(contentsOf: wearableData.map { $0.timestamp })
        dates.append(contentsOf: vitalSigns.map { $0.timestamp })
        dates.append(contentsOf: activityData.map { $0.date })
        dates.append(contentsOf: sleepData.map { $0.bedTime })
        dates.append(contentsOf: medicalDocuments.map { $0.documentDate })
        dates.append(contentsOf: timelineEvents.map { $0.date })
        return dates
    }
}

enum DataQuality: String, CaseIterable {
    case insufficient
    case limited
    case moderate
    case good
    case excellent

    var displayName: String {
        switch self {
        case .insufficient: return "Insufficient"
        case .limited: return "Limited"
        case .moderate: return "Moderate"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }

    var color: String {
        switch self {
        case .insufficient, .limited: return "red"
        case .moderate: return "yellow"
        case .good: return "orange"
        case .excellent: return "green"
        }
    }
}

// MARK: - Processed Health Data for ML

struct ProcessedHealthData {
    let features: [String: Double]
    let timeSeriesData: [String: [TimeSeriesPoint]]
    let categoricalData: [String: String]
    let quality: DataQuality
    let processingDate: Date
    let dataPointCount: Int

    func findMostRecentDataPoint(for metric: String) -> DataPoint? {
        if let timeSeries = timeSeriesData[metric], let latest = timeSeries.last {
            return DataPoint(id: "\(metric)_\(latest.timestamp)", value: latest.value, timestamp: latest.timestamp)
        }
        return nil
    }

    var featureVector: [Double] {
        return Array(features.values)
    }

    var featureNames: [String] {
        return Array(features.keys).sorted()
    }
}

struct TimeSeriesPoint {
    let timestamp: Date
    let value: Double
}

struct DataPoint {
    let id: String
    let value: Double
    let timestamp: Date
}

// MARK: - Health Data Types

struct WearableHealthData {
    let deviceId: String
    let deviceType: WearableDataSource
    let metricType: String
    let value: Double
    let unit: String
    let timestamp: Date
    let confidence: Double
}

struct VitalSignReading {
    let id: String
    let type: VitalSignType
    let value: Double
    let unit: String
    let timestamp: Date
    let source: String
    let quality: DataQuality

    static func fromHealthObservation(_ observation: HealthObservation) -> VitalSignReading {
        return VitalSignReading(
            id: observation.id ?? UUID().uuidString,
            type: VitalSignType.fromLOINCCode(observation.code ?? ""),
            value: observation.valueQuantity?.doubleValue ?? 0.0,
            unit: observation.valueQuantity?.unit ?? "",
            timestamp: observation.effectiveDateTime ?? Date(),
            source: observation.device?.type ?? "unknown",
            quality: .good
        )
    }
}

enum VitalSignType: String, CaseIterable {
    case heartRate = "heart_rate"
    case bloodPressure = "blood_pressure"
    case temperature = "temperature"
    case respiratoryRate = "respiratory_rate"
    case oxygenSaturation = "oxygen_saturation"
    case bloodGlucose = "blood_glucose"
    case weight = "weight"
    case height = "height"
    case bmi = "bmi"

    static func fromLOINCCode(_ code: String) -> VitalSignType {
        switch code {
        case "8867-4": return .heartRate
        case "85354-9": return .bloodPressure
        case "8310-5": return .temperature
        case "9279-1": return .respiratoryRate
        case "59408-5": return .oxygenSaturation
        case "33747-0": return .bloodGlucose
        case "29463-7": return .weight
        case "8302-2": return .height
        case "39156-5": return .bmi
        default: return .heartRate
        }
    }

    var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .bloodPressure: return "Blood Pressure"
        case .temperature: return "Temperature"
        case .respiratoryRate: return "Respiratory Rate"
        case .oxygenSaturation: return "Oxygen Saturation"
        case .bloodGlucose: return "Blood Glucose"
        case .weight: return "Weight"
        case .height: return "Height"
        case .bmi: return "BMI"
        }
    }
}

struct ActivityData {
    let id: String
    let activityType: String
    let date: Date
    let duration: TimeInterval
    let caloriesBurned: Double
    let steps: Int
    let distance: Double
    let averageHeartRate: Double?
    let source: String
}

struct SleepData {
    let id: String
    let bedTime: Date
    let wakeTime: Date
    let sleepDuration: TimeInterval
    let sleepEfficiency: Double
    let restlessness: Double
    let deepSleepPercentage: Double
    let remSleepPercentage: Double
    let source: String
}

struct MedicalDocumentInsight {
    let documentId: String
    let documentType: String
    let documentDate: Date
    let extractedMetrics: [String: Any]
    let classificationConfidence: Double
    let medicalEntities: [String]
    let providerName: String?

    static func fromMedicalDocument(_ document: MedicalDocument) -> MedicalDocumentInsight? {
        return MedicalDocumentInsight(
            documentId: document.id ?? "",
            documentType: document.documentType ?? "unknown",
            documentDate: document.documentDate ?? document.uploadDate ?? Date(),
            extractedMetrics: [:], // Would extract from document content
            classificationConfidence: document.classificationConfidence,
            medicalEntities: document.searchKeywords?.components(separatedBy: ",") ?? [],
            providerName: document.providerName
        )
    }
}

// MARK: - Health Goals and Coaching

struct HealthGoal {
    let id: String
    let title: String
    let description: String
    let targetValue: Double
    let currentValue: Double
    let unit: String
    let targetDate: Date
    let category: HealthGoalCategory
    let priority: GoalPriority
    let progress: Double
    let isActive: Bool
    let createdDate: Date

    var progressPercentage: Int {
        return Int(progress * 100)
    }

    var isCompleted: Bool {
        return progress >= 1.0
    }

    var daysRemaining: Int {
        return Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
    }
}

enum HealthGoalCategory: String, CaseIterable {
    case activity = "activity"
    case nutrition = "nutrition"
    case sleep = "sleep"
    case vitals = "vitals"
    case mental = "mental"
    case medication = "medication"

    var displayName: String {
        return rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .activity: return "figure.walk"
        case .nutrition: return "leaf.fill"
        case .sleep: return "moon.fill"
        case .vitals: return "heart.fill"
        case .mental: return "brain.head.profile"
        case .medication: return "pills.fill"
        }
    }
}

enum GoalPriority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        return rawValue.capitalized
    }
}

// MARK: - Machine Learning Input/Output Models

protocol MLFeatureProvider {
    var featureNames: Set<String> { get }
    func featureValue(for featureName: String) -> MLFeatureValue?
}

struct HealthMLInput: MLFeatureProvider {
    let features: [String: MLFeatureValue]

    var featureNames: Set<String> {
        return Set(features.keys)
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        return features[featureName]
    }

    static func fromProcessedData(_ data: ProcessedHealthData) -> HealthMLInput {
        var features: [String: MLFeatureValue] = [:]

        for (key, value) in data.features {
            features[key] = MLFeatureValue(double: value)
        }

        return HealthMLInput(features: features)
    }
}

struct HealthMLOutput: MLFeatureProvider {
    let prediction: [String: MLFeatureValue]

    var featureNames: Set<String> {
        return Set(prediction.keys)
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        return prediction[featureName]
    }
}

// MARK: - Analysis Results

struct PatternAnalysisResult {
    let patterns: [HealthPattern]
    let trends: [HealthTrend]
    let correlations: [HealthCorrelation]
    let analysisDate: Date
    let confidence: Double
}

struct HealthPattern {
    let id: String
    let patternType: PatternType
    let description: String
    let frequency: String
    let strength: Double
    let affectedMetrics: [String]
    let timeRange: DateInterval
}

enum PatternType: String {
    case circadian = "circadian"
    case weekly = "weekly"
    case seasonal = "seasonal"
    case activity = "activity"
    case stress = "stress"
    case nutrition = "nutrition"
}

struct HealthTrend {
    let metricName: String
    let direction: TrendDirection
    let magnitude: Double
    let duration: TimeInterval
    let confidence: Double
    let significance: TrendSignificance
}

enum TrendSignificance: String {
    case negligible = "negligible"
    case minor = "minor"
    case moderate = "moderate"
    case significant = "significant"
    case major = "major"
}

struct HealthCorrelation {
    let metric1: String
    let metric2: String
    let correlationCoefficient: Double
    let significance: Double
    let description: String
}

struct AnomalyDetectionResult {
    let anomalies: [HealthAnomaly]
    let overallScore: Double
    let analysisDate: Date
    let modelVersion: String
}

struct HealthAnomaly {
    let id: String
    let metricName: String
    let anomalyScore: Double
    let anomalyType: AnomalyType
    let timestamp: Date
    let expectedValue: Double
    let actualValue: Double
    let severity: AnomaalySeverity
    let context: String
}

enum AnomaalySeverity: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
}

// MARK: - Wellness Coaching Models

struct WellnessCoachingInsight {
    let id: String
    let title: String
    let description: String
    let actionItems: [ActionItem]
    let motivationalMessage: String
    let goalAlignment: String
    let priority: CoachingPriority
    let expirationDate: Date
}

enum CoachingPriority: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
}

struct ActionItem {
    let id: String
    let title: String
    let description: String
    let estimatedDuration: TimeInterval
    let difficulty: ActionDifficulty
    let category: ActionCategory
    let isCompleted: Bool
}

enum ActionDifficulty: String {
    case easy = "easy"
    case moderate = "moderate"
    case challenging = "challenging"

    var displayName: String {
        return rawValue.capitalized
    }
}

enum ActionCategory: String {
    case immediate = "immediate"
    case daily = "daily"
    case weekly = "weekly"
    case lifestyle = "lifestyle"

    var displayName: String {
        return rawValue.capitalized
    }
}

// MARK: - Recommendation Models

struct PersonalizedRecommendation {
    let id: String
    let title: String
    let description: String
    let recommendationType: RecommendationType
    let priority: RecommendationPriority
    let confidence: Double
    let evidence: [EvidencePoint]
    let suggestedActions: [String]
    let expectedBenefit: String
    let timeframe: String
    let createdDate: Date
}

enum RecommendationType: String {
    case lifestyle = "lifestyle"
    case medical = "medical"
    case fitness = "fitness"
    case nutrition = "nutrition"
    case sleep = "sleep"
    case stress = "stress"
    case preventive = "preventive"

    var displayName: String {
        return rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .lifestyle: return "person.fill"
        case .medical: return "stethoscope"
        case .fitness: return "figure.run"
        case .nutrition: return "leaf.fill"
        case .sleep: return "moon.fill"
        case .stress: return "brain.head.profile"
        case .preventive: return "shield.fill"
        }
    }
}

enum RecommendationPriority: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}

struct EvidencePoint {
    let description: String
    let dataSource: String
    let confidence: Double
    let timeRange: DateInterval?
}