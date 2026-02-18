import Foundation
import Accelerate
import HealthKit
import Combine

/// Anomaly detection service for early health warnings and unusual pattern identification
/// Implements REQ-056: Anomaly detection for early health warnings
@MainActor
class AnomalyDetectionService: ObservableObject {
    static let shared = AnomalyDetectionService()

    @Published var isAnalyzing = false
    @Published var detectedAnomalies: [HealthAnomaly] = []
    @Published var lastAnalysisDate: Date?
    @Published var anomalyRiskLevel: AnomalyRiskLevel = .low

    // Detection thresholds and parameters
    private let zScoreThreshold = 2.5 // Standard deviations for anomaly detection
    private let minimumDataPoints = 10 // Minimum data points for baseline establishment
    private let rollingWindowSize = 14 // Days for rolling baseline calculation
    private let highRiskThreshold = 0.8 // Score threshold for high-risk anomalies

    // Baseline health ranges (these would be personalized based on user history)
    private var personalizedBaselines: [String: HealthBaseline] = [:]

    private init() {
        initializeDefaultBaselines()
    }

    // MARK: - Anomaly Detection

    /// Detect health anomalies from processed health data
    func detectHealthAnomalies(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        var insights: [HealthInsight] = []

        do {
            // Update personalized baselines with new data
            try await updatePersonalizedBaselines(data)

            // Detect different types of anomalies
            let vitalSignAnomalies = try await detectVitalSignAnomalies(data)
            let activityAnomalies = try await detectActivityAnomalies(data)
            let sleepAnomalies = try await detectSleepAnomalies(data)
            let correlationAnomalies = try await detectCorrelationAnomalies(data)
            let temporalAnomalies = try await detectTemporalAnomalies(data)

            // Combine all detected anomalies
            let allAnomalies = vitalSignAnomalies + activityAnomalies + sleepAnomalies + correlationAnomalies + temporalAnomalies

            // Filter anomalies by significance
            let significantAnomalies = allAnomalies.filter { $0.anomalyScore >= 0.5 }

            // Convert anomalies to insights
            for anomaly in significantAnomalies {
                let insight = createInsightFromAnomaly(anomaly)
                insights.append(insight)
            }

            // Update state
            detectedAnomalies = significantAnomalies
            lastAnalysisDate = Date()
            anomalyRiskLevel = calculateOverallRiskLevel(significantAnomalies)

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            print("🚨 AnomalyDetectionService: Detected \(significantAnomalies.count) anomalies in \(processingTime)s")

            return insights

        } catch {
            print("❌ AnomalyDetectionService: Anomaly detection failed: \(error)")
            throw AnomalyDetectionError.detectionFailure(error.localizedDescription)
        }
    }

    /// Detect recent anomalies for quick assessment
    func detectRecentAnomalies(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        // Focus on the most recent data for quick anomaly detection
        let recentData = filterRecentData(data, days: 3)

        if recentData.dataPointCount < 5 {
            return [] // Not enough recent data for meaningful anomaly detection
        }

        var insights: [HealthInsight] = []

        // Quick vital signs anomaly check
        let recentVitalAnomalies = try await detectRecentVitalSignAnomalies(recentData)
        insights.append(contentsOf: recentVitalAnomalies)

        // Quick activity anomaly check
        let recentActivityAnomalies = try await detectRecentActivityAnomalies(recentData)
        insights.append(contentsOf: recentActivityAnomalies)

        return insights.prefix(3).map { $0 } // Limit to 3 most significant recent anomalies
    }

    // MARK: - Vital Sign Anomaly Detection

