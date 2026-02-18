import Foundation
import Accelerate
import Combine

/// Pattern recognition service for sleep, activity, and vital sign trends
/// Implements REQ-055: Pattern recognition for sleep, activity, and vital sign trends
@MainActor
class PatternRecognitionService: ObservableObject {
    static let shared = PatternRecognitionService()

    @Published var isAnalyzing = false
    @Published var lastAnalysisDate: Date?
    @Published var discoveredPatterns: [HealthPattern] = []

    // Analysis configuration
    private let minimumDataPoints = 7 // Minimum days of data for pattern analysis
    private let analysisWindowDays = 30 // Default analysis window
    private let confidenceThreshold = 0.6 // Minimum confidence for pattern recognition

    private init() {}

    // MARK: - Pattern Analysis

    /// Analyze health patterns from processed health data
    func analyzeHealthPatterns(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        var insights: [HealthInsight] = []

        do {
            // Analyze different types of patterns
            let sleepPatterns = try await analyzeSleepPatterns(data)
            let activityPatterns = try await analyzeActivityPatterns(data)
            let vitalSignPatterns = try await analyzeVitalSignPatterns(data)
            let circadianPatterns = try await analyzeCircadianPatterns(data)
            let weeklyPatterns = try await analyzeWeeklyPatterns(data)

            // Combine all patterns
            let allPatterns = sleepPatterns + activityPatterns + vitalSignPatterns + circadianPatterns + weeklyPatterns

            // Filter patterns by confidence
            let significantPatterns = allPatterns.filter { $0.strength >= confidenceThreshold }

            // Convert patterns to insights
            for pattern in significantPatterns {
                let insight = createInsightFromPattern(pattern)
                insights.append(insight)
            }

            // Store discovered patterns
            discoveredPatterns = significantPatterns
            lastAnalysisDate = Date()

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            print("🔍 PatternRecognitionService: Analyzed \(significantPatterns.count) patterns in \(processingTime)s")

            return insights

        } catch {
            print("❌ PatternRecognitionService: Pattern analysis failed: \(error)")
            throw PatternRecognitionError.analysisFailure(error.localizedDescription)
        }
    }

    /// Analyze recent patterns for quick insights
    func analyzeRecentPatterns(_ data: ProcessedHealthData, days: Int) async throws -> [HealthInsight] {
        let recentData = filterDataForRecentDays(data, days: days)

        if recentData.dataPointCount < minimumDataPoints {
            throw PatternRecognitionError.insufficientData
        }

        // Focus on short-term patterns for recent analysis
        let insights: [HealthInsight] = []

        // Quick circadian rhythm analysis
        let circadianInsights = try await analyzeRecentCircadianPatterns(recentData)

        // Quick activity pattern analysis
        let activityInsights = try await analyzeRecentActivityPatterns(recentData)

        return circadianInsights + activityInsights
    }

    // MARK: - Sleep Pattern Analysis

    private func analyzeSleepPatterns(_ data: ProcessedHealthData) async throws -> [HealthPattern] {
        guard let sleepTimeSeries = extractSleepTimeSeries(data) else {
            return []
        }

        var patterns: [HealthPattern] = []

        // Sleep duration patterns
        if let durationPattern = try await analyzeSleepDurationPattern(sleepTimeSeries) {
            patterns.append(durationPattern)
        }

        // Sleep quality patterns
        if let qualityPattern = try await analyzeSleepQualityPattern(sleepTimeSeries) {
            patterns.append(qualityPattern)
        }

        // Bedtime consistency patterns
        if let bedtimePattern = try await analyzeBedtimeConsistencyPattern(sleepTimeSeries) {
            patterns.append(bedtimePattern)
        }

        // Sleep efficiency trends
        if let efficiencyPattern = try await analyzeSleepEfficiencyPattern(sleepTimeSeries) {
            patterns.append(efficiencyPattern)
        }

        return patterns
    }

