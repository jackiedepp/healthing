//
//  AchievementEngine.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2F: Consumer Features & Gamification
//  Implements REQ-075: Gamification elements to encourage healthy behaviors
//  Implements REQ-076: Achievement badges and progress celebrations
//

import Foundation
import HealthKit
import UserNotifications
import os.log

/// Comprehensive achievement and badge system to encourage healthy behaviors
/// Implements REQ-075: Gamification elements to encourage healthy behaviors
/// Implements REQ-076: Achievement badges and progress celebrations
@MainActor
class AchievementEngine: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "HealthingApp", category: "AchievementEngine")

    @Published var unlockedAchievements: [Achievement] = []
    @Published var progressAchievements: [Achievement] = []
    @Published var availableAchievements: [Achievement] = []
    @Published var recentlyUnlocked: [Achievement] = []
    @Published var currentStreak: StreakData = StreakData()
    @Published var userLevel: UserLevel = UserLevel()
    @Published var totalPoints: Int = 0

    // Achievement tracking
    private var achievementProgress: [String: Double] = [:]
    private var lastProcessingDate: Date?
    private let achievementStore = AchievementStore()

    // Dependencies
    private let healthDataStore: HealthDataStore
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Shared Instance

    static let shared = AchievementEngine(healthDataStore: HealthDataStore.shared)

    // MARK: - Initialization

    init(healthDataStore: HealthDataStore) {
        self.healthDataStore = healthDataStore
        logger.info("AchievementEngine initialized")

        Task {
            await initializeAchievementSystem()
        }
    }

    // MARK: - Public Methods

    /// Initialize the achievement system and load user progress
    func initializeAchievementSystem() async {
        logger.info("Initializing achievement system")

        do {
            // Load saved achievements and progress
            unlockedAchievements = try await achievementStore.loadUnlockedAchievements()
            achievementProgress = try await achievementStore.loadProgress()
            totalPoints = unlockedAchievements.reduce(0) { $0 + $1.points }

            // Calculate user level based on total points
            userLevel = calculateUserLevel(from: totalPoints)

            // Initialize available achievements
            availableAchievements = createAvailableAchievements()

            // Update progress for all achievements
            await updateAchievementProgress()

            logger.info("Achievement system initialized with \(unlockedAchievements.count) unlocked achievements")

        } catch {
            logger.error("Failed to initialize achievement system: \(error.localizedDescription)")
        }
    }

    /// Process health data to check for new achievements
    func processHealthDataForAchievements(_ healthData: ProcessedHealthData) async {
        logger.debug("Processing health data for achievements")

        let newAchievements = await checkForNewAchievements(healthData)

        for achievement in newAchievements {
            await unlockAchievement(achievement)
        }

        // Update progress for all tracked achievements
        await updateAchievementProgress()

        // Update streaks
        await updateStreaks(with: healthData)

        // Save progress
        do {
            try await achievementStore.saveProgress(achievementProgress)
            try await achievementStore.saveUnlockedAchievements(unlockedAchievements)
        } catch {
            logger.error("Failed to save achievement progress: \(error.localizedDescription)")
        }
    }

    /// Unlock an achievement and trigger celebrations
    func unlockAchievement(_ achievement: Achievement) async {
        logger.info("Unlocking achievement: \(achievement.title)")

        // Add to unlocked achievements
        unlockedAchievements.append(achievement)
        recentlyUnlocked.append(achievement)

        // Add points
        totalPoints += achievement.points

        // Update user level
        let newLevel = calculateUserLevel(from: totalPoints)
        let leveledUp = newLevel.level > userLevel.level
        userLevel = newLevel

        // Remove from available achievements
        availableAchievements.removeAll { $0.id == achievement.id }

        // Trigger celebration
        await triggerAchievementCelebration(achievement, leveledUp: leveledUp)

        // Schedule notification
        await scheduleAchievementNotification(achievement)

        // Update progress tracking
        achievementProgress[achievement.id] = 1.0
    }

    /// Get user statistics for gamification display
    func getUserStatistics() -> UserStatistics {
        let totalAchievements = unlockedAchievements.count + availableAchievements.count
        let completionRate = totalAchievements > 0 ?
            Double(unlockedAchievements.count) / Double(totalAchievements) : 0.0

        let recentAchievements = unlockedAchievements
            .filter { $0.unlockedDate?.timeIntervalSinceNow ?? -86400 > -86400 } // Last 24 hours
            .count

        return UserStatistics(
            totalPoints: totalPoints,
            level: userLevel.level,
            progressToNextLevel: userLevel.progressToNext,
            totalAchievements: unlockedAchievements.count,
            availableAchievements: availableAchievements.count,
            completionRate: completionRate,
            currentStreak: currentStreak.days,
            longestStreak: currentStreak.longest,
            recentAchievements: recentAchievements
        )
    }

    /// Get achievements by category for organized display
    func getAchievements(by category: AchievementCategory) -> [Achievement] {
        let all = unlockedAchievements + availableAchievements
        return all.filter { $0.category == category }
    }

    /// Get progress for a specific achievement
    func getProgress(for achievementId: String) -> Double {
        return achievementProgress[achievementId] ?? 0.0
    }

    /// Mark recent achievements as viewed
    func markRecentAchievementsAsViewed() {
        recentlyUnlocked.removeAll()
    }

    /// Get suggested next achievements for user motivation
    func getSuggestedAchievements() -> [Achievement] {
        return availableAchievements
            .sorted { lhs, rhs in
                let progressLhs = achievementProgress[lhs.id] ?? 0.0
                let progressRhs = achievementProgress[rhs.id] ?? 0.0

                // Prioritize achievements with higher progress
                if abs(progressLhs - progressRhs) > 0.1 {
                    return progressLhs > progressRhs
                }

                // Then by points (easier achievements first)
                return lhs.points < rhs.points
            }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Private Methods

    private func createAvailableAchievements() -> [Achievement] {
        var achievements: [Achievement] = []

        // Activity achievements
        achievements.append(contentsOf: createActivityAchievements())

        // Sleep achievements
        achievements.append(contentsOf: createSleepAchievements())

        // Consistency achievements
        achievements.append(contentsOf: createConsistencyAchievements())

        // Health milestone achievements
        achievements.append(contentsOf: createHealthMilestoneAchievements())

        // Special achievements
        achievements.append(contentsOf: createSpecialAchievements())

        // Filter out already unlocked achievements
        let unlockedIds = Set(unlockedAchievements.map(\.id))
        return achievements.filter { !unlockedIds.contains($0.id) }
    }

    private func createActivityAchievements() -> [Achievement] {
        return [
            Achievement(
                id: "first_steps",
                title: NSLocalizedString("First Steps", comment: "First steps achievement title"),
                description: NSLocalizedString("Log your first daily step count", comment: "First steps achievement description"),
                category: .activity,
                type: .milestone,
                requirement: AchievementRequirement.steps(1),
                badge: AchievementBadge(
                    iconName: "figure.walk",
                    color: .blue,
                    rarity: .common
                ),
                points: 10
            ),
            Achievement(
                id: "step_master",
                title: NSLocalizedString("Step Master", comment: "Step master achievement title"),
                description: NSLocalizedString("Reach 10,000 steps in a single day", comment: "Step master achievement description"),
                category: .activity,
                type: .milestone,
                requirement: AchievementRequirement.steps(10000),
                badge: AchievementBadge(
                    iconName: "figure.run",
                    color: .blue,
                    rarity: .uncommon
                ),
                points: 50
            ),
            Achievement(
                id: "marathon_walker",
                title: NSLocalizedString("Marathon Walker", comment: "Marathon walker achievement title"),
                description: NSLocalizedString("Walk the equivalent of a marathon (26.2 miles)", comment: "Marathon walker achievement description"),
                category: .activity,
                type: .milestone,
                requirement: AchievementRequirement.steps(55000), // Approximately 26.2 miles
                badge: AchievementBadge(
                    iconName: "figure.walk.diamond",
                    color: .purple,
                    rarity: .rare
                ),
                points: 200
            ),
            Achievement(
                id: "weekly_warrior",
                title: NSLocalizedString("Weekly Warrior", comment: "Weekly warrior achievement title"),
                description: NSLocalizedString("Maintain 8,000+ steps for 7 consecutive days", comment: "Weekly warrior achievement description"),
                category: .activity,
                type: .streak,
                requirement: AchievementRequirement.stepStreak(days: 7, minimumSteps: 8000),
                badge: AchievementBadge(
                    iconName: "flame",
                    color: .orange,
                    rarity: .uncommon
                ),
                points: 75
            )
        ]
    }

    private func createSleepAchievements() -> [Achievement] {
        return [
            Achievement(
                id: "early_bird",
                title: NSLocalizedString("Early Bird", comment: "Early bird achievement title"),
                description: NSLocalizedString("Wake up before 7 AM for 5 consecutive days", comment: "Early bird achievement description"),
                category: .sleep,
                type: .streak,
                requirement: AchievementRequirement.earlyWakeStreak(days: 5, wakeTime: 7),
                badge: AchievementBadge(
                    iconName: "sunrise",
                    color: .yellow,
                    rarity: .common
                ),
                points: 30
            ),
            Achievement(
                id: "sleep_champion",
                title: NSLocalizedString("Sleep Champion", comment: "Sleep champion achievement title"),
                description: NSLocalizedString("Maintain excellent sleep quality for 7 nights", comment: "Sleep champion achievement description"),
                category: .sleep,
                type: .streak,
                requirement: AchievementRequirement.sleepQualityStreak(days: 7, minimumQuality: 0.8),
                badge: AchievementBadge(
                    iconName: "bed.double.fill",
                    color: .purple,
                    rarity: .rare
                ),
                points: 100
            ),
            Achievement(
                id: "consistent_sleeper",
                title: NSLocalizedString("Consistent Sleeper", comment: "Consistent sleeper achievement title"),
                description: NSLocalizedString("Go to bed within 30 minutes of the same time for 2 weeks", comment: "Consistent sleeper achievement description"),
                category: .sleep,
                type: .consistency,
                requirement: AchievementRequirement.bedtimeConsistency(days: 14, variationMinutes: 30),
                badge: AchievementBadge(
                    iconName: "clock.badge.checkmark",
                    color: .indigo,
                    rarity: .uncommon
                ),
                points: 60
            )
        ]
    }

    private func createConsistencyAchievements() -> [Achievement] {
        return [
            Achievement(
                id: "data_devotee",
                title: NSLocalizedString("Data Devotee", comment: "Data devotee achievement title"),
                description: NSLocalizedString("Log health data for 7 consecutive days", comment: "Data devotee achievement description"),
                category: .consistency,
                type: .streak,
                requirement: AchievementRequirement.dataEntryStreak(days: 7),
                badge: AchievementBadge(
                    iconName: "chart.line.uptrend.xyaxis",
                    color: .green,
                    rarity: .common
                ),
                points: 25
            ),
            Achievement(
                id: "commitment_keeper",
                title: NSLocalizedString("Commitment Keeper", comment: "Commitment keeper achievement title"),
                description: NSLocalizedString("Use the app for 30 consecutive days", comment: "Commitment keeper achievement description"),
                category: .consistency,
                type: .streak,
                requirement: AchievementRequirement.appUsageStreak(days: 30),
                badge: AchievementBadge(
                    iconName: "heart.fill",
                    color: .red,
                    rarity: .epic
                ),
                points: 300
            ),
            Achievement(
                id: "goal_getter",
                title: NSLocalizedString("Goal Getter", comment: "Goal getter achievement title"),
                description: NSLocalizedString("Complete 10 personal health goals", comment: "Goal getter achievement description"),
                category: .consistency,
                type: .milestone,
                requirement: AchievementRequirement.goalsCompleted(10),
                badge: AchievementBadge(
                    iconName: "target",
                    color: .mint,
                    rarity: .rare
                ),
                points: 150
            )
        ]
    }

    private func createHealthMilestoneAchievements() -> [Achievement] {
        return [
            Achievement(
                id: "vital_signs_master",
                title: NSLocalizedString("Vital Signs Master", comment: "Vital signs master achievement title"),
                description: NSLocalizedString("Record 50 vital sign measurements", comment: "Vital signs master achievement description"),
                category: .health,
                type: .milestone,
                requirement: AchievementRequirement.vitalSignsCount(50),
                badge: AchievementBadge(
                    iconName: "heart.text.square",
                    color: .red,
                    rarity: .uncommon
                ),
                points: 80
            ),
            Achievement(
                id: "wellness_warrior",
                title: NSLocalizedString("Wellness Warrior", comment: "Wellness warrior achievement title"),
                description: NSLocalizedString("Maintain all health metrics in normal range for 2 weeks", comment: "Wellness warrior achievement description"),
                category: .health,
                type: .streak,
                requirement: AchievementRequirement.healthyRangeStreak(days: 14),
                badge: AchievementBadge(
                    iconName: "shield.checkered",
                    color: .green,
                    rarity: .legendary
                ),
                points: 500
            ),
            Achievement(
                id: "document_organizer",
                title: NSLocalizedString("Document Organizer", comment: "Document organizer achievement title"),
                description: NSLocalizedString("Upload and organize 25 medical documents", comment: "Document organizer achievement description"),
                category: .health,
                type: .milestone,
                requirement: AchievementRequirement.documentsUploaded(25),
                badge: AchievementBadge(
                    iconName: "doc.badge.plus",
                    color: .blue,
                    rarity: .rare
                ),
                points: 120
            )
        ]
    }

    private func createSpecialAchievements() -> [Achievement] {
        return [
            Achievement(
                id: "new_year_starter",
                title: NSLocalizedString("New Year Starter", comment: "New year starter achievement title"),
                description: NSLocalizedString("Start your health journey in January", comment: "New year starter achievement description"),
                category: .special,
                type: .seasonal,
                requirement: AchievementRequirement.seasonalEvent(.newYear),
                badge: AchievementBadge(
                    iconName: "sparkles",
                    color: .yellow,
                    rarity: .special
                ),
                points: 50
            ),
            Achievement(
                id: "weekend_warrior",
                title: NSLocalizedString("Weekend Warrior", comment: "Weekend warrior achievement title"),
                description: NSLocalizedString("Stay active on weekends for 4 consecutive weeks", comment: "Weekend warrior achievement description"),
                category: .special,
                type: .pattern,
                requirement: AchievementRequirement.weekendActivityStreak(weeks: 4),
                badge: AchievementBadge(
                    iconName: "calendar.badge.exclamationmark",
                    color: .orange,
                    rarity: .rare
                ),
                points: 180
            ),
            Achievement(
                id: "perfect_week",
                title: NSLocalizedString("Perfect Week", comment: "Perfect week achievement title"),
                description: NSLocalizedString("Achieve all daily goals for an entire week", comment: "Perfect week achievement description"),
                category: .special,
                type: .streak,
                requirement: AchievementRequirement.perfectWeek,
                badge: AchievementBadge(
                    iconName: "crown.fill",
                    color: .yellow,
                    rarity: .legendary
                ),
                points: 400
            )
        ]
    }

    private func checkForNewAchievements(_ healthData: ProcessedHealthData) async -> [Achievement] {
        var newAchievements: [Achievement] = []

        for achievement in availableAchievements {
            if await checkAchievementRequirement(achievement.requirement, with: healthData) {
                newAchievements.append(achievement)
            }
        }

        return newAchievements
    }

    private func checkAchievementRequirement(_ requirement: AchievementRequirement, with healthData: ProcessedHealthData) async -> Bool {
        switch requirement {
        case .steps(let targetSteps):
            return healthData.activityData.last?.steps ?? 0 >= targetSteps

        case .stepStreak(let days, let minimumSteps):
            return await checkStepStreak(days: days, minimumSteps: minimumSteps, in: healthData)

        case .sleepQualityStreak(let days, let minimumQuality):
            return await checkSleepQualityStreak(days: days, minimumQuality: minimumQuality, in: healthData)

        case .earlyWakeStreak(let days, let wakeTime):
            return await checkEarlyWakeStreak(days: days, wakeTime: wakeTime, in: healthData)

        case .bedtimeConsistency(let days, let variationMinutes):
            return await checkBedtimeConsistency(days: days, variationMinutes: variationMinutes, in: healthData)

        case .dataEntryStreak(let days):
            return await checkDataEntryStreak(days: days, in: healthData)

        case .appUsageStreak(let days):
            return await checkAppUsageStreak(days: days)

        case .goalsCompleted(let count):
            return await checkGoalsCompleted(count: count)

        case .vitalSignsCount(let count):
            return healthData.vitalSignData.count >= count

        case .healthyRangeStreak(let days):
            return await checkHealthyRangeStreak(days: days, in: healthData)

        case .documentsUploaded(let count):
            return await checkDocumentsUploaded(count: count)

        case .seasonalEvent(let event):
            return checkSeasonalEvent(event)

        case .weekendActivityStreak(let weeks):
            return await checkWeekendActivityStreak(weeks: weeks, in: healthData)

        case .perfectWeek:
            return await checkPerfectWeek(in: healthData)
        }
    }

    // MARK: - Achievement Check Methods

    private func checkStepStreak(days: Int, minimumSteps: Int, in healthData: ProcessedHealthData) async -> Bool {
        let recentDays = healthData.activityData.suffix(days)
        return recentDays.count >= days && recentDays.allSatisfy { $0.steps >= minimumSteps }
    }

    private func checkSleepQualityStreak(days: Int, minimumQuality: Double, in healthData: ProcessedHealthData) async -> Bool {
        let recentSleep = healthData.sleepData.suffix(days)
        return recentSleep.count >= days && recentSleep.allSatisfy { $0.qualityScore >= minimumQuality }
    }

    private func checkEarlyWakeStreak(days: Int, wakeTime: Int, in healthData: ProcessedHealthData) async -> Bool {
        let recentSleep = healthData.sleepData.suffix(days)
        return recentSleep.count >= days && recentSleep.allSatisfy { sleep in
            let wakeHour = Calendar.current.component(.hour, from: sleep.endTime)
            return wakeHour < wakeTime
        }
    }

    private func checkBedtimeConsistency(days: Int, variationMinutes: Int, in healthData: ProcessedHealthData) async -> Bool {
        let recentSleep = healthData.sleepData.suffix(days)
        guard recentSleep.count >= days else { return false }

        let bedtimes = recentSleep.map { Calendar.current.component(.hour, from: $0.startTime) * 60 + Calendar.current.component(.minute, from: $0.startTime) }
        let avgBedtime = bedtimes.reduce(0, +) / bedtimes.count
        let maxVariation = bedtimes.map { abs($0 - avgBedtime) }.max() ?? 0

        return maxVariation <= variationMinutes
    }

    private func checkDataEntryStreak(days: Int, in healthData: ProcessedHealthData) async -> Bool {
        // Check if user has logged data for consecutive days
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<days {
            guard let checkDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { return false }

            let hasActivityData = healthData.activityData.contains { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }
            let hasSleepData = healthData.sleepData.contains { calendar.isDate($0.startTime, inSameDayAs: checkDate) }
            let hasVitalData = healthData.vitalSignData.contains { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }

            if !hasActivityData && !hasSleepData && !hasVitalData {
                return false
            }
        }

        return true
    }

    private func checkAppUsageStreak(days: Int) async -> Bool {
        // This would check app usage analytics - simplified for demo
        return days <= 30 // Placeholder logic
    }

    private func checkGoalsCompleted(count: Int) async -> Bool {
        // This would check completed goals from HealthGoalsManager - simplified for demo
        return false // Placeholder - would integrate with goals system
    }

    private func checkHealthyRangeStreak(days: Int, in healthData: ProcessedHealthData) async -> Bool {
        // Check if all health metrics are in normal range for consecutive days
        let recentDays = min(days, 14) // Check last 2 weeks max

        for dayOffset in 0..<recentDays {
            let checkDate = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            let dayData = healthData.filterForDate(checkDate)

            if !isHealthDataInNormalRange(dayData) {
                return false
            }
        }

        return true
    }

    private func checkDocumentsUploaded(count: Int) async -> Bool {
        // This would check document count from DocumentUploadManager - simplified for demo
        return false // Placeholder - would integrate with document system
    }

    private func checkSeasonalEvent(_ event: SeasonalEvent) -> Bool {
        let calendar = Calendar.current
        let now = Date()

        switch event {
        case .newYear:
            return calendar.component(.month, from: now) == 1
        case .spring:
            return [3, 4, 5].contains(calendar.component(.month, from: now))
        case .summer:
            return [6, 7, 8].contains(calendar.component(.month, from: now))
        case .fall:
            return [9, 10, 11].contains(calendar.component(.month, from: now))
        case .winter:
            return [12, 1, 2].contains(calendar.component(.month, from: now))
        }
    }

    private func checkWeekendActivityStreak(weeks: Int, in healthData: ProcessedHealthData) async -> Bool {
        let calendar = Calendar.current

        for weekOffset in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: Date()) else { return false }

            // Check Saturday and Sunday of that week
            let weekendDates = [
                calendar.date(byAdding: .day, value: 6, to: weekStart), // Saturday
                calendar.date(byAdding: .day, value: 7, to: weekStart)  // Sunday
            ].compactMap { $0 }

            for weekendDate in weekendDates {
                let hasActivity = healthData.activityData.contains { activity in
                    calendar.isDate(activity.timestamp, inSameDayAs: weekendDate) && activity.steps >= 5000
                }

                if !hasActivity {
                    return false
                }
            }
        }

        return true
    }

    private func checkPerfectWeek(in healthData: ProcessedHealthData) async -> Bool {
        // Check if user achieved all goals for 7 consecutive days
        // This would integrate with adaptive goals system - simplified for demo
        let recentWeek = healthData.activityData.suffix(7)
        return recentWeek.count >= 7 && recentWeek.allSatisfy { $0.steps >= 8000 }
    }

    private func isHealthDataInNormalRange(_ data: ProcessedHealthData) -> Bool {
        // Check if health metrics are within normal ranges
        for vital in data.vitalSignData {
            if let heartRate = vital.heartRate, heartRate < 60 || heartRate > 100 {
                return false
            }
            if let systolic = vital.systolicBP, systolic < 90 || systolic > 140 {
                return false
            }
            if let diastolic = vital.diastolicBP, diastolic < 60 || diastolic > 90 {
                return false
            }
        }

        return true
    }

    private func updateAchievementProgress() async {
        // Update progress for all available achievements
        // This would involve checking partial progress for each achievement
        // Simplified for demo
    }

    private func updateStreaks(with healthData: ProcessedHealthData) async {
        // Update current streaks based on latest health data
        let today = Calendar.current.startOfDay(for: Date())

        // Check step streak
        var stepStreakDays = 0
        for dayOffset in 0..<30 { // Check last 30 days
            guard let checkDate = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) else { break }

            let dayActivity = healthData.activityData.first { Calendar.current.isDate($0.timestamp, inSameDayAs: checkDate) }
            if let activity = dayActivity, activity.steps >= 8000 {
                stepStreakDays += 1
            } else {
                break
            }
        }

        currentStreak = StreakData(
            days: stepStreakDays,
            type: .steps,
            longest: max(currentStreak.longest, stepStreakDays)
        )
    }

    private func calculateUserLevel(from points: Int) -> UserLevel {
        // Level calculation: Every 1000 points = 1 level
        let level = points / 1000 + 1
        let pointsInCurrentLevel = points % 1000
        let progressToNext = Double(pointsInCurrentLevel) / 1000.0

        return UserLevel(
            level: level,
            progressToNext: progressToNext,
            pointsToNext: 1000 - pointsInCurrentLevel,
            title: getLevelTitle(for: level)
        )
    }

    private func getLevelTitle(for level: Int) -> String {
        switch level {
        case 1: return NSLocalizedString("Health Novice", comment: "Level 1 title")
        case 2: return NSLocalizedString("Wellness Seeker", comment: "Level 2 title")
        case 3: return NSLocalizedString("Health Enthusiast", comment: "Level 3 title")
        case 4: return NSLocalizedString("Fitness Explorer", comment: "Level 4 title")
        case 5: return NSLocalizedString("Wellness Champion", comment: "Level 5 title")
        case 6...10: return NSLocalizedString("Health Master", comment: "Level 6-10 title")
        default: return NSLocalizedString("Health Legend", comment: "Level 11+ title")
        }
    }

    private func triggerAchievementCelebration(_ achievement: Achievement, leveledUp: Bool) async {
        logger.info("Triggering celebration for achievement: \(achievement.title)")

        // Post celebration notification for UI
        NotificationCenter.default.post(
            name: .achievementUnlocked,
            object: achievement,
            userInfo: [
                "leveledUp": leveledUp,
                "newLevel": userLevel.level
            ]
        )
    }

    private func scheduleAchievementNotification(_ achievement: Achievement) async {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Achievement Unlocked!", comment: "Achievement notification title")
        content.body = String(format:
            NSLocalizedString("Congratulations! You earned '%@' and %d points!", comment: "Achievement notification body"),
            achievement.title, achievement.points
        )
        content.sound = .default
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: "achievement_\(achievement.id)",
            content: content,
            trigger: nil // Immediate delivery
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            logger.error("Failed to schedule achievement notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Data Structures

struct Achievement: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let category: AchievementCategory
    let type: AchievementType
    let requirement: AchievementRequirement
    let badge: AchievementBadge
    let points: Int
    var unlockedDate: Date?
    var progress: Double = 0.0

    init(id: String, title: String, description: String, category: AchievementCategory, type: AchievementType, requirement: AchievementRequirement, badge: AchievementBadge, points: Int) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.type = type
        self.requirement = requirement
        self.badge = badge
        self.points = points
    }
}