    private func detectVitalSignAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly] {
        var anomalies: [HealthAnomaly] = []

        // Heart rate anomalies
        if let heartRateAnomalies = try await detectHeartRateAnomalies(data) {
            anomalies.append(contentsOf: heartRateAnomalies)
        }

        // Blood pressure anomalies
        if let bloodPressureAnomalies = try await detectBloodPressureAnomalies(data) {
            anomalies.append(contentsOf: bloodPressureAnomalies)
        }

        // Weight anomalies
        if let weightAnomalies = try await detectWeightAnomalies(data) {
            anomalies.append(contentsOf: weightAnomalies)
        }

        // Temperature anomalies
        if let temperatureAnomalies = try await detectTemperatureAnomalies(data) {
            anomalies.append(contentsOf: temperatureAnomalies)
        }

        return anomalies
    }

    private func detectHeartRateAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let heartRateData = data.timeSeriesData["heart_rate"],
              heartRateData.count >= minimumDataPoints else { return nil }

        let baseline = personalizedBaselines["heart_rate"] ?? getDefaultBaseline(for: "heart_rate")
        var anomalies: [HealthAnomaly] = []

        for point in heartRateData.suffix(7) { // Check last week
            let zScore = calculateZScore(value: point.value, baseline: baseline)
            let anomalyScore = calculateAnomalyScore(zScore: zScore)

            if anomalyScore > 0.5 {
                let anomalyType = determineAnomalyType(value: point.value, baseline: baseline)
                let severity = determineSeverity(anomalyScore: anomalyScore, metricType: "heart_rate")

                let anomaly = HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "heart_rate",
                    anomalyScore: anomalyScore,
                    anomalyType: anomalyType,
                    timestamp: point.timestamp,
                    expectedValue: baseline.mean,
                    actualValue: point.value,
                    severity: severity,
                    context: generateAnomalyContext(
                        metricName: "Heart Rate",
                        value: point.value,
                        baseline: baseline,
                        anomalyType: anomalyType
                    )
                )

                anomalies.append(anomaly)
            }
        }

        return anomalies
    }

    private func detectBloodPressureAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let bpData = data.timeSeriesData["systolic_bp"],
              bpData.count >= minimumDataPoints else { return nil }

        let baseline = personalizedBaselines["systolic_bp"] ?? getDefaultBaseline(for: "systolic_bp")
        var anomalies: [HealthAnomaly] = []

        for point in bpData.suffix(7) {
            let zScore = calculateZScore(value: point.value, baseline: baseline)
            let anomalyScore = calculateAnomalyScore(zScore: zScore)

            // Blood pressure has special clinical thresholds
            let clinicalAnomalyScore = calculateBloodPressureClinicalScore(point.value)
            let finalScore = max(anomalyScore, clinicalAnomalyScore)

            if finalScore > 0.6 { // Lower threshold for BP due to clinical importance
                let anomalyType = point.value > 140 ? .elevated : (point.value < 90 ? .decreased : .unexpected)
                let severity = determineSeverity(anomalyScore: finalScore, metricType: "blood_pressure")

                let anomaly = HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "systolic_bp",
                    anomalyScore: finalScore,
                    anomalyType: anomalyType,
                    timestamp: point.timestamp,
                    expectedValue: baseline.mean,
                    actualValue: point.value,
                    severity: severity,
                    context: generateBloodPressureContext(value: point.value)
                )

                anomalies.append(anomaly)
            }
        }

        return anomalies
    }

    private func detectWeightAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let weightData = data.timeSeriesData["weight"],
              weightData.count >= minimumDataPoints else { return nil }

        let baseline = personalizedBaselines["weight"] ?? getDefaultBaseline(for: "weight")
        var anomalies: [HealthAnomaly] = []

        // Check for sudden weight changes
        let recentWeights = weightData.suffix(7)
        let weightChanges = calculateWeightChanges(recentWeights)

        for (index, change) in weightChanges.enumerated() {
            if abs(change) > 5.0 { // Sudden weight change > 5 lbs
                let severity = abs(change) > 10.0 ? AnomaalySeverity.high : .medium
                let anomalyType = change > 0 ? AnomalyType.elevated : .decreased

                let anomaly = HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "weight",
                    anomalyScore: min(abs(change) / 10.0, 1.0),
                    anomalyType: anomalyType,
                    timestamp: recentWeights[index + 1].timestamp,
                    expectedValue: recentWeights[index].value,
                    actualValue: recentWeights[index + 1].value,
                    severity: severity,
                    context: "Sudden weight \(change > 0 ? "gain" : "loss") of \(String(format: "%.1f", abs(change))) lbs detected. Consider monitoring and consulting healthcare provider if persistent."
                )

                anomalies.append(anomaly)
            }
        }

        return anomalies
    }

    private func detectTemperatureAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let tempData = data.timeSeriesData["temperature"],
              tempData.count >= 3 else { return nil } // Temperature anomalies need less historical data

        var anomalies: [HealthAnomaly] = []

        for point in tempData.suffix(3) { // Check last 3 readings
            if point.value > 100.4 { // Fever threshold (Fahrenheit)
                let severity: AnomaalySeverity = point.value > 103.0 ? .critical : (point.value > 102.0 ? .high : .medium)

                let anomaly = HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "temperature",
                    anomalyScore: min((point.value - 98.6) / 5.0, 1.0),
                    anomalyType: .elevated,
                    timestamp: point.timestamp,
                    expectedValue: 98.6,
                    actualValue: point.value,
                    severity: severity,
                    context: "Elevated body temperature detected (\(String(format: "%.1f", point.value))°F). Monitor symptoms and consider medical consultation."
                )

                anomalies.append(anomaly)
            }
        }

        return anomalies
    }

    // MARK: - Activity Anomaly Detection

    private func detectActivityAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly] {
        var anomalies: [HealthAnomaly] = []

        // Step count anomalies
        if let stepAnomalies = try await detectStepCountAnomalies(data) {
            anomalies.append(contentsOf: stepAnomalies)
        }

        // Activity pattern anomalies
        if let patternAnomalies = try await detectActivityPatternAnomalies(data) {
            anomalies.append(contentsOf: patternAnomalies)
        }

        return anomalies
    }

    private func detectStepCountAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let stepData = data.timeSeriesData["daily_steps"],
              stepData.count >= minimumDataPoints else { return nil }

        let baseline = personalizedBaselines["daily_steps"] ?? getDefaultBaseline(for: "daily_steps")
        var anomalies: [HealthAnomaly] = []

        for point in stepData.suffix(7) {
            let zScore = calculateZScore(value: point.value, baseline: baseline)
            let anomalyScore = calculateAnomalyScore(zScore: zScore)

            // Check for significant deviations
            if anomalyScore > 0.6 {
                let anomalyType = determineAnomalyType(value: point.value, baseline: baseline)
                let severity = determineSeverity(anomalyScore: anomalyScore, metricType: "activity")

                // Special case for very low activity (potential health concern)
                if point.value < baseline.mean * 0.3 {
                    let anomaly = HealthAnomaly(
                        id: UUID().uuidString,
                        metricName: "daily_steps",
                        anomalyScore: anomalyScore,
                        anomalyType: .decreased,
                        timestamp: point.timestamp,
                        expectedValue: baseline.mean,
                        actualValue: point.value,
                        severity: .high,
                        context: "Significantly reduced daily activity detected (\(Int(point.value)) steps vs \(Int(baseline.mean)) average). Consider gentle movement or consult healthcare provider if feeling unwell."
                    )

                    anomalies.append(anomaly)
                }
            }
        }

        return anomalies
    }

    private func detectActivityPatternAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let stepData = data.timeSeriesData["daily_steps"],
              stepData.count >= 14 else { return nil }

        // Detect unusual inactivity patterns (multiple consecutive low activity days)
        let recentSteps = stepData.suffix(7).map { $0.value }
        let lowActivityDays = recentSteps.filter { $0 < 2000 }.count // Less than 2000 steps

        if lowActivityDays >= 3 { // 3+ days of very low activity
            let anomaly = HealthAnomaly(
                id: UUID().uuidString,
                metricName: "activity_pattern",
                anomalyScore: Double(lowActivityDays) / 7.0,
                anomalyType: .irregular,
                timestamp: stepData.last?.timestamp ?? Date(),
                expectedValue: 7000, // Expected minimum activity
                actualValue: recentSteps.reduce(0, +) / Double(recentSteps.count),
                severity: lowActivityDays >= 5 ? .high : .medium,
                context: "Unusual pattern: \(lowActivityDays) days of very low activity in the past week. Consider gentle exercise or consulting a healthcare provider."
            )

            return [anomaly]
        }

        return nil
    }

    // MARK: - Sleep Anomaly Detection

    private func detectSleepAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly] {
        var anomalies: [HealthAnomaly] = []

        // Sleep duration anomalies
        if let durationAnomalies = try await detectSleepDurationAnomalies(data) {
            anomalies.append(contentsOf: durationAnomalies)
        }

        // Sleep timing anomalies
        if let timingAnomalies = try await detectSleepTimingAnomalies(data) {
            anomalies.append(contentsOf: timingAnomalies)
        }

        return anomalies
    }

    private func detectSleepDurationAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let sleepData = data.timeSeriesData["sleep_duration"],
              sleepData.count >= minimumDataPoints else { return nil }

        let baseline = personalizedBaselines["sleep_duration"] ?? getDefaultBaseline(for: "sleep_duration")
        var anomalies: [HealthAnomaly] = []

        for point in sleepData.suffix(7) {
            let zScore = calculateZScore(value: point.value, baseline: baseline)
            let anomalyScore = calculateAnomalyScore(zScore: zScore)

            // Check for extreme sleep deviations
            if point.value < 4.0 { // Less than 4 hours
                let anomaly = HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "sleep_duration",
                    anomalyScore: max(anomalyScore, 0.8), // High score for very short sleep
                    anomalyType: .decreased,
                    timestamp: point.timestamp,
                    expectedValue: baseline.mean,
                    actualValue: point.value,
                    severity: .high,
                    context: "Severely insufficient sleep detected (\(formatDuration(point.value))). Prioritize sleep hygiene and consider underlying causes."
                )

                anomalies.append(anomaly)
            } else if point.value > 12.0 { // More than 12 hours
                let anomaly = HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "sleep_duration",
                    anomalyScore: max(anomalyScore, 0.7),
                    anomalyType: .elevated,
                    timestamp: point.timestamp,
                    expectedValue: baseline.mean,
                    actualValue: point.value,
                    severity: .medium,
                    context: "Unusually long sleep detected (\(formatDuration(point.value))). May indicate recovery need or underlying sleep disorder."
                )

                anomalies.append(anomaly)
            }
        }

        return anomalies
    }

    private func detectSleepTimingAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let sleepData = data.timeSeriesData["sleep_duration"],
              sleepData.count >= 7 else { return nil }

        // Analyze bedtime consistency using sleep timestamps as proxy for sleep timing
        let recentSleepTimes = sleepData.suffix(7)
        let bedtimeHours = recentSleepTimes.map { point in
            Double(Calendar.current.component(.hour, from: point.timestamp))
        }

        let avgBedtime = bedtimeHours.reduce(0, +) / Double(bedtimeHours.count)
        let variance = calculateVariance(bedtimeHours, mean: avgBedtime)

        // Detect severely irregular sleep timing
        if variance > 9.0 { // More than 3 hours standard deviation
            let anomaly = HealthAnomaly(
                id: UUID().uuidString,
                metricName: "sleep_timing",
                anomalyScore: min(variance / 12.0, 1.0), // Normalize variance
                anomalyType: .irregular,
                timestamp: recentSleepTimes.last?.timestamp ?? Date(),
                expectedValue: avgBedtime,
                actualValue: variance,
                severity: variance > 16.0 ? .high : .medium,
                context: "Highly irregular sleep schedule detected with \(String(format: "%.1f", sqrt(variance))) hour variation. Consistent sleep timing improves sleep quality."
            )

            return [anomaly]
        }

        return nil
    }

    // MARK: - Correlation Anomaly Detection

    private func detectCorrelationAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly] {
        var anomalies: [HealthAnomaly] = []

        // Heart rate and activity correlation anomalies
        if let hrActivityAnomaly = try await detectHeartRateActivityCorrelationAnomaly(data) {
            anomalies.append(hrActivityAnomaly)
        }

        // Sleep and activity correlation anomalies
        if let sleepActivityAnomaly = try await detectSleepActivityCorrelationAnomaly(data) {
            anomalies.append(sleepActivityAnomaly)
        }

        return anomalies
    }

    private func detectHeartRateActivityCorrelationAnomaly(_ data: ProcessedHealthData) async throws -> HealthAnomaly? {
        guard let heartRateData = data.timeSeriesData["heart_rate"],
              let activityData = data.timeSeriesData["daily_steps"],
              heartRateData.count >= 10,
              activityData.count >= 10 else { return nil }

        // Calculate correlation between heart rate and activity for last 14 days
        let recentHR = heartRateData.suffix(14)
        let recentActivity = activityData.suffix(14)

        guard recentHR.count == recentActivity.count else { return nil }

        let correlation = calculateCorrelation(
            recentHR.map { $0.value },
            recentActivity.map { $0.value }
        )

        // Expected positive correlation between HR and activity
        // Negative or very weak correlation could indicate health issues
        if correlation < 0.1 { // Very weak or negative correlation
            let anomalyScore = max(0.0, 0.5 - correlation) // Higher score for negative correlation

            if anomalyScore > 0.4 {
                return HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "hr_activity_correlation",
                    anomalyScore: anomalyScore,
                    anomalyType: .unexpected,
                    timestamp: Date(),
                    expectedValue: 0.5, // Expected moderate positive correlation
                    actualValue: correlation,
                    severity: correlation < -0.2 ? .high : .medium,
                    context: "Unusual relationship between heart rate and activity detected. Heart rate not responding as expected to activity levels."
                )
            }
        }

        return nil
    }

    private func detectSleepActivityCorrelationAnomaly(_ data: ProcessedHealthData) async throws -> HealthAnomaly? {
        guard let sleepData = data.timeSeriesData["sleep_duration"],
              let activityData = data.timeSeriesData["daily_steps"],
              sleepData.count >= 10,
              activityData.count >= 10 else { return nil }

        // Calculate correlation between sleep and next-day activity
        let sleepValues = sleepData.prefix(sleepData.count - 1).map { $0.value }
        let nextDayActivity = activityData.suffix(activityData.count - 1).map { $0.value }

        guard sleepValues.count == nextDayActivity.count else { return nil }

        let correlation = calculateCorrelation(sleepValues, nextDayActivity)

        // Expected positive correlation between good sleep and next-day activity
        if correlation < -0.3 { // Strong negative correlation is unusual
            return HealthAnomaly(
                id: UUID().uuidString,
                metricName: "sleep_activity_correlation",
                anomalyScore: abs(correlation),
                anomalyType: .unexpected,
                timestamp: Date(),
                expectedValue: 0.2, // Expected weak positive correlation
                actualValue: correlation,
                severity: .medium,
                context: "Unusual pattern: better sleep associated with lower next-day activity. Consider factors affecting daily energy levels."
            )
        }

        return nil
    }

    // MARK: - Temporal Anomaly Detection

    private func detectTemporalAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly] {
        var anomalies: [HealthAnomaly] = []

        // Day-of-week anomalies
        if let weekdayAnomalies = try await detectWeekdayAnomalies(data) {
            anomalies.append(contentsOf: weekdayAnomalies)
        }

        // Time-of-day anomalies
        if let timeOfDayAnomalies = try await detectTimeOfDayAnomalies(data) {
            anomalies.append(contentsOf: timeOfDayAnomalies)
        }

        return anomalies
    }

    private func detectWeekdayAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let activityData = data.timeSeriesData["daily_steps"],
              activityData.count >= 21 else { return nil } // Need 3 weeks of data

        // Group activity by day of week
        var dailyActivity: [Int: [Double]] = [:]
        for point in activityData {
            let dayOfWeek = Calendar.current.component(.weekday, from: point.timestamp)
            dailyActivity[dayOfWeek, default: []].append(point.value)
        }

        var anomalies: [HealthAnomaly] = []

        for (day, activities) in dailyActivity {
            if activities.count >= 3 { // At least 3 instances of this day
                let dayAverage = activities.reduce(0, +) / Double(activities.count)
                let overallAverage = activityData.map { $0.value }.reduce(0, +) / Double(activityData.count)

                // Check if this day is significantly different from overall average
                let deviationRatio = abs(dayAverage - overallAverage) / overallAverage

                if deviationRatio > 0.4 { // 40% deviation from average
                    let anomaly = HealthAnomaly(
                        id: UUID().uuidString,
                        metricName: "weekday_pattern",
                        anomalyScore: min(deviationRatio, 1.0),
                        anomalyType: dayAverage < overallAverage ? .decreased : .elevated,
                        timestamp: activityData.last?.timestamp ?? Date(),
                        expectedValue: overallAverage,
                        actualValue: dayAverage,
                        severity: deviationRatio > 0.6 ? .medium : .low,
                        context: "\(dayName(for: day)) shows unusual activity pattern (\(Int(dayAverage)) vs \(Int(overallAverage)) average steps). Consider factors affecting this day."
                    )

                    anomalies.append(anomaly)
                }
            }
        }

        return anomalies.isEmpty ? nil : anomalies
    }

    private func detectTimeOfDayAnomalies(_ data: ProcessedHealthData) async throws -> [HealthAnomaly]? {
        guard let heartRateData = data.timeSeriesData["heart_rate"],
              heartRateData.count >= 50 else { return nil } // Need substantial hourly data

        // Group heart rate by hour of day
        var hourlyHR: [Int: [Double]] = [:]
        for point in heartRateData {
            let hour = Calendar.current.component(.hour, from: point.timestamp)
            hourlyHR[hour, default: []].append(point.value)
        }

        // Check for unusual overnight heart rate elevation
        let nightHours = [23, 0, 1, 2, 3, 4, 5] // 11 PM to 5 AM
        var nightTimeHR: [Double] = []

        for hour in nightHours {
            if let hrValues = hourlyHR[hour] {
                nightTimeHR.append(contentsOf: hrValues)
            }
        }

        if !nightTimeHR.isEmpty {
            let nightAverage = nightTimeHR.reduce(0, +) / Double(nightTimeHR.count)
            let overallAverage = heartRateData.map { $0.value }.reduce(0, +) / Double(heartRateData.count)

            // Nighttime HR should typically be lower than overall average
            if nightAverage > overallAverage * 1.2 { // 20% higher than overall average
                return [HealthAnomaly(
                    id: UUID().uuidString,
                    metricName: "nighttime_heart_rate",
                    anomalyScore: min((nightAverage - overallAverage) / overallAverage, 1.0),
                    anomalyType: .elevated,
                    timestamp: Date(),
                    expectedValue: overallAverage * 0.9, // Expected lower nighttime HR
                    actualValue: nightAverage,
                    severity: nightAverage > overallAverage * 1.3 ? .high : .medium,
                    context: "Elevated nighttime heart rate detected (\(Int(nightAverage)) vs \(Int(overallAverage)) daily average). May indicate stress, poor sleep, or underlying condition."
                )]
            }
        }

        return nil
    }

    // MARK: - Recent Anomaly Detection (for quick insights)

    private func detectRecentVitalSignAnomalies(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        var insights: [HealthInsight] = []

        // Check most recent heart rate readings
        if let heartRateData = data.timeSeriesData["heart_rate"],
           let latestHR = heartRateData.last {
            let baseline = personalizedBaselines["heart_rate"] ?? getDefaultBaseline(for: "heart_rate")
            let zScore = calculateZScore(value: latestHR.value, baseline: baseline)

            if abs(zScore) > 2.0 {
                let insight = HealthInsight(
                    id: UUID().uuidString,
                    title: latestHR.value > baseline.mean ? "Elevated Heart Rate" : "Low Heart Rate",
                    description: "Your recent heart rate (\(Int(latestHR.value)) BPM) is \(abs(zScore) > 2.5 ? "significantly" : "notably") \(latestHR.value > baseline.mean ? "higher" : "lower") than your typical range.",
                    category: .anomaly,
                    priority: abs(zScore) > 3.0 ? .high : .medium,
                    confidence: min(abs(zScore) / 3.0, 1.0),
                    actionable: true,
                    source: .anomalyDetection,
                    generatedDate: Date(),
                    expirationDate: Calendar.current.date(byAdding: .hour, value: 12, to: Date()),
                    metadata: [
                        "metric": "heart_rate",
                        "z_score": zScore,
                        "actual_value": latestHR.value
                    ]
                )
                insights.append(insight)
            }
        }

        return insights
    }

    private func detectRecentActivityAnomalies(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        var insights: [HealthInsight] = []

        if let activityData = data.timeSeriesData["daily_steps"],
           let latestActivity = activityData.last {
            let baseline = personalizedBaselines["daily_steps"] ?? getDefaultBaseline(for: "daily_steps")

            // Check for very low activity
            if latestActivity.value < baseline.mean * 0.3 {
                let insight = HealthInsight(
                    id: UUID().uuidString,
                    title: "Low Activity Alert",
                    description: "Your activity today (\(Int(latestActivity.value)) steps) is significantly lower than usual (\(Int(baseline.mean)) average). Consider gentle movement if feeling well.",
                    category: .warning,
                    priority: .medium,
                    confidence: 0.8,
                    actionable: true,
                    source: .anomalyDetection,
                    generatedDate: Date(),
                    expirationDate: Calendar.current.date(byAdding: .hour, value: 8, to: Date()),
                    metadata: [
                        "metric": "daily_steps",
                        "actual_value": latestActivity.value,
                        "expected_value": baseline.mean
                    ]
                )
                insights.append(insight)
            }
        }

        return insights
    }

    // MARK: - Baseline Management

    private func updatePersonalizedBaselines(_ data: ProcessedHealthData) async throws {
        for (metric, timeSeries) in data.timeSeriesData {
            guard timeSeries.count >= minimumDataPoints else { continue }

            let values = timeSeries.map { $0.value }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = calculateVariance(values, mean: mean)
            let standardDeviation = sqrt(variance)

            let baseline = HealthBaseline(
                mean: mean,
                standardDeviation: standardDeviation,
                minimum: values.min() ?? mean - 2 * standardDeviation,
                maximum: values.max() ?? mean + 2 * standardDeviation,
                dataPoints: values.count,
                lastUpdated: Date()
            )

            personalizedBaselines[metric] = baseline
        }
    }

    private func initializeDefaultBaselines() {
        // Initialize with population-based normal ranges
        personalizedBaselines["heart_rate"] = HealthBaseline(mean: 72, standardDeviation: 12, minimum: 60, maximum: 100, dataPoints: 0, lastUpdated: Date())
        personalizedBaselines["systolic_bp"] = HealthBaseline(mean: 120, standardDeviation: 15, minimum: 90, maximum: 140, dataPoints: 0, lastUpdated: Date())
        personalizedBaselines["daily_steps"] = HealthBaseline(mean: 8000, standardDeviation: 3000, minimum: 2000, maximum: 15000, dataPoints: 0, lastUpdated: Date())
        personalizedBaselines["sleep_duration"] = HealthBaseline(mean: 7.5, standardDeviation: 1.0, minimum: 6, maximum: 9, dataPoints: 0, lastUpdated: Date())
        personalizedBaselines["weight"] = HealthBaseline(mean: 150, standardDeviation: 20, minimum: 100, maximum: 250, dataPoints: 0, lastUpdated: Date())
    }

    private func getDefaultBaseline(for metric: String) -> HealthBaseline {
        return personalizedBaselines[metric] ?? HealthBaseline(mean: 0, standardDeviation: 1, minimum: 0, maximum: 1, dataPoints: 0, lastUpdated: Date())
    }

    // MARK: - Statistical Helper Methods

    private func calculateZScore(value: Double, baseline: HealthBaseline) -> Double {
        guard baseline.standardDeviation > 0 else { return 0 }
        return (value - baseline.mean) / baseline.standardDeviation
    }

    private func calculateAnomalyScore(zScore: Double) -> Double {
        // Convert Z-score to anomaly score (0-1 range)
        let absZScore = abs(zScore)
        return min(max(0, (absZScore - 1.5) / 2.0), 1.0) // Normalize based on threshold
    }

    private func calculateBloodPressureClinicalScore(_ value: Double) -> Double {
        // Clinical thresholds for blood pressure
        if value >= 180 {
            return 1.0 // Hypertensive crisis
        } else if value >= 160 {
            return 0.9 // Stage 2 hypertension
        } else if value >= 140 {
            return 0.7 // Stage 1 hypertension
        } else if value >= 130 {
            return 0.5 // Elevated
        } else if value < 90 {
            return 0.6 // Hypotension
        }
        return 0.0
    }

    private func calculateCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count && !x.isEmpty else { return 0 }

        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map { $0 * $1 }.reduce(0, +)
        let sumXSquared = x.map { $0 * $0 }.reduce(0, +)
        let sumYSquared = y.map { $0 * $0 }.reduce(0, +)

        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumXSquared - sumX * sumX) * (n * sumYSquared - sumY * sumY))

        return denominator != 0 ? numerator / denominator : 0
    }

    private func calculateVariance(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        return squaredDifferences.reduce(0, +) / Double(values.count)
    }

    private func calculateWeightChanges(_ weightData: [TimeSeriesPoint]) -> [Double] {
        guard weightData.count > 1 else { return [] }
        var changes: [Double] = []

        for i in 1..<weightData.count {
            let change = weightData[i].value - weightData[i-1].value
            changes.append(change)
        }

        return changes
    }

    // MARK: - Anomaly Classification

    private func determineAnomalyType(value: Double, baseline: HealthBaseline) -> AnomalyType {
        if value > baseline.mean + baseline.standardDeviation {
            return .elevated
        } else if value < baseline.mean - baseline.standardDeviation {
            return .decreased
        } else {
            return .unexpected
        }
    }

    private func determineSeverity(anomalyScore: Double, metricType: String) -> AnomaalySeverity {
        // Different metrics have different severity thresholds
        switch metricType {
        case "blood_pressure", "heart_rate", "temperature":
            // Vital signs have lower thresholds
            if anomalyScore >= 0.8 {
                return .critical
            } else if anomalyScore >= 0.6 {
                return .high
            } else if anomalyScore >= 0.4 {
                return .medium
            } else {
                return .low
            }
        default:
            if anomalyScore >= 0.9 {
                return .critical
            } else if anomalyScore >= 0.7 {
                return .high
            } else if anomalyScore >= 0.5 {
                return .medium
            } else {
                return .low
            }
        }
    }

    private func calculateOverallRiskLevel(_ anomalies: [HealthAnomaly]) -> AnomalyRiskLevel {
        guard !anomalies.isEmpty else { return .low }

        let criticalCount = anomalies.filter { $0.severity == .critical }.count
        let highCount = anomalies.filter { $0.severity == .high }.count

        if criticalCount > 0 || highCount > 2 {
            return .critical
        } else if highCount > 0 || anomalies.count > 3 {
            return .high
        } else if anomalies.count > 1 {
            return .medium
        } else {
            return .low
        }
    }

    // MARK: - Context Generation

    private func generateAnomalyContext(metricName: String, value: Double, baseline: HealthBaseline, anomalyType: AnomalyType) -> String {
        let deviationFromMean = abs(value - baseline.mean)
        let deviationInSDs = deviationFromMean / baseline.standardDeviation

        var context = "\(metricName) reading of \(String(format: "%.1f", value)) is "

        if deviationInSDs > 3 {
            context += "significantly "
        } else if deviationInSDs > 2 {
            context += "notably "
        }

        switch anomalyType {
        case .elevated:
            context += "higher than your typical range (\(String(format: "%.1f", baseline.mean)) ± \(String(format: "%.1f", baseline.standardDeviation))). "
        case .decreased:
            context += "lower than your typical range (\(String(format: "%.1f", baseline.mean)) ± \(String(format: "%.1f", baseline.standardDeviation))). "
        case .irregular, .unexpected:
            context += "unusual compared to your typical patterns. "
        }

        if deviationInSDs > 2.5 {
            context += "Consider monitoring closely and consult healthcare provider if persistent."
        } else {
            context += "Monitor and consider factors that might influence this reading."
        }

        return context
    }

    private func generateBloodPressureContext(value: Double) -> String {
        if value >= 180 {
            return "Blood pressure of \(Int(value)) mmHg indicates hypertensive crisis. Seek immediate medical attention."
        } else if value >= 160 {
            return "Blood pressure of \(Int(value)) mmHg indicates Stage 2 hypertension. Consult healthcare provider promptly."
        } else if value >= 140 {
            return "Blood pressure of \(Int(value)) mmHg indicates Stage 1 hypertension. Monitor regularly and consider lifestyle modifications."
        } else if value >= 130 {
            return "Blood pressure of \(Int(value)) mmHg is elevated. Consider lifestyle modifications to prevent progression."
        } else if value < 90 {
            return "Blood pressure of \(Int(value)) mmHg is low. Monitor for symptoms like dizziness or fatigue."
        } else {
            return "Blood pressure reading of \(Int(value)) mmHg detected."
        }
    }

    // MARK: - Insight Creation

    private func createInsightFromAnomaly(_ anomaly: HealthAnomaly) -> HealthInsight {
        let priority = anomalyPriorityFromSeverity(anomaly.severity)
        let category = InsightCategory.anomaly

        return HealthInsight(
            id: UUID().uuidString,
            title: formatAnomalyTitle(anomaly),
            description: anomaly.context,
            category: category,
            priority: priority,
            confidence: anomaly.anomalyScore,
            actionable: true,
            source: .anomalyDetection,
            generatedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .day, value: severityExpirationDays(anomaly.severity), to: Date()),
            metadata: [
                "anomaly_type": anomaly.anomalyType.rawValue,
                "severity": anomaly.severity.rawValue,
                "metric_name": anomaly.metricName,
                "actual_value": anomaly.actualValue,
                "expected_value": anomaly.expectedValue
            ],
            relatedData: [anomaly.id]
        )
    }

    private func formatAnomalyTitle(_ anomaly: HealthAnomaly) -> String {
        let metricDisplayName = formatMetricDisplayName(anomaly.metricName)

        switch anomaly.anomalyType {
        case .elevated:
            return "High \(metricDisplayName) Detected"
        case .decreased:
            return "Low \(metricDisplayName) Detected"
        case .irregular:
            return "Irregular \(metricDisplayName) Pattern"
        case .unexpected:
            return "Unusual \(metricDisplayName) Reading"
        }
    }

    private func formatMetricDisplayName(_ metricName: String) -> String {
        switch metricName {
        case "heart_rate":
            return "Heart Rate"
        case "systolic_bp":
            return "Blood Pressure"
        case "daily_steps":
            return "Activity Level"
        case "sleep_duration":
            return "Sleep Duration"
        case "weight":
            return "Weight"
        case "temperature":
            return "Temperature"
        default:
            return metricName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func anomalyPriorityFromSeverity(_ severity: AnomaalySeverity) -> InsightPriority {
        switch severity {
        case .critical:
            return .critical
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        }
    }

    private func severityExpirationDays(_ severity: AnomaalySeverity) -> Int {
        switch severity {
        case .critical:
            return 1 // Critical anomalies expire quickly - need immediate attention
        case .high:
            return 2
        case .medium:
            return 3
        case .low:
            return 5
        }
    }

    // MARK: - Utility Methods

    private func filterRecentData(_ data: ProcessedHealthData, days: Int) -> ProcessedHealthData {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        var filteredTimeSeriesData: [String: [TimeSeriesPoint]] = [:]
        for (key, series) in data.timeSeriesData {
            filteredTimeSeriesData[key] = series.filter { $0.timestamp >= cutoffDate }
        }

        return ProcessedHealthData(
            features: data.features,
            timeSeriesData: filteredTimeSeriesData,
            categoricalData: data.categoricalData,
            quality: data.quality,
            processingDate: data.processingDate,
            dataPointCount: filteredTimeSeriesData.values.map { $0.count }.reduce(0, +)
        )
    }

    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private func dayName(for dayNumber: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayNumber - 1]
    }
}

// MARK: - Supporting Types

struct HealthBaseline {
    let mean: Double
    let standardDeviation: Double
    let minimum: Double
    let maximum: Double
    let dataPoints: Int
    let lastUpdated: Date

    var isPersonalized: Bool {
        return dataPoints >= 10
    }

    var confidenceLevel: Double {
        return min(Double(dataPoints) / 30.0, 1.0) // Full confidence after 30 data points
    }
}

enum AnomalyRiskLevel: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var displayName: String {
        return rawValue.capitalized
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

// MARK: - Error Types

enum AnomalyDetectionError: LocalizedError {
    case detectionFailure(String)
    case insufficientData
    case baselineCalculationFailed
    case processingError(String)

    var errorDescription: String? {
        switch self {
        case .detectionFailure(let message):
            return "Anomaly detection failed: \(message)"
        case .insufficientData:
            return "Insufficient data for anomaly detection"
        case .baselineCalculationFailed:
            return "Failed to calculate health baselines"
        case .processingError(let message):
            return "Processing error: \(message)"
        }
    }
}