    private func analyzeSleepDurationPattern(_ sleepData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        let durations = sleepData.map { $0.value }

        guard durations.count >= minimumDataPoints else { return nil }

        // Calculate statistics
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let variance = calculateVariance(durations, mean: avgDuration)
        let trend = calculateTrend(durations)

        // Analyze weekday vs weekend patterns
        let weekdayDurations = filterWeekdays(sleepData).map { $0.value }
        let weekendDurations = filterWeekends(sleepData).map { $0.value }

        let weekdayAvg = weekdayDurations.isEmpty ? 0 : weekdayDurations.reduce(0, +) / Double(weekdayDurations.count)
        let weekendAvg = weekendDurations.isEmpty ? 0 : weekendDurations.reduce(0, +) / Double(weekendDurations.count)

        let weekdayWeekendDiff = abs(weekdayAvg - weekendAvg)

        // Determine pattern strength based on consistency and trends
        var strength = 1.0 - (variance / avgDuration) // More consistent = stronger pattern
        strength = min(max(strength, 0.0), 1.0)

        var description = "Your sleep duration "
        if trend > 0.1 {
            description += "has been increasing over time"
        } else if trend < -0.1 {
            description += "has been decreasing over time"
        } else {
            description += "has been relatively stable"
        }

        if weekdayWeekendDiff > 0.5 {
            description += ", with significant differences between weekdays and weekends"
        }

        description += ". Average sleep: \(formatDuration(avgDuration))"

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .sleep,
            description: description,
            frequency: determineFrequency(variance),
            strength: strength,
            affectedMetrics: ["sleep_duration"],
            timeRange: DateInterval(start: sleepData.first?.timestamp ?? Date(), end: sleepData.last?.timestamp ?? Date())
        )
    }

    private func analyzeSleepQualityPattern(_ sleepData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        // This would analyze sleep quality metrics like REM, deep sleep, restlessness
        // For now, create a simplified analysis based on sleep efficiency

        let efficiencyValues = sleepData.compactMap { point in
            // Simulate sleep efficiency calculation
            return calculateSimulatedSleepEfficiency(duration: point.value)
        }

        guard efficiencyValues.count >= minimumDataPoints else { return nil }

        let avgEfficiency = efficiencyValues.reduce(0, +) / Double(efficiencyValues.count)
        let variance = calculateVariance(efficiencyValues, mean: avgEfficiency)
        let trend = calculateTrend(efficiencyValues)

        let strength = 1.0 - variance // Lower variance = stronger pattern

        var description = "Your sleep quality "
        if avgEfficiency > 0.85 {
            description += "is consistently excellent"
        } else if avgEfficiency > 0.75 {
            description += "is generally good"
        } else {
            description += "shows room for improvement"
        }

        if trend > 0.05 {
            description += " and improving over time"
        } else if trend < -0.05 {
            description += " and showing declining trends"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .sleep,
            description: description,
            frequency: "nightly",
            strength: min(max(strength, 0.0), 1.0),
            affectedMetrics: ["sleep_quality", "sleep_efficiency"],
            timeRange: DateInterval(start: sleepData.first?.timestamp ?? Date(), end: sleepData.last?.timestamp ?? Date())
        )
    }

    private func analyzeBedtimeConsistencyPattern(_ sleepData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        // Extract bedtime from timestamps (assuming sleep start times)
        let bedtimes = sleepData.map { point in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: point.timestamp)
            let bedtimeMinutes = (components.hour ?? 22) * 60 + (components.minute ?? 0)
            return Double(bedtimeMinutes)
        }

        guard bedtimes.count >= minimumDataPoints else { return nil }

        let avgBedtime = bedtimes.reduce(0, +) / Double(bedtimes.count)
        let variance = calculateVariance(bedtimes, mean: avgBedtime)
        let standardDeviation = sqrt(variance)

        // Consistency strength - lower variance = more consistent
        let strength = max(0.0, 1.0 - (standardDeviation / 60.0)) // Normalize by 1 hour

        var description = "Your bedtime "
        if standardDeviation < 20 {
            description += "is very consistent"
        } else if standardDeviation < 45 {
            description += "is moderately consistent"
        } else {
            description += "varies significantly"
        }

        let avgHour = Int(avgBedtime / 60) % 24
        let avgMinute = Int(avgBedtime.truncatingRemainder(dividingBy: 60))
        description += ", averaging around \(formatTime(hour: avgHour, minute: avgMinute))"

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .circadian,
            description: description,
            frequency: "daily",
            strength: strength,
            affectedMetrics: ["bedtime_consistency"],
            timeRange: DateInterval(start: sleepData.first?.timestamp ?? Date(), end: sleepData.last?.timestamp ?? Date())
        )
    }

    private func analyzeSleepEfficiencyPattern(_ sleepData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        let efficiencyData = sleepData.map { point in
            calculateSimulatedSleepEfficiency(duration: point.value)
        }

        guard efficiencyData.count >= minimumDataPoints else { return nil }

        let avgEfficiency = efficiencyData.reduce(0, +) / Double(efficiencyData.count)
        let trend = calculateTrend(efficiencyData)
        let variance = calculateVariance(efficiencyData, mean: avgEfficiency)

        let strength = min(max(1.0 - variance, 0.0), 1.0)

        var description = "Your sleep efficiency "
        if avgEfficiency > 0.9 {
            description += "is excellent"
        } else if avgEfficiency > 0.8 {
            description += "is good"
        } else {
            description += "could be improved"
        }

        if trend > 0.02 {
            description += " and improving"
        } else if trend < -0.02 {
            description += " and declining"
        } else {
            description += " and stable"
        }

        description += " (avg: \(Int(avgEfficiency * 100))%)"

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .sleep,
            description: description,
            frequency: "nightly",
            strength: strength,
            affectedMetrics: ["sleep_efficiency"],
            timeRange: DateInterval(start: sleepData.first?.timestamp ?? Date(), end: sleepData.last?.timestamp ?? Date())
        )
    }

    // MARK: - Activity Pattern Analysis

    private func analyzeActivityPatterns(_ data: ProcessedHealthData) async throws -> [HealthPattern] {
        guard let activityTimeSeries = extractActivityTimeSeries(data) else {
            return []
        }

        var patterns: [HealthPattern] = []

        // Daily activity patterns
        if let dailyPattern = try await analyzeDailyActivityPattern(activityTimeSeries) {
            patterns.append(dailyPattern)
        }

        // Weekly activity patterns
        if let weeklyPattern = try await analyzeWeeklyActivityPattern(activityTimeSeries) {
            patterns.append(weeklyPattern)
        }

        // Activity intensity patterns
        if let intensityPattern = try await analyzeActivityIntensityPattern(activityTimeSeries) {
            patterns.append(intensityPattern)
        }

        return patterns
    }

    private func analyzeDailyActivityPattern(_ activityData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        guard activityData.count >= minimumDataPoints else { return nil }

        let stepCounts = activityData.map { $0.value }
        let avgSteps = stepCounts.reduce(0, +) / Double(stepCounts.count)
        let variance = calculateVariance(stepCounts, mean: avgSteps)
        let trend = calculateTrend(stepCounts)

        // Calculate consistency strength
        let strength = max(0.0, 1.0 - (variance / (avgSteps * avgSteps)))

        var description = "Your daily activity averages \(Int(avgSteps)) steps"

        if trend > 50 {
            description += ", with an increasing trend"
        } else if trend < -50 {
            description += ", with a decreasing trend"
        } else {
            description += ", maintaining consistent levels"
        }

        if avgSteps > 10000 {
            description += ". Excellent daily activity!"
        } else if avgSteps > 7500 {
            description += ". Good daily activity level."
        } else {
            description += ". Consider increasing daily movement."
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .activity,
            description: description,
            frequency: "daily",
            strength: min(strength, 1.0),
            affectedMetrics: ["daily_steps", "activity_level"],
            timeRange: DateInterval(start: activityData.first?.timestamp ?? Date(), end: activityData.last?.timestamp ?? Date())
        )
    }

    private func analyzeWeeklyActivityPattern(_ activityData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        // Group activity by day of week
        var dailyAverages: [Int: [Double]] = [:]

        for point in activityData {
            let dayOfWeek = Calendar.current.component(.weekday, from: point.timestamp)
            dailyAverages[dayOfWeek, default: []].append(point.value)
        }

        guard dailyAverages.count >= 5 else { return nil } // Need at least 5 different days

        var weeklyPattern: [Double] = []
        for day in 1...7 {
            if let dayData = dailyAverages[day], !dayData.isEmpty {
                weeklyPattern.append(dayData.reduce(0, +) / Double(dayData.count))
            } else {
                weeklyPattern.append(0)
            }
        }

        // Find peak activity days
        let maxActivity = weeklyPattern.max() ?? 0
        let minActivity = weeklyPattern.min() ?? 0
        let activityRange = maxActivity - minActivity
        let strength = activityRange > 1000 ? min(activityRange / 5000, 1.0) : 0.3

        let peakDays = weeklyPattern.enumerated().compactMap { index, value in
            value > maxActivity * 0.9 ? dayName(for: index + 1) : nil
        }

        let lowDays = weeklyPattern.enumerated().compactMap { index, value in
            value < minActivity * 1.1 ? dayName(for: index + 1) : nil
        }

        var description = "Your weekly activity shows "
        if !peakDays.isEmpty {
            description += "peak activity on \(peakDays.joined(separator: ", "))"
        }
        if !lowDays.isEmpty && !peakDays.isEmpty {
            description += " and lower activity on \(lowDays.joined(separator: ", "))"
        } else if !lowDays.isEmpty {
            description += "lower activity on \(lowDays.joined(separator: ", "))"
        } else {
            description += "consistent activity throughout the week"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .weekly,
            description: description,
            frequency: "weekly",
            strength: strength,
            affectedMetrics: ["weekly_activity", "step_distribution"],
            timeRange: DateInterval(start: activityData.first?.timestamp ?? Date(), end: activityData.last?.timestamp ?? Date())
        )
    }

    private func analyzeActivityIntensityPattern(_ activityData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        // Analyze intensity based on step count variations and patterns
        let stepCounts = activityData.map { $0.value }
        guard stepCounts.count >= minimumDataPoints else { return nil }

        // Categorize intensity levels
        let highIntensityDays = stepCounts.filter { $0 > 12000 }.count
        let moderateIntensityDays = stepCounts.filter { $0 > 8000 && $0 <= 12000 }.count
        let lowIntensityDays = stepCounts.filter { $0 <= 8000 }.count

        let totalDays = stepCounts.count
        let highPercentage = Double(highIntensityDays) / Double(totalDays)
        let moderatePercentage = Double(moderateIntensityDays) / Double(totalDays)
        let lowPercentage = Double(lowIntensityDays) / Double(totalDays)

        // Pattern strength based on distribution
        let strength = 1.0 - abs(0.33 - highPercentage) - abs(0.33 - moderatePercentage) - abs(0.33 - lowPercentage)

        var description = "Your activity intensity shows "
        if highPercentage > 0.4 {
            description += "frequent high-intensity days (\(Int(highPercentage * 100))%)"
        } else if moderatePercentage > 0.5 {
            description += "predominantly moderate activity levels (\(Int(moderatePercentage * 100))%)"
        } else if lowPercentage > 0.5 {
            description += "primarily low-intensity activity (\(Int(lowPercentage * 100))%)"
        } else {
            description += "a balanced mix of activity intensities"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .activity,
            description: description,
            frequency: "daily",
            strength: max(0.0, min(strength, 1.0)),
            affectedMetrics: ["activity_intensity", "exercise_variety"],
            timeRange: DateInterval(start: activityData.first?.timestamp ?? Date(), end: activityData.last?.timestamp ?? Date())
        )
    }

    // MARK: - Vital Sign Pattern Analysis

    private func analyzeVitalSignPatterns(_ data: ProcessedHealthData) async throws -> [HealthPattern] {
        var patterns: [HealthPattern] = []

        // Heart rate patterns
        if let heartRateTimeSeries = data.timeSeriesData["heart_rate"] {
            if let hrPattern = try await analyzeHeartRatePattern(heartRateTimeSeries) {
                patterns.append(hrPattern)
            }
        }

        // Blood pressure patterns (if available)
        if let bpTimeSeries = data.timeSeriesData["blood_pressure"] {
            if let bpPattern = try await analyzeBloodPressurePattern(bpTimeSeries) {
                patterns.append(bpPattern)
            }
        }

        // Weight patterns
        if let weightTimeSeries = data.timeSeriesData["weight"] {
            if let weightPattern = try await analyzeWeightPattern(weightTimeSeries) {
                patterns.append(weightPattern)
            }
        }

        return patterns
    }

    private func analyzeHeartRatePattern(_ heartRateData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        guard heartRateData.count >= minimumDataPoints else { return nil }

        let rates = heartRateData.map { $0.value }
        let avgRate = rates.reduce(0, +) / Double(rates.count)
        let variance = calculateVariance(rates, mean: avgRate)
        let trend = calculateTrend(rates)

        // Analyze time-of-day patterns
        let morningRates = heartRateData.filter { isMorning($0.timestamp) }.map { $0.value }
        let eveningRates = heartRateData.filter { isEvening($0.timestamp) }.map { $0.value }

        let morningAvg = morningRates.isEmpty ? 0 : morningRates.reduce(0, +) / Double(morningRates.count)
        let eveningAvg = eveningRates.isEmpty ? 0 : eveningRates.reduce(0, +) / Double(eveningRates.count)

        let strength = max(0.0, 1.0 - (variance / (avgRate * avgRate)))

        var description = "Your heart rate averages \(Int(avgRate)) BPM"

        if trend > 2 {
            description += " with an increasing trend"
        } else if trend < -2 {
            description += " with a decreasing trend"
        } else {
            description += " with stable patterns"
        }

        if abs(morningAvg - eveningAvg) > 10 {
            description += ". Shows typical circadian variation (\(Int(morningAvg)) AM vs \(Int(eveningAvg)) PM)"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .circadian,
            description: description,
            frequency: "daily",
            strength: strength,
            affectedMetrics: ["heart_rate", "resting_heart_rate"],
            timeRange: DateInterval(start: heartRateData.first?.timestamp ?? Date(), end: heartRateData.last?.timestamp ?? Date())
        )
    }

    private func analyzeBloodPressurePattern(_ bpData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        guard bpData.count >= minimumDataPoints else { return nil }

        let pressures = bpData.map { $0.value }
        let avgPressure = pressures.reduce(0, +) / Double(pressures.count)
        let variance = calculateVariance(pressures, mean: avgPressure)
        let trend = calculateTrend(pressures)

        let strength = max(0.0, 1.0 - (variance / (avgPressure * avgPressure)))

        var description = "Your blood pressure averages \(Int(avgPressure)) mmHg"

        if trend > 5 {
            description += " with an increasing trend - consider monitoring"
        } else if trend < -5 {
            description += " with a decreasing trend"
        } else {
            description += " maintaining stable levels"
        }

        // Basic BP categorization
        if avgPressure < 120 {
            description += ". Excellent pressure levels!"
        } else if avgPressure < 140 {
            description += ". Generally healthy range."
        } else {
            description += ". Consider consulting healthcare provider."
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .vital,
            description: description,
            frequency: "daily",
            strength: strength,
            affectedMetrics: ["blood_pressure", "cardiovascular_health"],
            timeRange: DateInterval(start: bpData.first?.timestamp ?? Date(), end: bpData.last?.timestamp ?? Date())
        )
    }

    private func analyzeWeightPattern(_ weightData: [TimeSeriesPoint]) async throws -> HealthPattern? {
        guard weightData.count >= minimumDataPoints else { return nil }

        let weights = weightData.map { $0.value }
        let avgWeight = weights.reduce(0, +) / Double(weights.count)
        let trend = calculateTrend(weights)
        let variance = calculateVariance(weights, mean: avgWeight)

        let strength = max(0.0, 1.0 - (variance / 10.0)) // Weight variance normalized

        var description = "Your weight "
        if abs(trend) < 0.1 {
            description += "remains stable at \(String(format: "%.1f", avgWeight)) lbs"
        } else if trend > 0.2 {
            description += "shows an increasing trend (\(String(format: "+%.1f", trend)) lbs)"
        } else if trend < -0.2 {
            description += "shows a decreasing trend (\(String(format: "%.1f", trend)) lbs)"
        } else {
            description += "shows minor fluctuations around \(String(format: "%.1f", avgWeight)) lbs"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .weekly,
            description: description,
            frequency: "daily",
            strength: strength,
            affectedMetrics: ["weight", "body_composition"],
            timeRange: DateInterval(start: weightData.first?.timestamp ?? Date(), end: weightData.last?.timestamp ?? Date())
        )
    }

    // MARK: - Circadian Pattern Analysis

    private func analyzeCircadianPatterns(_ data: ProcessedHealthData) async throws -> [HealthPattern] {
        var patterns: [HealthPattern] = []

        // Activity-based circadian patterns
        if let activityPattern = try await analyzeActivityCircadianPattern(data) {
            patterns.append(activityPattern)
        }

        // Heart rate circadian patterns
        if let hrPattern = try await analyzeHeartRateCircadianPattern(data) {
            patterns.append(hrPattern)
        }

        return patterns
    }

    private func analyzeActivityCircadianPattern(_ data: ProcessedHealthData) async throws -> HealthPattern? {
        guard let activityTimeSeries = extractActivityTimeSeries(data) else { return nil }

        // Group activity by hour of day
        var hourlyActivity: [Int: [Double]] = [:]

        for point in activityTimeSeries {
            let hour = Calendar.current.component(.hour, from: point.timestamp)
            hourlyActivity[hour, default: []].append(point.value)
        }

        guard hourlyActivity.count >= 12 else { return nil } // Need data for at least half the day

        // Calculate average activity for each hour
        var hourlyAverages: [Int: Double] = [:]
        for (hour, activities) in hourlyActivity {
            hourlyAverages[hour] = activities.reduce(0, +) / Double(activities.count)
        }

        // Find peak activity hours
        let maxActivity = hourlyAverages.values.max() ?? 0
        let peakHours = hourlyAverages.filter { $0.value > maxActivity * 0.8 }.keys.sorted()

        let strength = hourlyAverages.count >= 20 ? 0.8 : 0.6 // More data = stronger pattern

        var description = "Your activity peaks "
        if peakHours.count == 1 {
            description += "around \(formatHour(peakHours[0]))"
        } else if peakHours.count <= 3 {
            description += "between \(formatHour(peakHours.first!)) and \(formatHour(peakHours.last!))"
        } else {
            description += "throughout the day with high variability"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .circadian,
            description: description,
            frequency: "daily",
            strength: strength,
            affectedMetrics: ["hourly_activity", "circadian_rhythm"],
            timeRange: DateInterval(start: activityTimeSeries.first?.timestamp ?? Date(), end: activityTimeSeries.last?.timestamp ?? Date())
        )
    }

    private func analyzeHeartRateCircadianPattern(_ data: ProcessedHealthData) async throws -> HealthPattern? {
        guard let heartRateTimeSeries = data.timeSeriesData["heart_rate"] else { return nil }

        // Group heart rate by hour of day
        var hourlyHeartRate: [Int: [Double]] = [:]

        for point in heartRateTimeSeries {
            let hour = Calendar.current.component(.hour, from: point.timestamp)
            hourlyHeartRate[hour, default: []].append(point.value)
        }

        guard hourlyHeartRate.count >= 8 else { return nil } // Need data for at least 8 hours

        // Calculate average heart rate for each hour
        var hourlyAverages: [Int: Double] = [:]
        for (hour, rates) in hourlyHeartRate {
            hourlyAverages[hour] = rates.reduce(0, +) / Double(rates.count)
        }

        // Analyze circadian variation
        let maxHR = hourlyAverages.values.max() ?? 0
        let minHR = hourlyAverages.values.min() ?? 0
        let hrVariation = maxHR - minHR

        let strength = hrVariation > 20 ? min(hrVariation / 50, 1.0) : 0.4

        var description = "Your heart rate shows "
        if hrVariation > 30 {
            description += "strong circadian rhythm (range: \(Int(minHR))-\(Int(maxHR)) BPM)"
        } else if hrVariation > 15 {
            description += "moderate circadian variation (\(Int(hrVariation)) BPM range)"
        } else {
            description += "minimal circadian variation"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .circadian,
            description: description,
            frequency: "daily",
            strength: strength,
            affectedMetrics: ["heart_rate_circadian", "autonomic_rhythm"],
            timeRange: DateInterval(start: heartRateTimeSeries.first?.timestamp ?? Date(), end: heartRateTimeSeries.last?.timestamp ?? Date())
        )
    }

    // MARK: - Weekly Pattern Analysis

    private func analyzeWeeklyPatterns(_ data: ProcessedHealthData) async throws -> [HealthPattern] {
        var patterns: [HealthPattern] = []

        // Weekly sleep patterns
        if let sleepWeeklyPattern = try await analyzeWeeklySleepPattern(data) {
            patterns.append(sleepWeeklyPattern)
        }

        // Weekly activity patterns (already covered in activity analysis)
        // Could add more weekly pattern types here

        return patterns
    }

    private func analyzeWeeklySleepPattern(_ data: ProcessedHealthData) async throws -> HealthPattern? {
        guard let sleepTimeSeries = extractSleepTimeSeries(data) else { return nil }

        // Group sleep by day of week
        var dailySleep: [Int: [Double]] = [:]

        for point in sleepTimeSeries {
            let dayOfWeek = Calendar.current.component(.weekday, from: point.timestamp)
            dailySleep[dayOfWeek, default: []].append(point.value)
        }

        guard dailySleep.count >= 5 else { return nil }

        // Calculate average sleep for each day
        var dailyAverages: [Int: Double] = [:]
        for (day, sleepDurations) in dailySleep {
            dailyAverages[day] = sleepDurations.reduce(0, +) / Double(sleepDurations.count)
        }

        // Compare weekdays vs weekends
        let weekdayAverage = [2, 3, 4, 5, 6].compactMap { dailyAverages[$0] }.reduce(0, +) / 5.0
        let weekendAverage = [1, 7].compactMap { dailyAverages[$0] }.reduce(0, +) / 2.0

        let weekendDifference = weekendAverage - weekdayAverage
        let strength = abs(weekendDifference) > 0.5 ? min(abs(weekendDifference) / 2.0, 1.0) : 0.3

        var description = "Your weekly sleep pattern shows "
        if weekendDifference > 0.5 {
            description += "longer sleep on weekends (+\(formatDuration(weekendDifference)))"
        } else if weekendDifference < -0.5 {
            description += "shorter sleep on weekends (\(formatDuration(weekendDifference)))"
        } else {
            description += "consistent sleep duration throughout the week"
        }

        return HealthPattern(
            id: UUID().uuidString,
            patternType: .weekly,
            description: description,
            frequency: "weekly",
            strength: strength,
            affectedMetrics: ["weekly_sleep", "sleep_consistency"],
            timeRange: DateInterval(start: sleepTimeSeries.first?.timestamp ?? Date(), end: sleepTimeSeries.last?.timestamp ?? Date())
        )
    }

    // MARK: - Recent Pattern Analysis

    private func analyzeRecentCircadianPatterns(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        // Quick analysis of recent circadian patterns for dashboard
        var insights: [HealthInsight] = []

        if let recentSleepInsight = try await analyzeRecentSleepTiming(data) {
            insights.append(recentSleepInsight)
        }

        return insights
    }

    private func analyzeRecentActivityPatterns(_ data: ProcessedHealthData) async throws -> [HealthInsight] {
        // Quick analysis of recent activity patterns
        var insights: [HealthInsight] = []

        if let activityInsight = try await analyzeRecentActivityTrends(data) {
            insights.append(activityInsight)
        }

        return insights
    }

    private func analyzeRecentSleepTiming(_ data: ProcessedHealthData) async throws -> HealthInsight? {
        guard let sleepTimeSeries = extractSleepTimeSeries(data), sleepTimeSeries.count >= 3 else { return nil }

        let recentSleepTimes = sleepTimeSeries.suffix(7) // Last week
        let bedtimes = recentSleepTimes.map { point in
            Calendar.current.component(.hour, from: point.timestamp)
        }

        let avgBedtime = bedtimes.reduce(0, +) / bedtimes.count
        let variance = calculateVariance(bedtimes.map { Double($0) }, mean: Double(avgBedtime))

        let title: String
        let description: String
        let priority: InsightPriority

        if variance < 1.0 {
            title = "Consistent Sleep Schedule"
            description = "Great job maintaining a consistent bedtime around \(formatHour(avgBedtime))"
            priority = .low
        } else if variance < 4.0 {
            title = "Moderate Sleep Consistency"
            description = "Your bedtime varies moderately. Try to maintain a more regular schedule."
            priority = .medium
        } else {
            title = "Irregular Sleep Schedule"
            description = "Your bedtime varies significantly. A consistent sleep schedule could improve your rest quality."
            priority = .high
        }

        return HealthInsight(
            id: UUID().uuidString,
            title: title,
            description: description,
            category: .trend,
            priority: priority,
            confidence: 0.8,
            actionable: true,
            source: .patternRecognition,
            generatedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            metadata: [
                "pattern_type": "circadian_sleep",
                "avg_bedtime": avgBedtime,
                "variance": variance
            ]
        )
    }

    private func analyzeRecentActivityTrends(_ data: ProcessedHealthData) async throws -> HealthInsight? {
        guard let activityTimeSeries = extractActivityTimeSeries(data), activityTimeSeries.count >= 3 else { return nil }

        let recentSteps = activityTimeSeries.suffix(7).map { $0.value }
        let avgSteps = recentSteps.reduce(0, +) / Double(recentSteps.count)
        let trend = calculateTrend(Array(recentSteps))

        let title: String
        let description: String
        let priority: InsightPriority

        if trend > 500 {
            title = "Increasing Activity"
            description = "Your daily activity has been increasing! Keep up the great momentum."
            priority = .low
        } else if trend < -500 {
            title = "Decreasing Activity"
            description = "Your activity levels have been declining. Consider setting activity reminders."
            priority = .medium
        } else {
            title = "Stable Activity Level"
            description = "Your activity remains consistent at \(Int(avgSteps)) daily steps."
            priority = .low
        }

        return HealthInsight(
            id: UUID().uuidString,
            title: title,
            description: description,
            category: .trend,
            priority: priority,
            confidence: 0.75,
            actionable: true,
            source: .patternRecognition,
            generatedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
            metadata: [
                "pattern_type": "activity_trend",
                "avg_steps": avgSteps,
                "trend": trend
            ]
        )
    }

    // MARK: - Helper Methods

    private func createInsightFromPattern(_ pattern: HealthPattern) -> HealthInsight {
        let priority = determinePriorityFromPattern(pattern)
        let category = categoryFromPatternType(pattern.patternType)

        return HealthInsight(
            id: UUID().uuidString,
            title: generatePatternTitle(pattern),
            description: pattern.description,
            category: category,
            priority: priority,
            confidence: pattern.strength,
            actionable: true,
            source: .patternRecognition,
            generatedDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .week, value: 1, to: Date()),
            metadata: [
                "pattern_type": pattern.patternType.rawValue,
                "pattern_frequency": pattern.frequency,
                "affected_metrics": pattern.affectedMetrics.joined(separator: ",")
            ],
            relatedData: pattern.affectedMetrics
        )
    }

    private func generatePatternTitle(_ pattern: HealthPattern) -> String {
        switch pattern.patternType {
        case .sleep:
            return "Sleep Pattern Detected"
        case .activity:
            return "Activity Pattern Insight"
        case .circadian:
            return "Circadian Rhythm Pattern"
        case .weekly:
            return "Weekly Health Pattern"
        case .vital:
            return "Vital Signs Pattern"
        default:
            return "Health Pattern Detected"
        }
    }

    private func determinePriorityFromPattern(_ pattern: HealthPattern) -> InsightPriority {
        if pattern.strength >= 0.8 {
            return .high
        } else if pattern.strength >= 0.6 {
            return .medium
        } else {
            return .low
        }
    }

    private func categoryFromPatternType(_ patternType: PatternType) -> InsightCategory {
        switch patternType {
        case .circadian, .weekly:
            return .trend
        case .activity, .sleep:
            return .trend
        default:
            return .trend
        }
    }

    // MARK: - Data Extraction Methods

    private func extractSleepTimeSeries(_ data: ProcessedHealthData) -> [TimeSeriesPoint]? {
        return data.timeSeriesData["sleep_duration"]
    }

    private func extractActivityTimeSeries(_ data: ProcessedHealthData) -> [TimeSeriesPoint]? {
        return data.timeSeriesData["daily_steps"]
    }

    private func filterDataForRecentDays(_ data: ProcessedHealthData, days: Int) -> ProcessedHealthData {
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

    // MARK: - Statistical Helper Methods

    private func calculateVariance(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        return squaredDifferences.reduce(0, +) / Double(values.count)
    }

    private func calculateTrend(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let n = Double(values.count)
        let sumX = (1...values.count).map { Double($0) }.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(1...values.count, values).map { Double($0) * $1 }.reduce(0, +)
        let sumXSquared = (1...values.count).map { Double($0 * $0) }.reduce(0, +)

        let slope = (n * sumXY - sumX * sumY) / (n * sumXSquared - sumX * sumX)
        return slope
    }

    private func filterWeekdays(_ data: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        return data.filter { point in
            let weekday = Calendar.current.component(.weekday, from: point.timestamp)
            return weekday >= 2 && weekday <= 6 // Monday to Friday
        }
    }

    private func filterWeekends(_ data: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        return data.filter { point in
            let weekday = Calendar.current.component(.weekday, from: point.timestamp)
            return weekday == 1 || weekday == 7 // Sunday or Saturday
        }
    }

    private func isMorning(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 6 && hour < 12
    }

    private func isEvening(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 18 && hour < 22
    }

    private func calculateSimulatedSleepEfficiency(duration: Double) -> Double {
        // Simulate sleep efficiency based on duration
        // This is a simplified model for demonstration
        let optimalDuration = 8.0 // 8 hours
        let efficiencyPenalty = abs(duration - optimalDuration) * 0.05
        return max(0.6, 0.95 - efficiencyPenalty)
    }

    private func determineFrequency(_ variance: Double) -> String {
        if variance < 0.5 {
            return "very consistent"
        } else if variance < 1.5 {
            return "moderately consistent"
        } else {
            return "highly variable"
        }
    }

    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let amPm = hour < 12 ? "AM" : "PM"
        return minute > 0 ? "\(hour12):\(String(format: "%02d", minute)) \(amPm)" : "\(hour12) \(amPm)"
    }

    private func formatHour(_ hour: Int) -> String {
        let hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let amPm = hour < 12 ? "AM" : "PM"
        return "\(hour12) \(amPm)"
    }

    private func dayName(for dayNumber: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayNumber - 1]
    }
}

// MARK: - Error Types

enum PatternRecognitionError: LocalizedError {
    case analysisFailure(String)
    case insufficientData
    case processingError(String)

    var errorDescription: String? {
        switch self {
        case .analysisFailure(let message):
            return "Pattern analysis failed: \(message)"
        case .insufficientData:
            return "Insufficient data for pattern recognition"
        case .processingError(let message):
            return "Processing error: \(message)"
        }
    }
}