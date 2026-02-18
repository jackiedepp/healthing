//
//  MLDataProcessor.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2D: AI-Powered Health Insights
//  Processes and prepares health data for Core ML models
//

import Foundation
import CoreML
import Accelerate
import HealthKit
import os.log

/// Service for processing and preparing health data for machine learning models
/// Handles feature extraction, normalization, and data transformation for AI insights
@MainActor
class MLDataProcessor: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "HealthingApp", category: "MLDataProcessor")

    @Published var isProcessing = false
    @Published var lastProcessingTime: Date?

    // Feature engineering configuration
    private let featureWindowSize = 30 // Days of data for feature calculation
    private let minimumDataPoints = 7 // Minimum required data points for reliable features
    private let maxFeatureValues: [String: Double] = [
        "sleepDuration": 12 * 60 * 60, // 12 hours
        "sleepQuality": 1.0,
        "dailySteps": 50000,
        "activeMinutes": 24 * 60, // 24 hours
        "heartRate": 200,
        "systolicBP": 200,
        "diastolicBP": 120,
        "weight": 200, // kg
        "stressLevel": 1.0
    ]

    // MARK: - Initialization

    init() {
        logger.info("MLDataProcessor initialized")
    }

    // MARK: - Public Methods

    /// Process health data and extract features for ML models
    func processHealthDataForML(_ data: ProcessedHealthData) async throws -> MLFeatureSet {
        logger.info("Processing health data for ML models")

        isProcessing = true
        defer {
            isProcessing = false
            lastProcessingTime = Date()
        }

        // 1. Validate data sufficiency
        try validateDataSufficiency(data)

        // 2. Extract basic health features
        let basicFeatures = try await extractBasicHealthFeatures(data)

        // 3. Calculate temporal features
        let temporalFeatures = try await extractTemporalFeatures(data)

        // 4. Calculate statistical features
        let statisticalFeatures = try await extractStatisticalFeatures(data)

        // 5. Calculate correlation features
        let correlationFeatures = try await extractCorrelationFeatures(data)

        // 6. Calculate trend features
        let trendFeatures = try await extractTrendFeatures(data)

        // 7. Extract circadian rhythm features
        let circadianFeatures = try await extractCircadianRhythmFeatures(data)

        // 8. Combine all features
        let combinedFeatures = combineFeatures(
            basic: basicFeatures,
            temporal: temporalFeatures,
            statistical: statisticalFeatures,
            correlation: correlationFeatures,
            trend: trendFeatures,
            circadian: circadianFeatures
        )

        // 9. Normalize features
        let normalizedFeatures = try normalizeFeatures(combinedFeatures)

        // 10. Create ML feature set
        let mlFeatureSet = MLFeatureSet(
            features: normalizedFeatures,
            metadata: MLFeatureMetadata(
                featureCount: normalizedFeatures.count,
                dataPointCount: calculateTotalDataPoints(data),
                timeRange: calculateTimeRange(data),
                processingDate: Date(),
                qualityScore: calculateDataQualityScore(data)
            ),
            rawData: data
        )

        logger.info("ML feature processing complete: \(normalizedFeatures.count) features extracted")
        return mlFeatureSet
    }

    /// Prepare feature arrays for specific ML model types
    func prepareModelInput<T: MLFeatureProvider>(_ featureSet: MLFeatureSet, for modelType: MLModelType) throws -> T {
        logger.info("Preparing model input for: \(modelType)")

        switch modelType {
        case .healthTrendAnalysis:
            return try prepareHealthTrendInput(featureSet) as! T
        case .anomalyDetection:
            return try prepareAnomalyDetectionInput(featureSet) as! T
        case .patternRecognition:
            return try preparePatternRecognitionInput(featureSet) as! T
        case .riskAssessment:
            return try prepareRiskAssessmentInput(featureSet) as! T
        }
    }

    /// Generate feature importance scores for model interpretability
    func calculateFeatureImportance(_ featureSet: MLFeatureSet, for target: MLTarget) async throws -> FeatureImportanceAnalysis {
        logger.info("Calculating feature importance for target: \(target)")

        // Simplified feature importance calculation
        // In production, this would use proper ML techniques like permutation importance
        var importanceScores: [String: Double] = [:]

        for (featureName, featureValue) in featureSet.features {
            let importance = calculateFeatureRelevance(featureName, value: featureValue, target: target)
            importanceScores[featureName] = importance
        }

        // Sort by importance
        let sortedFeatures = importanceScores.sorted { $0.value > $1.value }

        return FeatureImportanceAnalysis(
            target: target,
            featureScores: importanceScores,
            topFeatures: Array(sortedFeatures.prefix(10)),
            analysisDate: Date()
        )
    }

    /// Validate and clean raw health data before processing
    func preprocessRawHealthData(_ rawData: ProcessedHealthData) async throws -> ProcessedHealthData {
        logger.info("Preprocessing raw health data")

        // 1. Remove outliers
        let cleanedSleepData = try removeOutliers(from: rawData.sleepData)
        let cleanedActivityData = try removeOutliers(from: rawData.activityData)
        let cleanedVitalSignData = try removeOutliers(from: rawData.vitalSignData)

        // 2. Fill missing values
        let filledSleepData = try fillMissingValues(in: cleanedSleepData)
        let filledActivityData = try fillMissingValues(in: cleanedActivityData)
        let filledVitalSignData = try fillMissingValues(in: cleanedVitalSignData)

        // 3. Smooth noisy data
        let smoothedVitalSignData = try smoothVitalSignData(filledVitalSignData)

        return ProcessedHealthData(
            sleepData: filledSleepData,
            activityData: filledActivityData,
            vitalSignData: smoothedVitalSignData,
            hydrationData: rawData.hydrationData, // Usually clean
            mindfulnessData: rawData.mindfulnessData, // Usually clean
            nutritionData: rawData.nutritionData // Usually clean
        )
    }

    /// Create time series features for temporal pattern analysis
    func createTimeSeriesFeatures(_ data: ProcessedHealthData, windowSize: Int = 7) throws -> TimeSeriesFeatures {
        logger.info("Creating time series features with window size: \(windowSize)")

        let sleepTimeSeries = createSleepTimeSeries(data.sleepData, windowSize: windowSize)
        let activityTimeSeries = createActivityTimeSeries(data.activityData, windowSize: windowSize)
        let vitalSignTimeSeries = createVitalSignTimeSeries(data.vitalSignData, windowSize: windowSize)

        return TimeSeriesFeatures(
            sleepSeries: sleepTimeSeries,
            activitySeries: activityTimeSeries,
            vitalSignSeries: vitalSignTimeSeries,
            windowSize: windowSize,
            createdDate: Date()
        )
    }

    // MARK: - Private Methods

    private func validateDataSufficiency(_ data: ProcessedHealthData) throws {
        let totalDataPoints = calculateTotalDataPoints(data)

        if totalDataPoints < minimumDataPoints {
            throw MLDataProcessorError.insufficientData("Need at least \(minimumDataPoints) data points, got \(totalDataPoints)")
        }

        // Check for essential data types
        if data.sleepData.isEmpty {
            logger.warning("No sleep data available for ML processing")
        }
        if data.activityData.isEmpty {
            logger.warning("No activity data available for ML processing")
        }
        if data.vitalSignData.isEmpty {
            logger.warning("No vital sign data available for ML processing")
        }
    }

    private func extractBasicHealthFeatures(_ data: ProcessedHealthData) async throws -> [String: Double] {
        var features: [String: Double] = [:]

        // Sleep features
        if !data.sleepData.isEmpty {
            let avgSleepDuration = data.sleepData.map(\.duration).reduce(0, +) / Double(data.sleepData.count)
            let avgSleepQuality = data.sleepData.map(\.qualityScore).reduce(0, +) / Double(data.sleepData.count)

            features["avg_sleep_duration"] = avgSleepDuration
            features["avg_sleep_quality"] = avgSleepQuality
        }

        // Activity features
        if !data.activityData.isEmpty {
            let avgDailySteps = data.activityData.map { Double($0.steps) }.reduce(0, +) / Double(data.activityData.count)
            let avgActiveMinutes = data.activityData.map { Double($0.activeMinutes) }.reduce(0, +) / Double(data.activityData.count)
            let avgSedentaryMinutes = data.activityData.map { Double($0.sedentaryMinutes) }.reduce(0, +) / Double(data.activityData.count)

            features["avg_daily_steps"] = avgDailySteps
            features["avg_active_minutes"] = avgActiveMinutes
            features["avg_sedentary_minutes"] = avgSedentaryMinutes
        }

        // Vital sign features
        if !data.vitalSignData.isEmpty {
            let heartRates = data.vitalSignData.compactMap(\.heartRate)
            let systolicBPs = data.vitalSignData.compactMap(\.systolicBP)
            let diastolicBPs = data.vitalSignData.compactMap(\.diastolicBP)

            if !heartRates.isEmpty {
                features["avg_heart_rate"] = heartRates.reduce(0, +) / Double(heartRates.count)
            }
            if !systolicBPs.isEmpty {
                features["avg_systolic_bp"] = systolicBPs.reduce(0, +) / Double(systolicBPs.count)
            }
            if !diastolicBPs.isEmpty {
                features["avg_diastolic_bp"] = diastolicBPs.reduce(0, +) / Double(diastolicBPs.count)
            }
        }

        return features
    }

    private func extractTemporalFeatures(_ data: ProcessedHealthData) async throws -> [String: Double] {
        var features: [String: Double] = [:]

        // Weekly patterns
        features.merge(extractWeeklyPatterns(data)) { $1 }

        // Weekend vs weekday differences
        features.merge(extractWeekendWeekdayDifferences(data)) { $1 }

        // Time of day patterns
        features.merge(extractTimeOfDayPatterns(data)) { $1 }

        return features
    }

    private func extractStatisticalFeatures(_ data: ProcessedHealthData) async throws -> [String: Double] {
        var features: [String: Double] = [:]

        // Sleep statistics
        if !data.sleepData.isEmpty {
            let sleepDurations = data.sleepData.map(\.duration)
            features["sleep_duration_std"] = calculateStandardDeviation(sleepDurations)
            features["sleep_duration_cv"] = features["sleep_duration_std"]! / (sleepDurations.reduce(0, +) / Double(sleepDurations.count))

            let sleepQualities = data.sleepData.map(\.qualityScore)
            features["sleep_quality_std"] = calculateStandardDeviation(sleepQualities)
        }

        // Activity statistics
        if !data.activityData.isEmpty {
            let dailySteps = data.activityData.map { Double($0.steps) }
            features["steps_std"] = calculateStandardDeviation(dailySteps)
            features["steps_cv"] = features["steps_std"]! / (dailySteps.reduce(0, +) / Double(dailySteps.count))
        }

        // Vital sign statistics
        if !data.vitalSignData.isEmpty {
            let heartRates = data.vitalSignData.compactMap(\.heartRate)
            if !heartRates.isEmpty {
                features["heart_rate_std"] = calculateStandardDeviation(heartRates)
                features["heart_rate_rmssd"] = calculateRMSSD(heartRates) // Heart rate variability metric
            }
        }

        return features
    }

    private func extractCorrelationFeatures(_ data: ProcessedHealthData) async throws -> [String: Double] {
        var features: [String: Double] = [:]

        // Sleep-Activity correlations
        if !data.sleepData.isEmpty && !data.activityData.isEmpty {
            let sleepQualities = data.sleepData.map(\.qualityScore)
            let dailySteps = data.activityData.map { Double($0.steps) }

            if sleepQualities.count == dailySteps.count {
                features["sleep_activity_correlation"] = calculatePearsonCorrelation(sleepQualities, dailySteps)
            }
        }

        // Heart rate-Activity correlations
        if !data.vitalSignData.isEmpty && !data.activityData.isEmpty {
            let heartRates = data.vitalSignData.compactMap(\.heartRate)
            let activeMinutes = data.activityData.map { Double($0.activeMinutes) }

            if !heartRates.isEmpty && heartRates.count == activeMinutes.count {
                features["heart_rate_activity_correlation"] = calculatePearsonCorrelation(heartRates, activeMinutes)
            }
        }

        return features
    }

    private func extractTrendFeatures(_ data: ProcessedHealthData) async throws -> [String: Double] {
        var features: [String: Double] = [:]

        // Sleep trends
        if data.sleepData.count >= 7 {
            let sleepDurations = data.sleepData.map(\.duration)
            features["sleep_duration_trend"] = calculateLinearTrend(sleepDurations)

            let sleepQualities = data.sleepData.map(\.qualityScore)
            features["sleep_quality_trend"] = calculateLinearTrend(sleepQualities)
        }

        // Activity trends
        if data.activityData.count >= 7 {
            let dailySteps = data.activityData.map { Double($0.steps) }
            features["daily_steps_trend"] = calculateLinearTrend(dailySteps)

            let activeMinutes = data.activityData.map { Double($0.activeMinutes) }
            features["active_minutes_trend"] = calculateLinearTrend(activeMinutes)
        }

        // Weight trends (if available)
        if !data.vitalSignData.isEmpty {
            let weights = data.vitalSignData.compactMap(\.weight)
            if weights.count >= 7 {
                features["weight_trend"] = calculateLinearTrend(weights)
            }
        }

        return features
    }

    private func extractCircadianRhythmFeatures(_ data: ProcessedHealthData) async throws -> [String: Double] {
        var features: [String: Double] = [:]

        // Sleep timing consistency
        if !data.sleepData.isEmpty {
            let bedtimes = data.sleepData.map { Calendar.current.component(.hour, from: $0.startTime) }
            let waketimes = data.sleepData.map { Calendar.current.component(.hour, from: $0.endTime) }

            features["bedtime_consistency"] = 1.0 - (calculateStandardDeviation(bedtimes.map(Double.init)) / 12.0) // Normalized to 0-1
            features["waketime_consistency"] = 1.0 - (calculateStandardDeviation(waketimes.map(Double.init)) / 12.0)

            let avgBedtime = bedtimes.reduce(0, +) / bedtimes.count
            let avgWaketime = waketimes.reduce(0, +) / waketimes.count
            features["avg_bedtime_hour"] = Double(avgBedtime)
            features["avg_waketime_hour"] = Double(avgWaketime)
        }

        // Activity circadian patterns
        if !data.activityData.isEmpty {
            let activityByHour = Dictionary(grouping: data.activityData) {
                Calendar.current.component(.hour, from: $0.timestamp)
            }

            // Peak activity hour
            let hourlyAverages = activityByHour.mapValues { activities in
                activities.map { Double($0.steps) }.reduce(0, +) / Double(activities.count)
            }

            if let peakActivityHour = hourlyAverages.max(by: { $0.value < $1.value })?.key {
                features["peak_activity_hour"] = Double(peakActivityHour)
            }

            // Activity amplitude (difference between peak and trough)
            if let maxActivity = hourlyAverages.values.max(),
               let minActivity = hourlyAverages.values.min() {
                features["activity_amplitude"] = maxActivity - minActivity
            }
        }

        return features
    }

    private func combineFeatures(
        basic: [String: Double],
        temporal: [String: Double],
        statistical: [String: Double],
        correlation: [String: Double],
        trend: [String: Double],
        circadian: [String: Double]
    ) -> [String: Double] {
        var combined: [String: Double] = [:]

        combined.merge(basic) { $1 }
        combined.merge(temporal) { $1 }
        combined.merge(statistical) { $1 }
        combined.merge(correlation) { $1 }
        combined.merge(trend) { $1 }
        combined.merge(circadian) { $1 }

        return combined
    }

    private func normalizeFeatures(_ features: [String: Double]) throws -> [String: Double] {
        var normalized: [String: Double] = [:]

        for (featureName, featureValue) in features {
            // Handle NaN and infinite values
            if featureValue.isNaN || featureValue.isInfinite {
                logger.warning("Invalid feature value for \(featureName): \(featureValue)")
                normalized[featureName] = 0.0
                continue
            }

            // Normalize based on known max values or use z-score normalization
            if let maxValue = maxFeatureValues[featureName.components(separatedBy: "_").first ?? ""] {
                normalized[featureName] = min(1.0, featureValue / maxValue)
            } else {
                // Use min-max normalization with sensible defaults
                normalized[featureName] = max(0.0, min(1.0, featureValue))
            }
        }

        return normalized
    }

    private func calculateTotalDataPoints(_ data: ProcessedHealthData) -> Int {
        return data.sleepData.count + data.activityData.count + data.vitalSignData.count +
               data.hydrationData.count + data.mindfulnessData.count + data.nutritionData.count
    }

    private func calculateTimeRange(_ data: ProcessedHealthData) -> TimeInterval {
        var allDates: [Date] = []
        allDates.append(contentsOf: data.sleepData.map(\.startTime))
        allDates.append(contentsOf: data.activityData.map(\.timestamp))
        allDates.append(contentsOf: data.vitalSignData.map(\.timestamp))

        guard let earliest = allDates.min(), let latest = allDates.max() else {
            return 0
        }

        return latest.timeIntervalSince(earliest)
    }

    private func calculateDataQualityScore(_ data: ProcessedHealthData) -> Double {
        let expectedDays = 30.0
        let sleepCoverage = min(1.0, Double(data.sleepData.count) / expectedDays)
        let activityCoverage = min(1.0, Double(data.activityData.count) / expectedDays)
        let vitalSignCoverage = min(1.0, Double(data.vitalSignData.count) / expectedDays)

        return (sleepCoverage + activityCoverage + vitalSignCoverage) / 3.0
    }

    // MARK: - Statistical Helper Methods

    private func calculateStandardDeviation<T: FloatingPoint>(_ values: [T]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let mean = values.reduce(0, +) / T(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / T(values.count)
        return sqrt(Double(variance))
    }

    private func calculatePearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count && x.count > 1 else { return 0.0 }

        let n = Double(x.count)
        let xMean = x.reduce(0, +) / n
        let yMean = y.reduce(0, +) / n

        let numerator = zip(x, y).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let xVariance = x.map { pow($0 - xMean, 2) }.reduce(0, +)
        let yVariance = y.map { pow($0 - yMean, 2) }.reduce(0, +)

        let denominator = sqrt(xVariance * yVariance)
        return denominator > 0 ? numerator / denominator : 0.0
    }

    private func calculateLinearTrend<T: FloatingPoint>(_ values: [T]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let n = Double(values.count)
        let xValues = Array(1...values.count).map(Double.init)
        let yValues = values.map(Double.init)

        let xMean = xValues.reduce(0, +) / n
        let yMean = yValues.reduce(0, +) / n

        let numerator = zip(xValues, yValues).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let denominator = xValues.map { pow($0 - xMean, 2) }.reduce(0, +)

        return denominator > 0 ? numerator / denominator : 0.0
    }

    private func calculateRMSSD(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let differences = zip(values.dropFirst(), values).map { $0 - $1 }
        let squaredDifferences = differences.map { $0 * $0 }
        let meanSquaredDifference = squaredDifferences.reduce(0, +) / Double(squaredDifferences.count)

        return sqrt(meanSquaredDifference)
    }

    private func extractWeeklyPatterns(_ data: ProcessedHealthData) -> [String: Double] {
        var features: [String: Double] = [:]

        // Group activity data by day of week
        let activityByDay = Dictionary(grouping: data.activityData) {
            Calendar.current.component(.weekday, from: $0.timestamp)
        }

        // Calculate average steps for each day
        for (dayOfWeek, activities) in activityByDay {
            let avgSteps = activities.map { Double($0.steps) }.reduce(0, +) / Double(activities.count)
            let dayName = Calendar.current.weekdaySymbols[dayOfWeek - 1].lowercased()
            features["avg_steps_\(dayName)"] = avgSteps
        }

        return features
    }

    private func extractWeekendWeekdayDifferences(_ data: ProcessedHealthData) -> [String: Double] {
        var features: [String: Double] = [:]

        let weekdayActivities = data.activityData.filter { !Calendar.current.isDateInWeekend($0.timestamp) }
        let weekendActivities = data.activityData.filter { Calendar.current.isDateInWeekend($0.timestamp) }

        if !weekdayActivities.isEmpty && !weekendActivities.isEmpty {
            let weekdayAvgSteps = weekdayActivities.map { Double($0.steps) }.reduce(0, +) / Double(weekdayActivities.count)
            let weekendAvgSteps = weekendActivities.map { Double($0.steps) }.reduce(0, +) / Double(weekendActivities.count)

            features["weekend_weekday_steps_diff"] = weekendAvgSteps - weekdayAvgSteps
            features["weekend_weekday_steps_ratio"] = weekdayAvgSteps > 0 ? weekendAvgSteps / weekdayAvgSteps : 0
        }

        return features
    }

    private func extractTimeOfDayPatterns(_ data: ProcessedHealthData) -> [String: Double] {
        var features: [String: Double] = [:]

        // Morning activity (6-12)
        let morningActivities = data.activityData.filter {
            let hour = Calendar.current.component(.hour, from: $0.timestamp)
            return hour >= 6 && hour < 12
        }

        // Afternoon activity (12-18)
        let afternoonActivities = data.activityData.filter {
            let hour = Calendar.current.component(.hour, from: $0.timestamp)
            return hour >= 12 && hour < 18
        }

        // Evening activity (18-22)
        let eveningActivities = data.activityData.filter {
            let hour = Calendar.current.component(.hour, from: $0.timestamp)
            return hour >= 18 && hour < 22
        }

        if !morningActivities.isEmpty {
            features["morning_avg_steps"] = morningActivities.map { Double($0.steps) }.reduce(0, +) / Double(morningActivities.count)
        }
        if !afternoonActivities.isEmpty {
            features["afternoon_avg_steps"] = afternoonActivities.map { Double($0.steps) }.reduce(0, +) / Double(afternoonActivities.count)
        }
        if !eveningActivities.isEmpty {
            features["evening_avg_steps"] = eveningActivities.map { Double($0.steps) }.reduce(0, +) / Double(eveningActivities.count)
        }

        return features
    }

    // MARK: - Data Preprocessing Methods

    private func removeOutliers(from sleepData: [SleepDataPoint]) throws -> [SleepDataPoint] {
        guard sleepData.count > 3 else { return sleepData }

        let durations = sleepData.map(\.duration)
        let q1 = percentile(durations, 0.25)
        let q3 = percentile(durations, 0.75)
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr

        return sleepData.filter { sleep in
            sleep.duration >= lowerBound && sleep.duration <= upperBound
        }
    }

    private func removeOutliers(from activityData: [ActivityDataPoint]) throws -> [ActivityDataPoint] {
        guard activityData.count > 3 else { return activityData }

        let steps = activityData.map { Double($0.steps) }
        let q1 = percentile(steps, 0.25)
        let q3 = percentile(steps, 0.75)
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr

        return activityData.filter { activity in
            let stepCount = Double(activity.steps)
            return stepCount >= lowerBound && stepCount <= upperBound
        }
    }

    private func removeOutliers(from vitalSignData: [VitalSignDataPoint]) throws -> [VitalSignDataPoint] {
        return vitalSignData.filter { vital in
            // Basic range checks for vital signs
            if let heartRate = vital.heartRate, heartRate < 30 || heartRate > 220 {
                return false
            }
            if let systolic = vital.systolicBP, systolic < 70 || systolic > 250 {
                return false
            }
            if let diastolic = vital.diastolicBP, diastolic < 40 || diastolic > 150 {
                return false
            }
            return true
        }
    }

    private func fillMissingValues(in sleepData: [SleepDataPoint]) throws -> [SleepDataPoint] {
        // For sleep data, missing values are typically whole missing days
        // We don't interpolate sleep data as it would be misleading
        return sleepData
    }

    private func fillMissingValues(in activityData: [ActivityDataPoint]) throws -> [ActivityDataPoint] {
        // For activity data, we might fill very low step counts as zero
        return activityData.map { activity in
            var updated = activity
            if updated.steps < 0 {
                updated.steps = 0
            }
            if updated.activeMinutes < 0 {
                updated.activeMinutes = 0
            }
            if updated.sedentaryMinutes < 0 {
                updated.sedentaryMinutes = 0
            }
            return updated
        }
    }

    private func fillMissingValues(in vitalSignData: [VitalSignDataPoint]) throws -> [VitalSignDataPoint] {
        // Use forward fill for missing vital sign values
        var filled = vitalSignData
        var lastHeartRate: Double?
        var lastSystolicBP: Double?
        var lastDiastolicBP: Double?

        for i in 0..<filled.count {
            if filled[i].heartRate == nil {
                filled[i].heartRate = lastHeartRate
            } else {
                lastHeartRate = filled[i].heartRate
            }

            if filled[i].systolicBP == nil {
                filled[i].systolicBP = lastSystolicBP
            } else {
                lastSystolicBP = filled[i].systolicBP
            }

            if filled[i].diastolicBP == nil {
                filled[i].diastolicBP = lastDiastolicBP
            } else {
                lastDiastolicBP = filled[i].diastolicBP
            }
        }

        return filled
    }

    private func smoothVitalSignData(_ vitalSignData: [VitalSignDataPoint]) throws -> [VitalSignDataPoint] {
        guard vitalSignData.count > 2 else { return vitalSignData }

        var smoothed = vitalSignData

        // Apply simple moving average for heart rate
        for i in 1..<smoothed.count-1 {
            if let prev = vitalSignData[i-1].heartRate,
               let curr = vitalSignData[i].heartRate,
               let next = vitalSignData[i+1].heartRate {
                smoothed[i].heartRate = (prev + curr + next) / 3.0
            }
        }

        return smoothed
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        let index = p * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)

        return sorted[lower] * (1.0 - fraction) + sorted[upper] * fraction
    }

    // MARK: - Model Input Preparation

    private func prepareHealthTrendInput(_ featureSet: MLFeatureSet) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]

        // Select relevant features for trend analysis
        let trendFeatures = featureSet.features.filter { key, _ in
            key.contains("trend") || key.contains("avg_") || key.contains("std")
        }

        for (key, value) in trendFeatures {
            features[key] = MLFeatureValue(double: value)
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func prepareAnomalyDetectionInput(_ featureSet: MLFeatureSet) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]

        // Select features relevant for anomaly detection
        let anomalyFeatures = featureSet.features.filter { key, _ in
            key.contains("std") || key.contains("cv") || key.contains("correlation")
        }

        for (key, value) in anomalyFeatures {
            features[key] = MLFeatureValue(double: value)
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func preparePatternRecognitionInput(_ featureSet: MLFeatureSet) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]

        // Select features for pattern recognition
        let patternFeatures = featureSet.features.filter { key, _ in
            key.contains("avg_") || key.contains("consistency") || key.contains("amplitude")
        }

        for (key, value) in patternFeatures {
            features[key] = MLFeatureValue(double: value)
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func prepareRiskAssessmentInput(_ featureSet: MLFeatureSet) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]

        // Select features for risk assessment
        let riskFeatures = featureSet.features.filter { key, _ in
            key.contains("bp") || key.contains("heart_rate") || key.contains("weight") ||
            key.contains("sleep_duration") || key.contains("activity")
        }

        for (key, value) in riskFeatures {
            features[key] = MLFeatureValue(double: value)
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    // MARK: - Feature Importance Calculation

    private func calculateFeatureRelevance(_ featureName: String, value: Double, target: MLTarget) -> Double {
        // Simplified feature relevance calculation
        switch target {
        case .sleepQuality:
            if featureName.contains("sleep") { return 0.9 }
            if featureName.contains("bedtime") || featureName.contains("waketime") { return 0.7 }
            if featureName.contains("activity") { return 0.5 }
            return 0.3
        case .activityLevel:
            if featureName.contains("steps") || featureName.contains("active") { return 0.9 }
            if featureName.contains("sleep") { return 0.6 }
            return 0.3
        case .heartRateVariability:
            if featureName.contains("heart_rate") { return 0.9 }
            if featureName.contains("stress") || featureName.contains("sleep") { return 0.7 }
            return 0.4
        case .overallWellness:
            return 0.6 // All features are moderately relevant for overall wellness
        }
    }

    // MARK: - Time Series Creation

    private func createSleepTimeSeries(_ sleepData: [SleepDataPoint], windowSize: Int) -> [[Double]] {
        let durations = sleepData.map(\.duration)
        return createWindows(from: durations, windowSize: windowSize)
    }

    private func createActivityTimeSeries(_ activityData: [ActivityDataPoint], windowSize: Int) -> [[Double]] {
        let steps = activityData.map { Double($0.steps) }
        return createWindows(from: steps, windowSize: windowSize)
    }

    private func createVitalSignTimeSeries(_ vitalSignData: [VitalSignDataPoint], windowSize: Int) -> [[Double]] {
        let heartRates = vitalSignData.compactMap(\.heartRate)
        return createWindows(from: heartRates, windowSize: windowSize)
    }

    private func createWindows(from values: [Double], windowSize: Int) -> [[Double]] {
        guard values.count >= windowSize else { return [] }

        var windows: [[Double]] = []
        for i in 0...(values.count - windowSize) {
            let window = Array(values[i..<(i + windowSize)])
            windows.append(window)
        }
        return windows
    }
}

