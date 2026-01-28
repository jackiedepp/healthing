//
//  HealthSummaryGenerator.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import Combine
import OSLog
import HealthKit

/// Health summary generation service for doctor visits and comprehensive reporting
/// Implements REQ-080: Pre-visit health summaries for doctor appointments
/// Supports REQ-068: Data export with comprehensive health summaries
/// Implements REQ-050: Accessibility features for health reports
@MainActor
final class HealthSummaryGenerator: ObservableObject {

    // MARK: - Singleton
    static let shared = HealthSummaryGenerator()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "HealthSummaryGenerator")
    private let healthDataStore = HealthDataStore.shared
    private var cancellables = Set<AnyCancellable>()

    @Published var generatedSummaries: [HealthSummary] = []
    @Published var isGenerating = false

    // MARK: - Initialization
    private init() {
        setupNotificationObservers()
    }

    // MARK: - Notification Observer Setup

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .preVisitSummaryRequested)
            .sink { [weak self] notification in
                Task { await self?.handlePreVisitSummaryRequest(notification) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Summary Generation

    /// Generate comprehensive health summary for doctor visit
    func generatePreVisitSummary(
        appointmentId: String,
        appointmentType: AppointmentType,
        timeFrame: SummaryTimeFrame = .lastThreeMonths
    ) async -> HealthSummary? {
        logger.info("Generating pre-visit summary for appointment: \(appointmentId)")

        await MainActor.run {
            isGenerating = true
        }

        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }

        do {
            // Get health data for the specified time frame
            let healthData = await getHealthDataForTimeFrame(timeFrame)

            // Generate summary based on appointment type
            let summary = await generateSummaryContent(
                healthData: healthData,
                appointmentType: appointmentType,
                timeFrame: timeFrame
            )

            let healthSummary = HealthSummary(
                id: UUID().uuidString,
                appointmentId: appointmentId,
                type: .preVisit,
                appointmentType: appointmentType,
                timeFrame: timeFrame,
                generatedDate: Date(),
                summary: summary,
                sections: createSummarySections(from: healthData, appointmentType: appointmentType),
                recommendations: generateRecommendations(from: healthData, appointmentType: appointmentType),
                keyMetrics: extractKeyMetrics(from: healthData, appointmentType: appointmentType)
            )

            await MainActor.run {
                generatedSummaries.append(healthSummary)
            }

            logger.info("Generated pre-visit summary: \(healthSummary.id)")
            return healthSummary

        } catch {
            logger.error("Failed to generate pre-visit summary: \(error.localizedDescription)")
            return nil
        }
    }

    /// Generate comprehensive health export summary
    func generateExportSummary(
        includeTimeFrame: SummaryTimeFrame = .allTime,
        includeMedications: Bool = true,
        includeDocuments: Bool = true,
        includeAchievements: Bool = true
    ) async -> HealthSummary? {
        logger.info("Generating export summary")

        await MainActor.run {
            isGenerating = true
        }

        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }

        do {
            let healthData = await getHealthDataForTimeFrame(includeTimeFrame)

            let summary = HealthSummary(
                id: UUID().uuidString,
                appointmentId: nil,
                type: .export,
                appointmentType: .general,
                timeFrame: includeTimeFrame,
                generatedDate: Date(),
                summary: generateExportSummaryContent(healthData),
                sections: createExportSections(
                    from: healthData,
                    includeMedications: includeMedications,
                    includeDocuments: includeDocuments,
                    includeAchievements: includeAchievements
                ),
                recommendations: [],
                keyMetrics: extractAllKeyMetrics(from: healthData)
            )

            await MainActor.run {
                generatedSummaries.append(summary)
            }

            logger.info("Generated export summary: \(summary.id)")
            return summary

        } catch {
            logger.error("Failed to generate export summary: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Data Retrieval

    private func getHealthDataForTimeFrame(_ timeFrame: SummaryTimeFrame) async -> ProcessedHealthData {
        let endDate = Date()
        let startDate = getStartDate(for: timeFrame, from: endDate)

        return await healthDataStore.getHealthData(from: startDate, to: endDate)
    }

    private func getStartDate(for timeFrame: SummaryTimeFrame, from endDate: Date) -> Date {
        let calendar = Calendar.current

        switch timeFrame {
        case .lastWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: endDate) ?? endDate
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .lastThreeMonths:
            return calendar.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .lastSixMonths:
            return calendar.date(byAdding: .month, value: -6, to: endDate) ?? endDate
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .allTime:
            return calendar.date(byAdding: .year, value: -10, to: endDate) ?? endDate // Reasonable max
        }
    }

    // MARK: - Summary Content Generation

    private func generateSummaryContent(
        healthData: ProcessedHealthData,
        appointmentType: AppointmentType,
        timeFrame: SummaryTimeFrame
    ) async -> String {
        var summaryLines: [String] = []

        // Add overview
        summaryLines.append(generateOverview(healthData: healthData, timeFrame: timeFrame))

        // Add appointment-specific focus areas
        summaryLines.append(contentsOf: generateAppointmentSpecificContent(
            healthData: healthData,
            appointmentType: appointmentType
        ))

        // Add key concerns or highlights
        summaryLines.append(contentsOf: generateKeyConcerns(healthData: healthData))

        return summaryLines.joined(separator: "\n\n")
    }

    private func generateOverview(healthData: ProcessedHealthData, timeFrame: SummaryTimeFrame) -> String {
        let timeFrameDesc = getTimeFrameDescription(timeFrame)

        var overview = String.localizedStringWithFormat(
            NSLocalizedString("health.summary.overview", comment: "Health Overview (%@)"),
            timeFrameDesc
        )

        // Add key statistics
        if let latestVitals = healthData.vitals.last {
            overview += "\n\n" + NSLocalizedString("health.summary.vitals.latest", comment: "Latest Vital Signs:")

            if let heartRate = latestVitals.heartRate {
                overview += "\n• " + String.localizedStringWithFormat(
                    NSLocalizedString("health.summary.vitals.heart_rate", comment: "Heart Rate: %d BPM"),
                    Int(heartRate)
                )
            }

            if let systolic = latestVitals.bloodPressureSystolic,
               let diastolic = latestVitals.bloodPressureDiastolic {
                overview += "\n• " + String.localizedStringWithFormat(
                    NSLocalizedString("health.summary.vitals.blood_pressure", comment: "Blood Pressure: %d/%d mmHg"),
                    Int(systolic),
                    Int(diastolic)
                )
            }

            if let weight = latestVitals.weight {
                overview += "\n• " + String.localizedStringWithFormat(
                    NSLocalizedString("health.summary.vitals.weight", comment: "Weight: %.1f kg"),
                    weight
                )
            }
        }

        // Add activity summary
        if let recentActivity = healthData.activityData.last {
            overview += "\n\n" + NSLocalizedString("health.summary.activity.recent", comment: "Recent Activity:")

            overview += "\n• " + String.localizedStringWithFormat(
                NSLocalizedString("health.summary.activity.steps", comment: "Steps: %d"),
                recentActivity.steps
            )

            overview += "\n• " + String.localizedStringWithFormat(
                NSLocalizedString("health.summary.activity.calories", comment: "Active Calories: %d"),
                Int(recentActivity.activeCalories)
            )

            if let exerciseMinutes = recentActivity.exerciseMinutes {
                overview += "\n• " + String.localizedStringWithFormat(
                    NSLocalizedString("health.summary.activity.exercise", comment: "Exercise Minutes: %d"),
                    Int(exerciseMinutes)
                )
            }
        }

        return overview
    }

    private func generateAppointmentSpecificContent(
        healthData: ProcessedHealthData,
        appointmentType: AppointmentType
    ) -> [String] {
        var content: [String] = []

        switch appointmentType {
        case .checkup, .general:
            content.append(generateGeneralHealthContent(healthData))

        case .specialist:
            content.append(generateSpecialistContent(healthData))

        case .dental:
            content.append(generateDentalContent(healthData))

        case .vision:
            content.append(generateVisionContent(healthData))

        case .therapy:
            content.append(generateTherapyContent(healthData))

        case .procedure:
            content.append(generateProcedureContent(healthData))

        case .followUp:
            content.append(generateFollowUpContent(healthData))

        case .emergency:
            content.append(generateEmergencyContent(healthData))
        }

        return content
    }

    private func generateGeneralHealthContent(_ healthData: ProcessedHealthData) -> String {
        var content = NSLocalizedString("health.summary.general.title", comment: "General Health Status")

        // Vital trends
        content += "\n\n" + generateVitalTrends(healthData.vitals)

        // Activity patterns
        content += "\n\n" + generateActivityPatterns(healthData.activityData)

        // Sleep quality
        if let sleepData = healthData.sleepData.last {
            content += "\n\n" + generateSleepSummary([sleepData])
        }

        return content
    }

    private func generateSpecialistContent(_ healthData: ProcessedHealthData) -> String {
        var content = NSLocalizedString("health.summary.specialist.title", comment: "Specialist Visit Information")

        // Focus on specific metrics that might be relevant to specialist
        content += "\n\n" + generateDetailedVitalAnalysis(healthData.vitals)

        // Recent symptoms or concerns (from medical records)
        content += "\n\n" + generateRecentSymptoms(healthData)

        return content
    }

    private func generateKeyConcerns(_ healthData: ProcessedHealthData) -> [String] {
        var concerns: [String] = []

        // Check for concerning vital signs
        if let concerningVitals = identifyConcerningVitals(healthData.vitals) {
            concerns.append(concerningVitals)
        }

        // Check for activity pattern changes
        if let activityConcerns = identifyActivityConcerns(healthData.activityData) {
            concerns.append(activityConcerns)
        }

        // Check for sleep issues
        if let sleepConcerns = identifySleepConcerns(healthData.sleepData) {
            concerns.append(sleepConcerns)
        }

        return concerns
    }

    // MARK: - Section Generation

    private func createSummarySections(
        from healthData: ProcessedHealthData,
        appointmentType: AppointmentType
    ) -> [HealthSummarySection] {
        var sections: [HealthSummarySection] = []

        // Vital Signs Section
        sections.append(createVitalSignsSection(healthData.vitals))

        // Activity Section
        sections.append(createActivitySection(healthData.activityData))

        // Sleep Section
        if !healthData.sleepData.isEmpty {
            sections.append(createSleepSection(healthData.sleepData))
        }

        // Medical History Section
        sections.append(createMedicalHistorySection(healthData))

        // Medications Section (if relevant)
        if appointmentType != .dental && appointmentType != .vision {
            sections.append(createMedicationsSection())
        }

        return sections
    }

    private func createExportSections(
        from healthData: ProcessedHealthData,
        includeMedications: Bool,
        includeDocuments: Bool,
        includeAchievements: Bool
    ) -> [HealthSummarySection] {
        var sections: [HealthSummarySection] = []

        // All standard sections
        sections.append(contentsOf: createSummarySections(from: healthData, appointmentType: .general))

        // Additional export-specific sections
        if includeMedications {
            sections.append(createDetailedMedicationsSection())
        }

        if includeDocuments {
            sections.append(createDocumentsSection())
        }

        if includeAchievements {
            sections.append(createAchievementsSection())
        }

        return sections
    }

    private func createVitalSignsSection(_ vitals: [VitalSigns]) -> HealthSummarySection {
        let content = generateVitalTrends(vitals)

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.vitals", comment: "Vital Signs"),
            content: content,
            type: .vitals,
            priority: .high
        )
    }

    private func createActivitySection(_ activityData: [ActivityData]) -> HealthSummarySection {
        let content = generateActivityPatterns(activityData)

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.activity", comment: "Physical Activity"),
            content: content,
            type: .activity,
            priority: .medium
        )
    }

    private func createSleepSection(_ sleepData: [SleepData]) -> HealthSummarySection {
        let content = generateSleepSummary(sleepData)

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.sleep", comment: "Sleep"),
            content: content,
            type: .sleep,
            priority: .medium
        )
    }

    private func createMedicalHistorySection(_ healthData: ProcessedHealthData) -> HealthSummarySection {
        // This would integrate with medical records from previous phases
        let content = NSLocalizedString("health.summary.medical.placeholder", comment: "Medical history integration pending medical records phase.")

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.medical_history", comment: "Medical History"),
            content: content,
            type: .medicalHistory,
            priority: .high
        )
    }

    private func createMedicationsSection() -> HealthSummarySection {
        let medicationService = MedicationRemindersService.shared
        let adherenceSummary = medicationService.getAdherenceSummary()

        var content = ""
        if adherenceSummary.isEmpty {
            content = NSLocalizedString("health.summary.medications.none", comment: "No medications currently tracked.")
        } else {
            content = NSLocalizedString("health.summary.medications.current", comment: "Current Medications:")

            for summary in adherenceSummary {
                content += "\n• \(summary.medication.name) (\(summary.medication.dosage))"
                content += " - " + String.localizedStringWithFormat(
                    NSLocalizedString("health.summary.medications.adherence", comment: "Adherence: %.0f%%"),
                    summary.adherenceRate
                )
            }
        }

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.medications", comment: "Medications"),
            content: content,
            type: .medications,
            priority: .high
        )
    }

    // MARK: - Content Generation Helpers

    private func generateVitalTrends(_ vitals: [VitalSigns]) -> String {
        guard !vitals.isEmpty else {
            return NSLocalizedString("health.summary.vitals.none", comment: "No vital signs data available.")
        }

        var content = ""

        // Heart rate trends
        let heartRates = vitals.compactMap { $0.heartRate }
        if !heartRates.isEmpty {
            let average = heartRates.reduce(0, +) / Double(heartRates.count)
            let latest = heartRates.last ?? 0

            content += String.localizedStringWithFormat(
                NSLocalizedString("health.summary.vitals.heart_rate_trend", comment: "Heart Rate: Latest %d BPM (Average: %d BPM)"),
                Int(latest),
                Int(average)
            )
        }

        // Blood pressure trends
        let systolic = vitals.compactMap { $0.bloodPressureSystolic }
        let diastolic = vitals.compactMap { $0.bloodPressureDiastolic }

        if !systolic.isEmpty && !diastolic.isEmpty {
            let avgSystolic = systolic.reduce(0, +) / Double(systolic.count)
            let avgDiastolic = diastolic.reduce(0, +) / Double(diastolic.count)

            if !content.isEmpty { content += "\n" }
            content += String.localizedStringWithFormat(
                NSLocalizedString("health.summary.vitals.bp_trend", comment: "Blood Pressure: Average %d/%d mmHg"),
                Int(avgSystolic),
                Int(avgDiastolic)
            )
        }

        return content
    }

    private func generateActivityPatterns(_ activityData: [ActivityData]) -> String {
        guard !activityData.isEmpty else {
            return NSLocalizedString("health.summary.activity.none", comment: "No activity data available.")
        }

        let totalSteps = activityData.map { $0.steps }.reduce(0, +)
        let averageSteps = totalSteps / activityData.count

        let totalCalories = activityData.map { $0.activeCalories }.reduce(0, +)
        let averageCalories = totalCalories / Double(activityData.count)

        var content = String.localizedStringWithFormat(
            NSLocalizedString("health.summary.activity.averages", comment: "Daily Averages: %d steps, %d active calories"),
            averageSteps,
            Int(averageCalories)
        )

        // Add trends
        if activityData.count >= 7 {
            let recentAverage = activityData.suffix(7).map { $0.steps }.reduce(0, +) / 7
            let olderAverage = activityData.prefix(max(1, activityData.count - 7)).map { $0.steps }.reduce(0, +) / max(1, activityData.count - 7)

            let trend = recentAverage > olderAverage ? "increasing" : "stable"
            content += "\n" + String.localizedStringWithFormat(
                NSLocalizedString("health.summary.activity.trend", comment: "Trend: %@"),
                NSLocalizedString("health.summary.activity.trend.\(trend)", comment: trend.capitalized)
            )
        }

        return content
    }

    private func generateSleepSummary(_ sleepData: [SleepData]) -> String {
        guard !sleepData.isEmpty else {
            return NSLocalizedString("health.summary.sleep.none", comment: "No sleep data available.")
        }

        let totalSleep = sleepData.map { $0.duration }.reduce(0, +)
        let averageSleep = totalSleep / Double(sleepData.count)

        let qualityScores = sleepData.compactMap { $0.qualityScore }
        let averageQuality = qualityScores.isEmpty ? 0 : qualityScores.reduce(0, +) / Double(qualityScores.count)

        var content = String.localizedStringWithFormat(
            NSLocalizedString("health.summary.sleep.average", comment: "Average Sleep: %.1f hours per night"),
            averageSleep
        )

        if averageQuality > 0 {
            content += "\n" + String.localizedStringWithFormat(
                NSLocalizedString("health.summary.sleep.quality", comment: "Average Sleep Quality: %.1f/10"),
                averageQuality
            )
        }

        return content
    }

    // MARK: - Analysis Helpers

    private func identifyConcerningVitals(_ vitals: [VitalSigns]) -> String? {
        guard let latest = vitals.last else { return nil }

        var concerns: [String] = []

        // Check heart rate
        if let heartRate = latest.heartRate {
            if heartRate > 100 {
                concerns.append(NSLocalizedString("health.concerns.high_heart_rate", comment: "Elevated heart rate"))
            } else if heartRate < 60 {
                concerns.append(NSLocalizedString("health.concerns.low_heart_rate", comment: "Low heart rate"))
            }
        }

        // Check blood pressure
        if let systolic = latest.bloodPressureSystolic {
            if systolic > 140 {
                concerns.append(NSLocalizedString("health.concerns.high_blood_pressure", comment: "Elevated blood pressure"))
            }
        }

        if concerns.isEmpty { return nil }

        return NSLocalizedString("health.concerns.vitals.title", comment: "Vital Signs to Discuss:") + "\n• " + concerns.joined(separator: "\n• ")
    }

    private func identifyActivityConcerns(_ activityData: [ActivityData]) -> String? {
        guard activityData.count >= 7 else { return nil }

        let recentWeek = activityData.suffix(7)
        let averageSteps = recentWeek.map { $0.steps }.reduce(0, +) / 7

        if averageSteps < 5000 {
            return NSLocalizedString("health.concerns.low_activity", comment: "Activity Level: Below recommended daily step count")
        }

        return nil
    }

    private func identifySleepConcerns(_ sleepData: [SleepData]) -> String? {
        guard sleepData.count >= 7 else { return nil }

        let recentWeek = sleepData.suffix(7)
        let averageSleep = recentWeek.map { $0.duration }.reduce(0, +) / 7

        if averageSleep < 6.0 {
            return NSLocalizedString("health.concerns.insufficient_sleep", comment: "Sleep: Consistently below recommended 7-9 hours")
        }

        return nil
    }

    // MARK: - Utility Methods

    private func getTimeFrameDescription(_ timeFrame: SummaryTimeFrame) -> String {
        switch timeFrame {
        case .lastWeek: return NSLocalizedString("time.frame.last_week", comment: "Last Week")
        case .lastMonth: return NSLocalizedString("time.frame.last_month", comment: "Last Month")
        case .lastThreeMonths: return NSLocalizedString("time.frame.last_three_months", comment: "Last 3 Months")
        case .lastSixMonths: return NSLocalizedString("time.frame.last_six_months", comment: "Last 6 Months")
        case .lastYear: return NSLocalizedString("time.frame.last_year", comment: "Last Year")
        case .allTime: return NSLocalizedString("time.frame.all_time", comment: "All Time")
        }
    }

    // MARK: - Notification Handler

    private func handlePreVisitSummaryRequest(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let appointmentId = userInfo["appointmentId"] as? String,
              let appointmentTypeString = userInfo["appointmentType"] as? String,
              let appointmentType = AppointmentType(rawValue: appointmentTypeString) else {
            return
        }

        let summary = await generatePreVisitSummary(
            appointmentId: appointmentId,
            appointmentType: appointmentType
        )

        if let summary = summary {
            // Send notification that summary is ready
            NotificationCenter.default.post(
                name: .preVisitSummaryGenerated,
                object: nil,
                userInfo: [
                    "summaryId": summary.id,
                    "appointmentId": appointmentId
                ]
            )
        }
    }

    // MARK: - Additional Content Generators (Stubs for different appointment types)

    private func generateDetailedVitalAnalysis(_ vitals: [VitalSigns]) -> String {
        return generateVitalTrends(vitals) + "\n\n" + NSLocalizedString("health.summary.detailed.vitals.note", comment: "Detailed vital analysis would include trend charts and anomaly detection.")
    }

    private func generateRecentSymptoms(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.symptoms.placeholder", comment: "Recent symptoms and medical records integration pending.")
    }

    private func generateDentalContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.dental.placeholder", comment: "Dental-specific health information.")
    }

    private func generateVisionContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.vision.placeholder", comment: "Vision-specific health information.")
    }

    private func generateTherapyContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.therapy.placeholder", comment: "Therapy-relevant health information including mental health indicators.")
    }

    private func generateProcedureContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.procedure.placeholder", comment: "Pre-procedure health status and preparation information.")
    }

    private func generateFollowUpContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.followup.placeholder", comment: "Follow-up visit information with progress tracking.")
    }

    private func generateEmergencyContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.emergency.placeholder", comment: "Emergency-relevant health information with recent critical indicators.")
    }

    private func createDetailedMedicationsSection() -> HealthSummarySection {
        return createMedicationsSection() // Enhanced version would include full medication history
    }

    private func createDocumentsSection() -> HealthSummarySection {
        let content = NSLocalizedString("health.summary.documents.placeholder", comment: "Medical documents and records summary.")

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.documents", comment: "Medical Documents"),
            content: content,
            type: .documents,
            priority: .medium
        )
    }

    private func createAchievementsSection() -> HealthSummarySection {
        let content = NSLocalizedString("health.summary.achievements.placeholder", comment: "Health achievements and milestones.")

        return HealthSummarySection(
            title: NSLocalizedString("health.summary.section.achievements", comment: "Health Achievements"),
            content: content,
            type: .achievements,
            priority: .low
        )
    }

    private func generateExportSummaryContent(_ healthData: ProcessedHealthData) -> String {
        return NSLocalizedString("health.summary.export.comprehensive", comment: "Comprehensive health data export generated for external use.")
    }

    private func generateRecommendations(from healthData: ProcessedHealthData, appointmentType: AppointmentType) -> [String] {
        // AI-powered recommendations would be integrated here
        return [NSLocalizedString("health.recommendations.placeholder", comment: "AI-powered health recommendations will be available after AI insights phase.")]
    }

    private func extractKeyMetrics(from healthData: ProcessedHealthData, appointmentType: AppointmentType) -> [HealthMetric] {
        // Key metrics extraction for specific appointment types
        return []
    }

    private func extractAllKeyMetrics(from healthData: ProcessedHealthData) -> [HealthMetric] {
        // Comprehensive metrics for export
        return []
    }
}

