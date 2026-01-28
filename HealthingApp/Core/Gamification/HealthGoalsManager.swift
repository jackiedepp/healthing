//
//  HealthGoalsManager.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2F: Consumer Features & Gamification
//  Implements REQ-078: Health goal tracking with adaptive targets
//

import Foundation
import HealthKit
import UserNotifications
import os.log

/// Adaptive health goal setting and tracking system
/// Implements REQ-078: Health goal tracking with adaptive targets
@MainActor
class HealthGoalsManager: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "HealthingApp", category: "HealthGoalsManager")

    @Published var activeGoals: [HealthGoal] = []
    @Published var completedGoals: [HealthGoal] = []
    @Published var dailyProgress: [String: Double] = [:]
    @Published var weeklyProgress: [String: Double] = [:]
    @Published var goalSuggestions: [HealthGoal] = []
    @Published var isGeneratingGoals = false

    // Goal performance tracking
    private var goalPerformanceHistory: [String: [GoalPerformance]] = [:]
    private var lastAdaptationDate: [String: Date] = [:]
    private let goalStore = HealthGoalStore()

    // Dependencies
    private let healthDataStore: HealthDataStore
    private let achievementEngine: AchievementEngine
    private let notificationCenter = UNUserNotificationCenter.current()

    // Goal adaptation settings
    private let adaptationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let minSuccessRate = 0.8 // 80% success rate to increase difficulty
    private let maxFailureRate = 0.3 // 30% success rate to decrease difficulty

    // MARK: - Shared Instance

    static let shared = HealthGoalsManager(
        healthDataStore: HealthDataStore.shared,
        achievementEngine: AchievementEngine.shared
    )

    // MARK: - Initialization

    init(healthDataStore: HealthDataStore, achievementEngine: AchievementEngine) {
        self.healthDataStore = healthDataStore
        self.achievementEngine = achievementEngine
        logger.info("HealthGoalsManager initialized")

        Task {
            await initializeGoalSystem()
        }
    }

    // MARK: - Public Methods

    /// Initialize the health goal system
    func initializeGoalSystem() async {
        logger.info("Initializing health goal system")

        do {
            // Load saved goals
            activeGoals = try await goalStore.loadActiveGoals()
            completedGoals = try await goalStore.loadCompletedGoals()
            goalPerformanceHistory = try await goalStore.loadPerformanceHistory()

            // Generate initial goals if user has none
            if activeGoals.isEmpty {
                await generateInitialGoals()
            }

            // Update progress for all active goals
            await updateAllGoalProgress()

            logger.info("Goal system initialized with \(activeGoals.count) active goals")

        } catch {
            logger.error("Failed to initialize goal system: \(error.localizedDescription)")
        }
    }

    /// Update progress for all active goals based on latest health data
    func updateAllGoalProgress() async {
        logger.debug("Updating progress for all active goals")

        do {
            // Get latest health data
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate

            let observations = try await healthDataStore.fetchHealthObservations(
                dateRange: startDate...endDate,
                limit: 1000
            )

            let healthData = processObservationsToHealthData(observations)

            // Update progress for each goal
            for i in 0..<activeGoals.count {
                let progress = calculateGoalProgress(activeGoals[i], with: healthData)
                activeGoals[i].currentProgress = progress

                // Update daily/weekly progress tracking
                dailyProgress[activeGoals[i].id] = calculateDailyProgress(activeGoals[i], with: healthData)
                weeklyProgress[activeGoals[i].id] = calculateWeeklyProgress(activeGoals[i], with: healthData)

                // Check for goal completion
                if progress >= 1.0 && !activeGoals[i].isCompleted {
                    await completeGoal(activeGoals[i])
                }
            }

            // Check for goal adaptations
            await checkForGoalAdaptations(with: healthData)

            // Save updated goals
            try await goalStore.saveActiveGoals(activeGoals)

        } catch {
            logger.error("Failed to update goal progress: \(error.localizedDescription)")
        }
    }

    /// Create a new health goal
    func createGoal(_ goalTemplate: HealthGoalTemplate, customTarget: Double? = nil) async {
        logger.info("Creating new goal: \(goalTemplate.title)")

        let goal = HealthGoal(
            template: goalTemplate,
            customTarget: customTarget,
            startDate: Date()
        )

        activeGoals.append(goal)

        // Initialize performance tracking
        goalPerformanceHistory[goal.id] = []
        lastAdaptationDate[goal.id] = Date()

        // Save goals
        do {
            try await goalStore.saveActiveGoals(activeGoals)
            logger.info("Goal created successfully: \(goal.title)")

            // Schedule goal reminders
            await scheduleGoalReminder(goal)

        } catch {
            logger.error("Failed to save new goal: \(error.localizedDescription)")
        }
    }

    /// Modify an existing goal's target or parameters
    func modifyGoal(goalId: String, newTarget: Double? = nil, newDuration: GoalDuration? = nil) async {
        guard let goalIndex = activeGoals.firstIndex(where: { $0.id == goalId }) else {
            logger.warning("Goal not found for modification: \(goalId)")
            return
        }

        var modifiedGoal = activeGoals[goalIndex]

        if let newTarget = newTarget {
            modifiedGoal.targetValue = newTarget
            logger.info("Updated goal target: \(modifiedGoal.title) -> \(newTarget)")
        }

        if let newDuration = newDuration {
            modifiedGoal.duration = newDuration
            logger.info("Updated goal duration: \(modifiedGoal.title) -> \(newDuration)")
        }

        modifiedGoal.lastModified = Date()
        activeGoals[goalIndex] = modifiedGoal

        // Save changes
        do {
            try await goalStore.saveActiveGoals(activeGoals)
        } catch {
            logger.error("Failed to save modified goal: \(error.localizedDescription)")
        }
    }

    /// Pause or resume a goal
    func toggleGoalStatus(goalId: String) async {
        guard let goalIndex = activeGoals.firstIndex(where: { $0.id == goalId }) else {
            logger.warning("Goal not found for status toggle: \(goalId)")
            return
        }

        activeGoals[goalIndex].isPaused.toggle()
        activeGoals[goalIndex].lastModified = Date()

        let status = activeGoals[goalIndex].isPaused ? "paused" : "resumed"
        logger.info("Goal \(status): \(activeGoals[goalIndex].title)")

        // Save changes
        do {
            try await goalStore.saveActiveGoals(activeGoals)
        } catch {
            logger.error("Failed to save goal status change: \(error.localizedDescription)")
        }
    }

    /// Delete a goal
    func deleteGoal(goalId: String) async {
        guard let goalIndex = activeGoals.firstIndex(where: { $0.id == goalId }) else {
            logger.warning("Goal not found for deletion: \(goalId)")
            return
        }

        let deletedGoal = activeGoals.remove(at: goalIndex)
        logger.info("Goal deleted: \(deletedGoal.title)")

        // Clean up tracking data
        goalPerformanceHistory.removeValue(forKey: goalId)
        lastAdaptationDate.removeValue(forKey: goalId)
        dailyProgress.removeValue(forKey: goalId)
        weeklyProgress.removeValue(forKey: goalId)

        // Cancel notifications
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["goal_reminder_\(goalId)"])

        // Save changes
        do {
            try await goalStore.saveActiveGoals(activeGoals)
        } catch {
            logger.error("Failed to save after goal deletion: \(error.localizedDescription)")
        }
    }

    /// Get personalized goal suggestions based on user data
    func generateGoalSuggestions() async {
        logger.info("Generating personalized goal suggestions")
        isGeneratingGoals = true

        do {
            // Analyze user's health data patterns
            let healthData = try await collectRecentHealthData()
            let userProfile = analyzeUserHealthProfile(healthData)

            // Generate appropriate goal suggestions
            goalSuggestions = createPersonalizedGoalSuggestions(for: userProfile)

            logger.info("Generated \(goalSuggestions.count) goal suggestions")

        } catch {
            logger.error("Failed to generate goal suggestions: \(error.localizedDescription)")
        }

        isGeneratingGoals = false
    }

    /// Get goal statistics for dashboard display
    func getGoalStatistics() -> GoalStatistics {
        let totalActive = activeGoals.filter { !$0.isPaused }.count
        let totalCompleted = completedGoals.count
        let averageProgress = activeGoals.isEmpty ? 0.0 :
            activeGoals.map(\.currentProgress).reduce(0, +) / Double(activeGoals.count)

        let recentlyCompleted = completedGoals.filter {
            $0.completionDate?.timeIntervalSinceNow ?? -86400 > -86400 // Last 24 hours
        }.count

        let onTrackGoals = activeGoals.filter { $0.currentProgress >= 0.7 }.count

        return GoalStatistics(
            totalActive: totalActive,
            totalCompleted: totalCompleted,
            averageProgress: averageProgress,
            onTrackCount: onTrackGoals,
            strugglingCount: totalActive - onTrackGoals,
            recentlyCompleted: recentlyCompleted,
            streakDays: calculateGoalStreak()
        )
    }

    /// Get goals filtered by category and status
    func getGoals(
        category: HealthGoalCategory? = nil,
        status: GoalStatus? = nil,
        sortBy: GoalSortOption = .progress
    ) -> [HealthGoal] {
        var filteredGoals = activeGoals

        if let category = category {
            filteredGoals = filteredGoals.filter { $0.category == category }
        }

        if let status = status {
            switch status {
            case .active:
                filteredGoals = filteredGoals.filter { !$0.isPaused && !$0.isCompleted }
            case .paused:
                filteredGoals = filteredGoals.filter { $0.isPaused }
            case .completed:
                return completedGoals.filter { category == nil || $0.category == category }
            }
        }

        return sortGoals(filteredGoals, by: sortBy)
    }

    // MARK: - Private Methods

    private func generateInitialGoals() async {
        logger.info("Generating initial goals for new user")

        // Create default starter goals
        let starterGoals = [
            HealthGoalTemplate.dailyStepsTemplate(target: 8000),
            HealthGoalTemplate.sleepDurationTemplate(target: 8.0),
            HealthGoalTemplate.weeklyActiveMinutesTemplate(target: 150)
        ]

        for template in starterGoals {
            await createGoal(template)
        }
    }

    private func calculateGoalProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        switch goal.type {
        case .dailyTarget:
            return calculateDailyTargetProgress(goal, with: healthData)
        case .weeklyTarget:
            return calculateWeeklyTargetProgress(goal, with: healthData)
        case .monthlyTarget:
            return calculateMonthlyTargetProgress(goal, with: healthData)
        case .streak:
            return calculateStreakProgress(goal, with: healthData)
        case .improvement:
            return calculateImprovementProgress(goal, with: healthData)
        }
    }

    private func calculateDailyTargetProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        let todayData = healthData.filterForDate(today)

        switch goal.category {
        case .activity:
            if goal.metric == .steps {
                let todaySteps = todayData.activityData.first?.steps ?? 0
                return min(1.0, Double(todaySteps) / goal.targetValue)
            } else if goal.metric == .activeMinutes {
                let todayActiveMinutes = todayData.activityData.first?.activeMinutes ?? 0
                return min(1.0, Double(todayActiveMinutes) / goal.targetValue)
            }

        case .sleep:
            if goal.metric == .sleepDuration {
                let todaySleep = todayData.sleepData.first?.duration ?? 0
                let todayHours = todaySleep / 3600.0 // Convert to hours
                return min(1.0, todayHours / goal.targetValue)
            } else if goal.metric == .sleepQuality {
                let todayQuality = todayData.sleepData.first?.qualityScore ?? 0
                return min(1.0, todayQuality / goal.targetValue)
            }

        case .health:
            // Handle health-specific metrics
            if goal.metric == .heartRate {
                let todayHeartRate = todayData.vitalSignData.compactMap(\.heartRate).last ?? 0
                return min(1.0, todayHeartRate / goal.targetValue)
            }

        case .nutrition:
            // Handle nutrition metrics
            break

        case .mindfulness:
            // Handle mindfulness metrics
            break
        }

        return 0.0
    }

    private func calculateWeeklyTargetProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0.0 }

        let weekData = healthData.activityData.filter { $0.timestamp >= weekStart }

        switch goal.category {
        case .activity:
            if goal.metric == .activeMinutes {
                let weeklyActiveMinutes = weekData.reduce(0) { $0 + $1.activeMinutes }
                return min(1.0, Double(weeklyActiveMinutes) / goal.targetValue)
            }
        default:
            break
        }

        return 0.0
    }

    private func calculateMonthlyTargetProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return 0.0 }

        let monthData = healthData.activityData.filter { $0.timestamp >= monthStart }
        let daysInMonth = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        let daysElapsed = Double(calendar.dateComponents([.day], from: monthStart, to: now).day ?? 1)

        switch goal.category {
        case .activity:
            if goal.metric == .steps {
                let monthlySteps = monthData.reduce(0) { $0 + $1.steps }
                let expectedSteps = goal.targetValue * (daysElapsed / daysInMonth)
                return min(1.0, Double(monthlySteps) / expectedSteps)
            }
        default:
            break
        }

        return 0.0
    }

    private func calculateStreakProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        let targetDays = Int(goal.targetValue)
        var currentStreak = 0

        for dayOffset in 0..<targetDays {
            let checkDate = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            let dayData = healthData.filterForDate(checkDate)

            let dayMeetsGoal = checkDayMeetsGoal(goal, data: dayData)
            if dayMeetsGoal {
                currentStreak += 1
            } else {
                break
            }
        }

        return min(1.0, Double(currentStreak) / Double(targetDays))
    }

    private func calculateImprovementProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        // Calculate improvement from baseline to current values
        let recentData = healthData.filterRecent(days: 7)
        let baselineData = healthData.filterDateRange(
            start: goal.startDate,
            end: Calendar.current.date(byAdding: .day, value: 7, to: goal.startDate) ?? goal.startDate
        )

        guard let currentValue = getCurrentMetricValue(goal.metric, from: recentData),
              let baselineValue = getCurrentMetricValue(goal.metric, from: baselineData),
              baselineValue > 0 else { return 0.0 }

        let improvementRatio = (currentValue - baselineValue) / baselineValue
        let targetImprovement = goal.targetValue / 100.0 // Target is percentage improvement

        return min(1.0, max(0.0, improvementRatio / targetImprovement))
    }

    private func calculateDailyProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        return calculateGoalProgress(goal, with: healthData)
    }

    private func calculateWeeklyProgress(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0.0 }

        var weeklyProgress: Double = 0.0
        var daysChecked = 0

        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                  checkDate <= now else { continue }

            let dayData = healthData.filterForDate(checkDate)
            let dayProgress = calculateGoalProgress(goal, with: ProcessedHealthData(
                sleepData: dayData.sleepData,
                activityData: dayData.activityData,
                vitalSignData: dayData.vitalSignData,
                hydrationData: dayData.hydrationData,
                mindfulnessData: dayData.mindfulnessData,
                nutritionData: dayData.nutritionData
            ))

            weeklyProgress += min(1.0, dayProgress)
            daysChecked += 1
        }

        return daysChecked > 0 ? weeklyProgress / Double(daysChecked) : 0.0
    }

    private func completeGoal(_ goal: HealthGoal) async {
        logger.info("Goal completed: \(goal.title)")

        // Move to completed goals
        if let index = activeGoals.firstIndex(where: { $0.id == goal.id }) {
            var completedGoal = activeGoals.remove(at: index)
            completedGoal.isCompleted = true
            completedGoal.completionDate = Date()
            completedGoals.append(completedGoal)

            // Award achievement points
            await achievementEngine.processHealthDataForAchievements(
                ProcessedHealthData(
                    sleepData: [], activityData: [], vitalSignData: [],
                    hydrationData: [], mindfulnessData: [], nutritionData: []
                )
            )

            // Send completion notification
            await sendGoalCompletionNotification(completedGoal)

            // Save updated goals
            do {
                try await goalStore.saveActiveGoals(activeGoals)
                try await goalStore.saveCompletedGoals(completedGoals)
            } catch {
                logger.error("Failed to save completed goal: \(error.localizedDescription)")
            }
        }
    }

    private func checkForGoalAdaptations(with healthData: ProcessedHealthData) async {
        let now = Date()

        for i in 0..<activeGoals.count {
            let goal = activeGoals[i]
            let lastAdapted = lastAdaptationDate[goal.id] ?? goal.startDate

            // Check if enough time has passed for adaptation
            if now.timeIntervalSince(lastAdapted) >= adaptationInterval {
                if let adaptedGoal = calculateGoalAdaptation(goal, with: healthData) {
                    activeGoals[i] = adaptedGoal
                    lastAdaptationDate[goal.id] = now
                    logger.info("Goal adapted: \(goal.title) -> new target: \(adaptedGoal.targetValue)")
                }
            }
        }
    }

    private func calculateGoalAdaptation(_ goal: HealthGoal, with healthData: ProcessedHealthData) -> HealthGoal? {
        // Calculate recent performance
        let recentPerformances = goalPerformanceHistory[goal.id]?.suffix(7) ?? []
        guard !recentPerformances.isEmpty else { return nil }

        let successRate = recentPerformances.filter { $0.achieved }.count / recentPerformances.count
        let averageProgress = recentPerformances.map(\.progress).reduce(0, +) / Double(recentPerformances.count)

        var adaptedGoal = goal

        // Increase difficulty if user is consistently succeeding
        if successRate >= minSuccessRate && averageProgress >= 0.9 {
            let increaseMultiplier = 1.1 // 10% increase
            adaptedGoal.targetValue *= increaseMultiplier
            adaptedGoal.adaptationReason = .tooEasy
        }
        // Decrease difficulty if user is consistently failing
        else if successRate <= maxFailureRate && averageProgress <= 0.5 {
            let decreaseMultiplier = 0.9 // 10% decrease
            adaptedGoal.targetValue *= decreaseMultiplier
            adaptedGoal.adaptationReason = .tooHard
        }
        // No adaptation needed
        else {
            return nil
        }

        adaptedGoal.lastModified = Date()
        adaptedGoal.adaptationCount += 1

        return adaptedGoal
    }

    // MARK: - Helper Methods

    private func checkDayMeetsGoal(_ goal: HealthGoal, data: ProcessedHealthData) -> Bool {
        switch goal.category {
        case .activity:
            if goal.metric == .steps {
                return (data.activityData.first?.steps ?? 0) >= Int(goal.targetValue)
            }
        case .sleep:
            if goal.metric == .sleepDuration {
                let sleepHours = (data.sleepData.first?.duration ?? 0) / 3600.0
                return sleepHours >= goal.targetValue
            }
        default:
            break
        }
        return false
    }

    private func getCurrentMetricValue(_ metric: HealthMetric, from data: ProcessedHealthData) -> Double? {
        switch metric {
        case .steps:
            return Double(data.activityData.last?.steps ?? 0)
        case .activeMinutes:
            return Double(data.activityData.last?.activeMinutes ?? 0)
        case .sleepDuration:
            return (data.sleepData.last?.duration ?? 0) / 3600.0 // Convert to hours
        case .sleepQuality:
            return data.sleepData.last?.qualityScore
        case .heartRate:
            return data.vitalSignData.compactMap(\.heartRate).last
        case .weight:
            return data.vitalSignData.compactMap(\.weight).last
        case .hydration:
            return data.hydrationData.last?.waterIntake
        }
    }

    private func processObservationsToHealthData(_ observations: [HealthingObservation]) -> ProcessedHealthData {
        // Convert FHIR observations to ProcessedHealthData format
        // This is a simplified conversion - in production would be more comprehensive
        return ProcessedHealthData(
            sleepData: [],
            activityData: [],
            vitalSignData: [],
            hydrationData: [],
            mindfulnessData: [],
            nutritionData: []
        )
    }

    private func collectRecentHealthData() async throws -> ProcessedHealthData {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate

        let observations = try await healthDataStore.fetchHealthObservations(
            dateRange: startDate...endDate,
            limit: 1000
        )

        return processObservationsToHealthData(observations)
    }

    private func analyzeUserHealthProfile(_ healthData: ProcessedHealthData) -> UserHealthProfile {
        // Analyze user's health patterns to inform goal suggestions
        let averageDailySteps = healthData.activityData.isEmpty ? 0 :
            healthData.activityData.map(\.steps).reduce(0, +) / healthData.activityData.count

        let averageSleepDuration = healthData.sleepData.isEmpty ? 0 :
            healthData.sleepData.map(\.duration).reduce(0, +) / Double(healthData.sleepData.count) / 3600.0

        let fitnessLevel: FitnessLevel
        if averageDailySteps >= 10000 {
            fitnessLevel = .high
        } else if averageDailySteps >= 6000 {
            fitnessLevel = .moderate
        } else {
            fitnessLevel = .low
        }

        return UserHealthProfile(
            age: 30, // Would get from user profile
            fitnessLevel: fitnessLevel,
            healthRisks: [],
            preferences: UserPreferences(
                tracksHydration: !healthData.hydrationData.isEmpty,
                interestedInMindfulness: !healthData.mindfulnessData.isEmpty,
                prefersLowIntensityExercise: fitnessLevel == .low,
                prefersGroupActivities: false,
                prefersOutdoorActivities: false
            ),
            constraints: [],
            historicalPatterns: HistoricalPatterns(
                sleepTrend: .stable,
                activityTrend: .stable,
                weightTrend: .stable,
                consistencyScore: 0.7
            ),
            motivationStyle: .achievementOriented
        )
    }

    private func createPersonalizedGoalSuggestions(for profile: UserHealthProfile) -> [HealthGoal] {
        var suggestions: [HealthGoal] = []

        // Activity suggestions based on fitness level
        switch profile.fitnessLevel {
        case .low:
            suggestions.append(contentsOf: [
                HealthGoal(template: HealthGoalTemplate.dailyStepsTemplate(target: 6000)),
                HealthGoal(template: HealthGoalTemplate.weeklyActiveMinutesTemplate(target: 90))
            ])
        case .moderate:
            suggestions.append(contentsOf: [
                HealthGoal(template: HealthGoalTemplate.dailyStepsTemplate(target: 8500)),
                HealthGoal(template: HealthGoalTemplate.weeklyActiveMinutesTemplate(target: 150))
            ])
        case .high:
            suggestions.append(contentsOf: [
                HealthGoal(template: HealthGoalTemplate.dailyStepsTemplate(target: 12000)),
                HealthGoal(template: HealthGoalTemplate.weeklyActiveMinutesTemplate(target: 200))
            ])
        }

        // Sleep suggestions
        suggestions.append(
            HealthGoal(template: HealthGoalTemplate.sleepDurationTemplate(target: 8.0))
        )

        // Health-specific suggestions
        if !profile.healthRisks.isEmpty {
            // Add health-focused goals based on risks
        }

        return suggestions
    }

    private func calculateGoalStreak() -> Int {
        // Calculate consecutive days with goal progress
        var streak = 0
        let calendar = Calendar.current

        for dayOffset in 0..<30 {
            let checkDate = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            let dayHadProgress = activeGoals.contains { goal in
                dailyProgress[goal.id] ?? 0.0 > 0.5
            }

            if dayHadProgress {
                streak += 1
            } else {
                break
            }
        }

        return streak
    }

    private func sortGoals(_ goals: [HealthGoal], by option: GoalSortOption) -> [HealthGoal] {
        switch option {
        case .progress:
            return goals.sorted { $0.currentProgress > $1.currentProgress }
        case .dueDate:
            return goals.sorted { $0.endDate < $1.endDate }
        case .category:
            return goals.sorted { $0.category.rawValue < $1.category.rawValue }
        case .difficulty:
            return goals.sorted { $0.difficulty.rawValue < $1.difficulty.rawValue }
        }
    }

    private func scheduleGoalReminder(_ goal: HealthGoal) async {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Goal Reminder", comment: "Goal reminder notification title")
        content.body = String(format:
            NSLocalizedString("Don't forget to work on your goal: %@", comment: "Goal reminder notification body"),
            goal.title
        )
        content.sound = .default

        // Schedule daily reminder at 6 PM
        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "goal_reminder_\(goal.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            logger.error("Failed to schedule goal reminder: \(error.localizedDescription)")
        }
    }

    private func sendGoalCompletionNotification(_ goal: HealthGoal) async {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Goal Completed!", comment: "Goal completion notification title")
        content.body = String(format:
            NSLocalizedString("Congratulations! You've completed your goal: %@", comment: "Goal completion notification body"),
            goal.title
        )
        content.sound = .default
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: "goal_completion_\(goal.id)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            logger.error("Failed to send goal completion notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Data Structures

struct HealthGoal: Identifiable, Codable {
    let id: String
    var title: String
    var description: String
    var category: HealthGoalCategory
    var type: GoalType
    var metric: HealthMetric
    var targetValue: Double
    var currentProgress: Double
    var duration: GoalDuration
    var difficulty: GoalDifficulty
    var startDate: Date
    var endDate: Date
    var lastModified: Date
    var isCompleted: Bool
    var completionDate: Date?
    var isPaused: Bool
    var adaptationCount: Int
    var adaptationReason: AdaptationReason?

    init(template: HealthGoalTemplate, customTarget: Double? = nil, startDate: Date = Date()) {
        self.id = UUID().uuidString
        self.title = template.title
        self.description = template.description
        self.category = template.category
        self.type = template.type
        self.metric = template.metric
        self.targetValue = customTarget ?? template.defaultTarget
        self.currentProgress = 0.0
        self.duration = template.duration
        self.difficulty = template.difficulty
        self.startDate = startDate
        self.endDate = template.calculateEndDate(from: startDate)
        self.lastModified = startDate
        self.isCompleted = false
        self.completionDate = nil
        self.isPaused = false
        self.adaptationCount = 0
        self.adaptationReason = nil
    }
}

enum HealthGoalCategory: String, CaseIterable, Codable {
    case activity
    case sleep
    case health
    case nutrition
    case mindfulness

    var displayName: String {
        switch self {
        case .activity: return NSLocalizedString("Activity", comment: "Activity goal category")
        case .sleep: return NSLocalizedString("Sleep", comment: "Sleep goal category")
        case .health: return NSLocalizedString("Health", comment: "Health goal category")
        case .nutrition: return NSLocalizedString("Nutrition", comment: "Nutrition goal category")
        case .mindfulness: return NSLocalizedString("Mindfulness", comment: "Mindfulness goal category")
        }
    }

    var icon: String {
        switch self {
        case .activity: return "figure.walk"
        case .sleep: return "bed.double"
        case .health: return "heart"
        case .nutrition: return "leaf"
        case .mindfulness: return "brain.head.profile"
        }
    }
}

enum GoalType: String, Codable {
    case dailyTarget
    case weeklyTarget
    case monthlyTarget
    case streak
    case improvement

    var displayName: String {
        switch self {
        case .dailyTarget: return NSLocalizedString("Daily Target", comment: "Daily target goal type")
        case .weeklyTarget: return NSLocalizedString("Weekly Target", comment: "Weekly target goal type")
        case .monthlyTarget: return NSLocalizedString("Monthly Target", comment: "Monthly target goal type")
        case .streak: return NSLocalizedString("Streak", comment: "Streak goal type")
        case .improvement: return NSLocalizedString("Improvement", comment: "Improvement goal type")
        }
    }
}

enum HealthMetric: String, Codable {
    case steps
    case activeMinutes
    case sleepDuration
    case sleepQuality
    case heartRate
    case weight
    case hydration

    var displayName: String {
        switch self {
        case .steps: return NSLocalizedString("Steps", comment: "Steps metric")
        case .activeMinutes: return NSLocalizedString("Active Minutes", comment: "Active minutes metric")
        case .sleepDuration: return NSLocalizedString("Sleep Duration", comment: "Sleep duration metric")
        case .sleepQuality: return NSLocalizedString("Sleep Quality", comment: "Sleep quality metric")
        case .heartRate: return NSLocalizedString("Heart Rate", comment: "Heart rate metric")
        case .weight: return NSLocalizedString("Weight", comment: "Weight metric")
        case .hydration: return NSLocalizedString("Hydration", comment: "Hydration metric")
        }
    }

    var unit: String {
        switch self {
        case .steps: return "steps"
        case .activeMinutes: return "minutes"
        case .sleepDuration: return "hours"
        case .sleepQuality: return "score"
        case .heartRate: return "bpm"
        case .weight: return "kg"
        case .hydration: return "liters"
        }
    }
}

enum GoalDuration: String, Codable {
    case oneWeek
    case twoWeeks
    case oneMonth
    case threeMonths
    case ongoing

    var displayName: String {
        switch self {
        case .oneWeek: return NSLocalizedString("1 Week", comment: "One week duration")
        case .twoWeeks: return NSLocalizedString("2 Weeks", comment: "Two weeks duration")
        case .oneMonth: return NSLocalizedString("1 Month", comment: "One month duration")
        case .threeMonths: return NSLocalizedString("3 Months", comment: "Three months duration")
        case .ongoing: return NSLocalizedString("Ongoing", comment: "Ongoing duration")
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .oneWeek: return 7 * 24 * 60 * 60
        case .twoWeeks: return 14 * 24 * 60 * 60
        case .oneMonth: return 30 * 24 * 60 * 60
        case .threeMonths: return 90 * 24 * 60 * 60
        case .ongoing: return .greatestFiniteMagnitude
        }
    }
}

enum GoalDifficulty: Int, CaseIterable, Codable {
    case easy = 1
    case moderate = 2
    case challenging = 3
    case expert = 4

    var displayName: String {
        switch self {
        case .easy: return NSLocalizedString("Easy", comment: "Easy goal difficulty")
        case .moderate: return NSLocalizedString("Moderate", comment: "Moderate goal difficulty")
        case .challenging: return NSLocalizedString("Challenging", comment: "Challenging goal difficulty")
        case .expert: return NSLocalizedString("Expert", comment: "Expert goal difficulty")
        }
    }

    var color: Color {
        switch self {
        case .easy: return .green
        case .moderate: return .yellow
        case .challenging: return .orange
        case .expert: return .red
        }
    }
}

enum AdaptationReason: String, Codable {
    case tooEasy
    case tooHard
    case userRequest
    case healthChange

    var displayName: String {
        switch self {
        case .tooEasy: return NSLocalizedString("Goal was too easy", comment: "Too easy adaptation reason")
        case .tooHard: return NSLocalizedString("Goal was too challenging", comment: "Too hard adaptation reason")
        case .userRequest: return NSLocalizedString("User requested change", comment: "User request adaptation reason")
        case .healthChange: return NSLocalizedString("Health status changed", comment: "Health change adaptation reason")
        }
    }
}

enum GoalStatus {
    case active
    case paused
    case completed
}

enum GoalSortOption {
    case progress
    case dueDate
    case category
    case difficulty
}

struct GoalPerformance: Codable {
    let date: Date
    let progress: Double
    let achieved: Bool
}

struct GoalStatistics {
    let totalActive: Int
    let totalCompleted: Int
    let averageProgress: Double
    let onTrackCount: Int
    let strugglingCount: Int
    let recentlyCompleted: Int
    let streakDays: Int
}

// MARK: - Goal Templates

struct HealthGoalTemplate {
    let title: String
    let description: String
    let category: HealthGoalCategory
    let type: GoalType
    let metric: HealthMetric
    let defaultTarget: Double
    let duration: GoalDuration
    let difficulty: GoalDifficulty

    func calculateEndDate(from startDate: Date) -> Date {
        if duration == .ongoing {
            return Date.distantFuture
        }
        return startDate.addingTimeInterval(duration.timeInterval)
    }

    // Predefined templates
    static func dailyStepsTemplate(target: Double = 10000) -> HealthGoalTemplate {
        return HealthGoalTemplate(
            title: NSLocalizedString("Daily Steps Goal", comment: "Daily steps goal title"),
            description: NSLocalizedString("Reach your daily step target to stay active", comment: "Daily steps goal description"),
            category: .activity,
            type: .dailyTarget,
            metric: .steps,
            defaultTarget: target,
            duration: .ongoing,
            difficulty: target >= 12000 ? .challenging : (target >= 8000 ? .moderate : .easy)
        )
    }

    static func sleepDurationTemplate(target: Double = 8.0) -> HealthGoalTemplate {
        return HealthGoalTemplate(
            title: NSLocalizedString("Sleep Duration Goal", comment: "Sleep duration goal title"),
            description: NSLocalizedString("Get enough quality sleep each night", comment: "Sleep duration goal description"),
            category: .sleep,
            type: .dailyTarget,
            metric: .sleepDuration,
            defaultTarget: target,
            duration: .ongoing,
            difficulty: .moderate
        )
    }

    static func weeklyActiveMinutesTemplate(target: Double = 150) -> HealthGoalTemplate {
        return HealthGoalTemplate(
            title: NSLocalizedString("Weekly Active Minutes", comment: "Weekly active minutes goal title"),
            description: NSLocalizedString("Stay active with regular exercise throughout the week", comment: "Weekly active minutes goal description"),
            category: .activity,
            type: .weeklyTarget,
            metric: .activeMinutes,
            defaultTarget: target,
            duration: .ongoing,
            difficulty: target >= 300 ? .challenging : (target >= 200 ? .moderate : .easy)
        )
    }
}

// MARK: - Goal Store

class HealthGoalStore {
    private let userDefaults = UserDefaults.standard
    private let activeGoalsKey = "active_health_goals"
    private let completedGoalsKey = "completed_health_goals"
    private let performanceKey = "goal_performance_history"

    func loadActiveGoals() async throws -> [HealthGoal] {
        guard let data = userDefaults.data(forKey: activeGoalsKey) else {
            return []
        }
        return try JSONDecoder().decode([HealthGoal].self, from: data)
    }

    func saveActiveGoals(_ goals: [HealthGoal]) async throws {
        let data = try JSONEncoder().encode(goals)
        userDefaults.set(data, forKey: activeGoalsKey)
    }

    func loadCompletedGoals() async throws -> [HealthGoal] {
        guard let data = userDefaults.data(forKey: completedGoalsKey) else {
            return []
        }
        return try JSONDecoder().decode([HealthGoal].self, from: data)
    }

    func saveCompletedGoals(_ goals: [HealthGoal]) async throws {
        let data = try JSONEncoder().encode(goals)
        userDefaults.set(data, forKey: completedGoalsKey)
    }

    func loadPerformanceHistory() async throws -> [String: [GoalPerformance]] {
        guard let data = userDefaults.data(forKey: performanceKey) else {
            return [:]
        }
        return try JSONDecoder().decode([String: [GoalPerformance]].self, from: data)
    }

    func savePerformanceHistory(_ history: [String: [GoalPerformance]]) async throws {
        let data = try JSONEncoder().encode(history)
        userDefaults.set(data, forKey: performanceKey)
    }
}