// MARK: - Supporting Data Structures

enum MLDataProcessorError: LocalizedError {
    case insufficientData(String)
    case invalidFeatureValue(String)
    case modelPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientData(let message):
            return "Insufficient data: \(message)"
        case .invalidFeatureValue(let message):
            return "Invalid feature value: \(message)"
        case .modelPreparationFailed(let message):
            return "Model preparation failed: \(message)"
        }
    }
}

enum MLModelType {
    case healthTrendAnalysis
    case anomalyDetection
    case patternRecognition
    case riskAssessment
}

enum MLTarget {
    case sleepQuality
    case activityLevel
    case heartRateVariability
    case overallWellness
}

struct MLFeatureSet {
    let features: [String: Double]
    let metadata: MLFeatureMetadata
    let rawData: ProcessedHealthData
}

struct MLFeatureMetadata {
    let featureCount: Int
    let dataPointCount: Int
    let timeRange: TimeInterval
    let processingDate: Date
    let qualityScore: Double
}

struct FeatureImportanceAnalysis {
    let target: MLTarget
    let featureScores: [String: Double]
    let topFeatures: [(String, Double)]
    let analysisDate: Date
}

struct TimeSeriesFeatures {
    let sleepSeries: [[Double]]
    let activitySeries: [[Double]]
    let vitalSignSeries: [[Double]]
    let windowSize: Int
    let createdDate: Date
}