// MARK: - Supporting Models

/// Health summary data model
struct HealthSummary: Identifiable {
    let id: String
    let appointmentId: String?
    let type: SummaryType
    let appointmentType: AppointmentType
    let timeFrame: SummaryTimeFrame
    let generatedDate: Date
    let summary: String
    let sections: [HealthSummarySection]
    let recommendations: [String]
    let keyMetrics: [HealthMetric]
}

/// Health summary section
struct HealthSummarySection: Identifiable {
    let id = UUID().uuidString
    let title: String
    let content: String
    let type: SectionType
    let priority: SectionPriority
}

/// Summary types
enum SummaryType {
    case preVisit
    case export
    case periodic
}

/// Summary time frames
enum SummaryTimeFrame {
    case lastWeek
    case lastMonth
    case lastThreeMonths
    case lastSixMonths
    case lastYear
    case allTime
}

/// Section types
enum SectionType {
    case vitals
    case activity
    case sleep
    case medicalHistory
    case medications
    case documents
    case achievements
}

/// Section priority
enum SectionPriority {
    case high
    case medium
    case low
}

/// Health metric
struct HealthMetric {
    let name: String
    let value: String
    let unit: String?
    let trend: MetricTrend?
}

/// Metric trend
enum MetricTrend {
    case improving
    case stable
    case declining
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let preVisitSummaryGenerated = Notification.Name("preVisitSummaryGenerated")
}