enum AchievementCategory: String, CaseIterable, Codable {
    case activity
    case sleep
    case consistency
    case health
    case special

    var displayName: String {
        switch self {
        case .activity: return NSLocalizedString("Activity", comment: "Activity achievement category")
        case .sleep: return NSLocalizedString("Sleep", comment: "Sleep achievement category")
        case .consistency: return NSLocalizedString("Consistency", comment: "Consistency achievement category")
        case .health: return NSLocalizedString("Health", comment: "Health achievement category")
        case .special: return NSLocalizedString("Special", comment: "Special achievement category")
        }
    }

    var icon: String {
        switch self {
        case .activity: return "figure.walk"
        case .sleep: return "bed.double"
        case .consistency: return "calendar.badge.checkmark"
        case .health: return "heart.fill"
        case .special: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .activity: return .blue
        case .sleep: return .purple
        case .consistency: return .green
        case .health: return .red
        case .special: return .yellow
        }
    }
}

enum AchievementType: String, Codable {
    case milestone
    case streak
    case consistency
    case seasonal
    case pattern
}

enum AchievementRequirement: Codable {
    case steps(Int)
    case stepStreak(days: Int, minimumSteps: Int)
    case sleepQualityStreak(days: Int, minimumQuality: Double)
    case earlyWakeStreak(days: Int, wakeTime: Int)
    case bedtimeConsistency(days: Int, variationMinutes: Int)
    case dataEntryStreak(days: Int)
    case appUsageStreak(days: Int)
    case goalsCompleted(Int)
    case vitalSignsCount(Int)
    case healthyRangeStreak(days: Int)
    case documentsUploaded(Int)
    case seasonalEvent(SeasonalEvent)
    case weekendActivityStreak(weeks: Int)
    case perfectWeek
}

enum SeasonalEvent: String, Codable {
    case newYear
    case spring
    case summer
    case fall
    case winter
}

struct AchievementBadge: Codable {
    let iconName: String
    let color: Color
    let rarity: BadgeRarity

    enum BadgeRarity: String, Codable {
        case common
        case uncommon
        case rare
        case epic
        case legendary
        case special

        var displayName: String {
            switch self {
            case .common: return NSLocalizedString("Common", comment: "Common badge rarity")
            case .uncommon: return NSLocalizedString("Uncommon", comment: "Uncommon badge rarity")
            case .rare: return NSLocalizedString("Rare", comment: "Rare badge rarity")
            case .epic: return NSLocalizedString("Epic", comment: "Epic badge rarity")
            case .legendary: return NSLocalizedString("Legendary", comment: "Legendary badge rarity")
            case .special: return NSLocalizedString("Special", comment: "Special badge rarity")
            }
        }

        var glowColor: Color {
            switch self {
            case .common: return .clear
            case .uncommon: return .green
            case .rare: return .blue
            case .epic: return .purple
            case .legendary: return .yellow
            case .special: return .pink
            }
        }
    }
}

struct StreakData: Codable {
    let days: Int
    let type: StreakType
    let longest: Int

    init(days: Int = 0, type: StreakType = .steps, longest: Int = 0) {
        self.days = days
        self.type = type
        self.longest = longest
    }
}

enum StreakType: String, Codable {
    case steps
    case sleep
    case consistency
    case app
}

struct UserLevel: Codable {
    let level: Int
    let progressToNext: Double
    let pointsToNext: Int
    let title: String

    init(level: Int = 1, progressToNext: Double = 0.0, pointsToNext: Int = 1000, title: String = "Health Novice") {
        self.level = level
        self.progressToNext = progressToNext
        self.pointsToNext = pointsToNext
        self.title = title
    }
}

struct UserStatistics {
    let totalPoints: Int
    let level: Int
    let progressToNextLevel: Double
    let totalAchievements: Int
    let availableAchievements: Int
    let completionRate: Double
    let currentStreak: Int
    let longestStreak: Int
    let recentAchievements: Int
}

// MARK: - Achievement Store

class AchievementStore {
    private let userDefaults = UserDefaults.standard
    private let achievementsKey = "user_achievements"
    private let progressKey = "achievement_progress"

    func loadUnlockedAchievements() async throws -> [Achievement] {
        guard let data = userDefaults.data(forKey: achievementsKey) else {
            return []
        }

        return try JSONDecoder().decode([Achievement].self, from: data)
    }

    func saveUnlockedAchievements(_ achievements: [Achievement]) async throws {
        let data = try JSONEncoder().encode(achievements)
        userDefaults.set(data, forKey: achievementsKey)
    }

    func loadProgress() async throws -> [String: Double] {
        guard let data = userDefaults.data(forKey: progressKey) else {
            return [:]
        }

        return try JSONDecoder().decode([String: Double].self, from: data)
    }

    func saveProgress(_ progress: [String: Double]) async throws {
        let data = try JSONEncoder().encode(progress)
        userDefaults.set(data, forKey: progressKey)
    }
}

// MARK: - Extensions

extension Color: Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let opacity = try container.decode(Double.self, forKey: .opacity)

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        guard let cgColor = self.cgColor else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Failed to encode Color"))
        }

        guard cgColor.numberOfComponents >= 3 else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Color doesn't have enough components"))
        }

        let components = cgColor.components!
        try container.encode(Double(components[0]), forKey: .red)
        try container.encode(Double(components[1]), forKey: .green)
        try container.encode(Double(components[2]), forKey: .blue)
        try container.encode(Double(cgColor.alpha), forKey: .opacity)
    }
}

extension Notification.Name {
    static let achievementUnlocked = Notification.Name("achievementUnlocked")
    static let leveledUp = Notification.Name("leveledUp")
}