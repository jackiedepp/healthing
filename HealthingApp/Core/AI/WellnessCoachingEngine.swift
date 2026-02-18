//
//  WellnessCoachingEngine.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2D: AI-Powered Health Insights
//  Implements REQ-058: Proactive health management suggestions
//  Implements REQ-059: Wellness coaching with adaptive targets
//

import Foundation
import HealthKit
import CoreML
import UserNotifications
import os.log

/// Intelligent wellness coaching system that provides proactive health suggestions and adaptive goal setting
/// Implements REQ-058: Proactive health management suggestions
/// Implements REQ-059: Wellness coaching with adaptive targets
@MainActor
class WellnessCoachingEngine: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "HealthingApp", category: "WellnessCoachingEngine")

    @Published var isActivelyCoaching = false
    @Published var currentCoachingSession: CoachingSession?
    @Published var adaptiveGoals: [AdaptiveGoal] = []
    @Published var coachingInsights: [CoachingInsight] = []
    @Published var motivationalMessages: [MotivationalMessage] = []

    // Dependencies
    private let healthInsightsEngine: HealthInsightsEngine
    private let personalizedRecommendations: PersonalizedRecommendations
    private let patternRecognitionService: PatternRecognitionService
    private let anomalyDetectionService: AnomalyDetectionService

    // Coaching configuration
    private let coachingCheckInterval: TimeInterval = 4 * 60 * 60 // 4 hours
    private let goalAdjustmentThreshold = 0.8 // Adjust goals when consistently achieving 80%+
    private let strugglingThreshold = 0.3 // Provide extra support when below 30%
    private let motivationCooldown: TimeInterval = 2 * 60 * 60 // 2 hours between motivational messages

    // Coaching state
    private var lastCoachingCheck: Date?
    private var lastMotivationalMessage: Date?
    private var userEngagementScore: Double = 0.5

    // MARK: - Initialization

    init(healthInsightsEngine: HealthInsightsEngine,
         personalizedRecommendations: PersonalizedRecommendations,
         patternRecognitionService: PatternRecognitionService,
         anomalyDetectionService: AnomalyDetectionService) {
        self.healthInsightsEngine = healthInsightsEngine
        self.personalizedRecommendations = personalizedRecommendations
        self.patternRecognitionService = patternRecognitionService
        self.anomalyDetectionService = anomalyDetectionService

        logger.info("WellnessCoachingEngine initialized")

        // Start proactive coaching
        Task {
            await startProactiveCoaching()
        }
    }

    // MARK: - Public Methods

    /// Start proactive health coaching with intelligent suggestions and adaptive goals
    func startProactiveCoaching() async {
        logger.info("Starting proactive wellness coaching")

        isActivelyCoaching = true

        // Initialize adaptive goals
        await initializeAdaptiveGoals()

        // Start coaching monitoring loop
        Task {
            await runCoachingLoop()
        }
    }

    /// Generate proactive health management suggestions based on real-time data analysis
    func generateProactiveHealthSuggestions(for data: ProcessedHealthData) async throws -> [ProactiveHealthSuggestion] {
        logger.info("Generating proactive health suggestions")

        // 1. Analyze current patterns and trends
        let currentPatterns = try await patternRecognitionService.analyzeHealthPatterns(data)
        let anomalies = try await anomalyDetectionService.detectHealthAnomalies(data)
        let recommendations = try await personalizedRecommendations.generatePersonalizedRecommendations(for: data)

        // 2. Generate context-aware suggestions
        var suggestions: [ProactiveHealthSuggestion] = []

        // Real-time health suggestions
        let realtimeSuggestions = try await generateRealtimeHealthSuggestions(data, patterns: currentPatterns)
        suggestions.append(contentsOf: realtimeSuggestions)

        // Preventive health suggestions
        let preventiveSuggestions = try await generatePreventiveHealthSuggestions(data, anomalies: anomalies)
        suggestions.append(contentsOf: preventiveSuggestions)

        // Behavior change suggestions
        let behaviorSuggestions = try await generateBehaviorChangeSuggestions(data, recommendations: recommendations)
        suggestions.append(contentsOf: behaviorSuggestions)

        // Wellness opportunity suggestions
        let wellnessSuggestions = try await generateWellnessOpportunitySuggestions(data)
        suggestions.append(contentsOf: wellnessSuggestions)

        // 3. Prioritize and personalize suggestions
        let personalizedSuggestions = try await prioritizeAndPersonalizeSuggestions(suggestions, for: data)

        logger.info("Generated \(personalizedSuggestions.count) proactive health suggestions")
        return personalizedSuggestions
    }

    /// Update adaptive goals based on user progress and performance patterns
    func updateAdaptiveGoals(with data: ProcessedHealthData) async throws {
        logger.info("Updating adaptive goals")

        for i in 0..<adaptiveGoals.count {
            let goal = adaptiveGoals[i]
            let currentProgress = try await calculateGoalProgress(goal, with: data)
            let performancePattern = try await analyzeGoalPerformancePattern(goal, with: data)

            // Update goal progress
            adaptiveGoals[i].currentProgress = currentProgress
            adaptiveGoals[i].lastUpdated = Date()

            // Adaptive goal adjustment based on consistent performance
            if performancePattern.shouldAdjustTarget {
                let adjustedGoal = try await adjustGoalTarget(goal, pattern: performancePattern, data: data)
                adaptiveGoals[i] = adjustedGoal
                logger.info("Adjusted adaptive goal: \(goal.title)")

                // Generate coaching insight about the adjustment
                let adjustmentInsight = createGoalAdjustmentInsight(originalGoal: goal, adjustedGoal: adjustedGoal)
                coachingInsights.append(adjustmentInsight)
            }
        }
    }

    /// Provide contextual wellness coaching based on current situation and user behavior
    func provideContextualWellnessCoaching(for context: WellnessContext) async throws -> CoachingSession {
        logger.info("Providing contextual wellness coaching for: \(context.situation)")

        let session = CoachingSession(
            id: UUID().uuidString,
            context: context,
            startTime: Date(),
            coachingType: determineCoachingType(for: context),
            personalizedMessages: [],
            actionableSteps: [],
            motivationalContent: [],
            progressCheckpoints: []
        )

        // Generate personalized coaching content
        let personalizedMessages = try await generatePersonalizedCoachingMessages(for: context)
        let actionableSteps = try await generateActionableCoachingSteps(for: context)
        let motivationalContent = try await generateMotivationalContent(for: context)
        let progressCheckpoints = try await generateProgressCheckpoints(for: context)

        let completedSession = CoachingSession(
            id: session.id,
            context: session.context,
            startTime: session.startTime,
            coachingType: session.coachingType,
            personalizedMessages: personalizedMessages,
            actionableSteps: actionableSteps,
            motivationalContent: motivationalContent,
            progressCheckpoints: progressCheckpoints
        )

        currentCoachingSession = completedSession

        logger.info("Coaching session created with \(personalizedMessages.count) messages and \(actionableSteps.count) actionable steps")
        return completedSession
    }

    /// Generate motivational messages based on user progress and engagement patterns
    func generateMotivationalMessage(for achievement: HealthAchievement) async -> MotivationalMessage {
        logger.info("Generating motivational message for achievement: \(achievement.type)")

        let messageStyle = determineMotivationalStyle(for: achievement)
        let content = await generateMotivationalContent(for: achievement, style: messageStyle)

        let message = MotivationalMessage(
            id: UUID().uuidString,
            achievement: achievement,
            content: content,
            style: messageStyle,
            deliveryTime: Date(),
            expiresAt: Date().addingTimeInterval(24 * 60 * 60), // Valid for 24 hours
            hasBeenDelivered: false
        )

        motivationalMessages.append(message)
        lastMotivationalMessage = Date()

        return message
    }

    /// Get current wellness coaching status and recommendations
    func getCurrentWellnessStatus() -> WellnessCoachingStatus {
        let activeGoalsCount = adaptiveGoals.filter { !$0.isCompleted }.count
        let recentInsights = coachingInsights.filter { $0.timestamp > Date().addingTimeInterval(-24 * 60 * 60) }
        let pendingMessages = motivationalMessages.filter { !$0.hasBeenDelivered }

        return WellnessCoachingStatus(
            isActivelyCoaching: isActivelyCoaching,
            activeGoalsCount: activeGoalsCount,
            recentInsightsCount: recentInsights.count,
            pendingMessagesCount: pendingMessages.count,
            userEngagementScore: userEngagementScore,
            lastCoachingCheck: lastCoachingCheck,
            nextCoachingCheck: lastCoachingCheck?.addingTimeInterval(coachingCheckInterval)
        )
    }

    /// Manual trigger for immediate coaching intervention
    func requestImmediateCoaching(reason: CoachingTrigger) async throws -> CoachingSession {
        logger.info("Immediate coaching requested: \(reason)")

        let context = WellnessContext(
            situation: .userRequested,
            trigger: reason,
            timestamp: Date(),
            urgency: .medium,
            userState: await determineCurrentUserState()
        )

        return try await provideContextualWellnessCoaching(for: context)
    }

    // MARK: - Private Methods

    private func runCoachingLoop() async {
        while isActivelyCoaching {
            do {
                await performCoachingCheck()

                // Wait for next check interval
                try await Task.sleep(nanoseconds: UInt64(coachingCheckInterval * 1_000_000_000))
            } catch {
                logger.error("Error in coaching loop: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000)) // Wait 1 minute before retrying
            }
        }
    }

    private func performCoachingCheck() async {
        logger.debug("Performing proactive coaching check")

        do {
            // Get latest health data
            let healthData = try await healthInsightsEngine.collectHealthData()

            // Update adaptive goals
            try await updateAdaptiveGoals(with: healthData)

            // Generate proactive suggestions if needed
            let suggestions = try await generateProactiveHealthSuggestions(for: healthData)

            // Check for coaching opportunities
            await checkForCoachingOpportunities(healthData, suggestions: suggestions)

            // Update user engagement score
            await updateUserEngagementScore(healthData)

            lastCoachingCheck = Date()

        } catch {
            logger.error("Error during coaching check: \(error.localizedDescription)")
        }
    }

    private func initializeAdaptiveGoals() async {
        logger.info("Initializing adaptive wellness goals")

        // Create foundational adaptive goals
        let sleepGoal = AdaptiveGoal(
            id: UUID().uuidString,
            title: NSLocalizedString("Optimal Sleep Quality", comment: "Adaptive sleep goal"),
            description: NSLocalizedString("Maintain consistent, high-quality sleep for better health", comment: "Sleep goal description"),
            category: .sleep,
            targetValue: 8.0, // 8 hours
            targetUnit: "hours",
            currentProgress: 0.0,
            adaptationStrategy: .gradualIncrease,
            difficultyLevel: .moderate,
            timeframe: .ongoing,
            createdDate: Date(),
            lastUpdated: Date(),
            isCompleted: false
        )

        let activityGoal = AdaptiveGoal(
            id: UUID().uuidString,
            title: NSLocalizedString("Daily Movement Target", comment: "Adaptive activity goal"),
            description: NSLocalizedString("Achieve daily activity goals that adapt to your progress", comment: "Activity goal description"),
            category: .activity,
            targetValue: 10000, // 10,000 steps
            targetUnit: "steps",
            currentProgress: 0.0,
            adaptationStrategy: .performanceBased,
            difficultyLevel: .moderate,
            timeframe: .ongoing,
            createdDate: Date(),
            lastUpdated: Date(),
            isCompleted: false
        )

        let wellnessGoal = AdaptiveGoal(
            id: UUID().uuidString,
            title: NSLocalizedString("Stress Management", comment: "Adaptive wellness goal"),
            description: NSLocalizedString("Develop effective stress management habits", comment: "Wellness goal description"),
            category: .wellness,
            targetValue: 10.0, // 10 minutes daily
            targetUnit: "minutes",
            currentProgress: 0.0,
            adaptationStrategy: .needsBased,
            difficultyLevel: .easy,
            timeframe: .ongoing,
            createdDate: Date(),
            lastUpdated: Date(),
            isCompleted: false
        )

        adaptiveGoals = [sleepGoal, activityGoal, wellnessGoal]
        logger.info("Initialized \(adaptiveGoals.count) adaptive goals")
    }

    private func generateRealtimeHealthSuggestions(_ data: ProcessedHealthData, patterns: [HealthInsight]) async throws -> [ProactiveHealthSuggestion] {
        var suggestions: [ProactiveHealthSuggestion] = []

        // Current time context
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isWeekday = !Calendar.current.isDateInWeekend(Date())

        // Morning suggestions (6-10 AM)
        if currentHour >= 6 && currentHour <= 10 {
            if let lastSleep = data.sleepData.last, lastSleep.duration < 7 * 60 * 60 {
                suggestions.append(createMorningEnergySuggestion(shortSleep: lastSleep.duration))
            }

            if data.hydrationData.isEmpty {
                suggestions.append(createMorningHydrationSuggestion())
            }
        }

        // Afternoon suggestions (12-17 PM)
        if currentHour >= 12 && currentHour <= 17 {
            let morningActivity = data.activityData.filter {
                Calendar.current.component(.hour, from: $0.timestamp) < 12
            }
            if morningActivity.map(\.steps).reduce(0, +) < 3000 {
                suggestions.append(createAfternoonMovementSuggestion())
            }
        }

        // Evening suggestions (18-22 PM)
        if currentHour >= 18 && currentHour <= 22 {
            let todayStress = calculateTodayStressLevel(data)
            if todayStress > 0.7 {
                suggestions.append(createEveningRelaxationSuggestion())
            }
        }

        return suggestions
    }

    private func generatePreventiveHealthSuggestions(_ data: ProcessedHealthData, anomalies: [HealthInsight]) async throws -> [ProactiveHealthSuggestion] {
        var suggestions: [ProactiveHealthSuggestion] = []

        for anomaly in anomalies where anomaly.priority == .high {
            switch anomaly.category {
            case .vitalSigns:
                suggestions.append(createVitalSignsPreventiveSuggestion(anomaly: anomaly))
            case .sleep:
                suggestions.append(createSleepPreventiveSuggestion(anomaly: anomaly))
            case .activity:
                suggestions.append(createActivityPreventiveSuggestion(anomaly: anomaly))
            default:
                break
            }
        }

        return suggestions
    }

    private func generateBehaviorChangeSuggestions(_ data: ProcessedHealthData, recommendations: [HealthRecommendation]) async throws -> [ProactiveHealthSuggestion] {
        var suggestions: [ProactiveHealthSuggestion] = []

        // Focus on struggling recommendations for behavior change support
        let strugglingRecommendations = recommendations.filter { $0.progress < strugglingThreshold }

        for recommendation in strugglingRecommendations {
            let behaviorSuggestion = createBehaviorChangeSuggestion(for: recommendation, data: data)
            suggestions.append(behaviorSuggestion)
        }

        return suggestions
    }

    private func generateWellnessOpportunitySuggestions(_ data: ProcessedHealthData) async throws -> [ProactiveHealthSuggestion] {
        var suggestions: [ProactiveHealthSuggestion] = []

        // Weather-based suggestions (simplified)
        let isGoodWeather = true // Would integrate with weather API
        if isGoodWeather {
            suggestions.append(createOutdoorActivitySuggestion())
        }

        // Social wellness opportunities
        let daysSinceLastSocialActivity = 3 // Would track from social activity data
        if daysSinceLastSocialActivity >= 3 {
            suggestions.append(createSocialWellnessSuggestion())
        }

        // Learning opportunities
        let consistencyScore = calculateOverallConsistency(data)
        if consistencyScore > 0.8 {
            suggestions.append(createNewChallengeeSuggestion())
        }

        return suggestions
    }

    private func prioritizeAndPersonalizeSuggestions(_ suggestions: [ProactiveHealthSuggestion], for data: ProcessedHealthData) async throws -> [ProactiveHealthSuggestion] {
        // Calculate user context for personalization
        let userState = await determineCurrentUserState()
        let timeOfDay = Calendar.current.component(.hour, from: Date())

        return suggestions
            .filter { isAppropriateForCurrentContext($0, userState: userState, timeOfDay: timeOfDay) }
            .sorted { lhs, rhs in
                // Primary sort: Urgency
                if lhs.urgency != rhs.urgency {
                    return lhs.urgency.rawValue > rhs.urgency.rawValue
                }

                // Secondary sort: Impact potential
                if lhs.impactPotential != rhs.impactPotential {
                    return lhs.impactPotential > rhs.impactPotential
                }

                // Tertiary sort: User engagement likelihood
                return lhs.engagementLikelihood > rhs.engagementLikelihood
            }
            .prefix(5) // Limit to top 5 suggestions
            .map { $0 }
    }

    private func calculateGoalProgress(_ goal: AdaptiveGoal, with data: ProcessedHealthData) async throws -> Double {
        switch goal.category {
        case .sleep:
            let recentSleep = data.sleepData.suffix(7)
            guard !recentSleep.isEmpty else { return 0 }
            let averageDuration = recentSleep.map(\.duration).reduce(0, +) / Double(recentSleep.count)
            let targetDuration = goal.targetValue * 60 * 60 // Convert hours to seconds
            return min(1.0, averageDuration / targetDuration)

        case .activity:
            let recentActivity = data.activityData.suffix(7)
            guard !recentActivity.isEmpty else { return 0 }
            let averageSteps = recentActivity.map { Double($0.steps) }.reduce(0, +) / Double(recentActivity.count)
            return min(1.0, averageSteps / goal.targetValue)

        case .wellness:
            let recentMindfulness = data.mindfulnessData.suffix(7)
            guard !recentMindfulness.isEmpty else { return 0 }
            let averageMinutes = recentMindfulness.map(\.sessionDuration).reduce(0, +) / Double(recentMindfulness.count)
            return min(1.0, averageMinutes / goal.targetValue)

        default:
            return 0
        }
    }

    private func analyzeGoalPerformancePattern(_ goal: AdaptiveGoal, with data: ProcessedHealthData) async throws -> GoalPerformancePattern {
        // Analyze last 30 days of performance
        let last30Days = data.filterRecent(days: 30)
        let progressHistory = try await calculateProgressHistory(goal, data: last30Days)

        let averageProgress = progressHistory.reduce(0, +) / Double(progressHistory.count)
        let consistency = calculateProgressConsistency(progressHistory)
        let trend = calculateProgressTrend(progressHistory)

        let shouldAdjustTarget = averageProgress >= goalAdjustmentThreshold && consistency > 0.7
        let needsSupport = averageProgress < strugglingThreshold

        return GoalPerformancePattern(
            averageProgress: averageProgress,
            consistency: consistency,
            trend: trend,
            shouldAdjustTarget: shouldAdjustTarget,
            needsSupport: needsSupport,
            recommendedAdjustment: shouldAdjustTarget ? 0.15 : 0.0 // 15% increase if performing well
        )
    }

    private func adjustGoalTarget(_ goal: AdaptiveGoal, pattern: GoalPerformancePattern, data: ProcessedHealthData) async throws -> AdaptiveGoal {
        var adjustedGoal = goal

        switch goal.adaptationStrategy {
        case .gradualIncrease:
            if pattern.shouldAdjustTarget {
                adjustedGoal.targetValue = goal.targetValue * (1.0 + pattern.recommendedAdjustment)
            }
        case .performanceBased:
            if pattern.shouldAdjustTarget {
                adjustedGoal.targetValue = goal.targetValue * (1.0 + pattern.recommendedAdjustment)
            } else if pattern.needsSupport {
                adjustedGoal.targetValue = goal.targetValue * 0.9 // Reduce target by 10%
            }
        case .needsBased:
            // Adjust based on detected health needs
            adjustedGoal.targetValue = try await calculateNeedsBasedTarget(goal, data: data)
        }

        adjustedGoal.lastUpdated = Date()
        return adjustedGoal
    }

    private func checkForCoachingOpportunities(_ data: ProcessedHealthData, suggestions: [ProactiveHealthSuggestion]) async {
        // Check for high-priority coaching opportunities
        let urgentSuggestions = suggestions.filter { $0.urgency == .high }

        if !urgentSuggestions.isEmpty {
            let context = WellnessContext(
                situation: .proactiveOpportunity,
                trigger: .healthAlert,
                timestamp: Date(),
                urgency: .high,
                userState: await determineCurrentUserState()
            )

            do {
                _ = try await provideContextualWellnessCoaching(for: context)
            } catch {
                logger.error("Failed to provide urgent coaching: \(error.localizedDescription)")
            }
        }

        // Check for motivation opportunities
        await checkForMotivationOpportunities(data)
    }

    private func checkForMotivationOpportunities(_ data: ProcessedHealthData) async {
        // Only send motivational messages if enough time has passed
        if let lastMessage = lastMotivationalMessage,
           Date().timeIntervalSince(lastMessage) < motivationCooldown {
            return
        }

        // Check for achievements to celebrate
        let achievements = await detectHealthAchievements(data)

        for achievement in achievements {
            let motivationalMessage = await generateMotivationalMessage(for: achievement)

            // Schedule delivery of motivational message
            await scheduleMotivationalMessageDelivery(motivationalMessage)
        }
    }

    private func updateUserEngagementScore(_ data: ProcessedHealthData) async {
        // Calculate engagement based on various factors
        let dataCompleteness = calculateDataCompleteness(data)
        let goalProgress = adaptiveGoals.map(\.currentProgress).reduce(0, +) / Double(adaptiveGoals.count)
        let recentActivity = data.activityData.suffix(7).count >= 7 ? 1.0 : 0.5

        let newEngagementScore = (dataCompleteness + goalProgress + recentActivity) / 3.0

        // Smooth the engagement score with exponential moving average
        userEngagementScore = 0.3 * newEngagementScore + 0.7 * userEngagementScore
    }

    // MARK: - Helper Methods

    private func determineCurrentUserState() async -> UserState {
        let currentHour = Calendar.current.component(.hour, from: Date())

        switch currentHour {
        case 6...11:
            return .morning
        case 12...17:
            return .afternoon
        case 18...22:
            return .evening
        default:
            return .night
        }
    }

    private func determineCoachingType(for context: WellnessContext) -> CoachingType {
        switch context.situation {
        case .healthAlert:
            return .intervention
        case .goalStruggling:
            return .supportive
        case .goalProgression:
            return .motivational
        case .userRequested:
            return .consultative
        case .proactiveOpportunity:
            return .educational
        }
    }

    private func calculateTodayStressLevel(_ data: ProcessedHealthData) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        let todayData = data.vitalSignData.filter { $0.timestamp >= today }

        guard !todayData.isEmpty else { return 0.5 }

        // Simplified stress calculation based on heart rate variability
        let hrvValues = todayData.compactMap(\.heartRateVariability)
        guard !hrvValues.isEmpty else { return 0.5 }

        let averageHRV = hrvValues.reduce(0, +) / Double(hrvValues.count)
        return max(0, min(1, 1.0 - (averageHRV / 50.0))) // Normalized stress level
    }

    private func calculateOverallConsistency(_ data: ProcessedHealthData) -> Double {
        let sleepConsistency = calculateDataConsistency(data.sleepData.map(\.qualityScore))
        let activityConsistency = calculateDataConsistency(data.activityData.map { Double($0.steps) })

        return (sleepConsistency + activityConsistency) / 2.0
    }

    private func calculateDataConsistency<T: FloatingPoint>(_ values: [T]) -> Double {
        guard values.count > 1 else { return 1.0 }

        let mean = values.reduce(0, +) / T(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / T(values.count)
        let standardDeviation = sqrt(Double(variance))
        let coefficientOfVariation = standardDeviation / Double(mean)

        return max(0, 1.0 - coefficientOfVariation)
    }

    private func calculateDataCompleteness(_ data: ProcessedHealthData) -> Double {
        let totalExpectedEntries = 7.0 // Last 7 days
        let sleepCompleteness = min(1.0, Double(data.sleepData.suffix(7).count) / totalExpectedEntries)
        let activityCompleteness = min(1.0, Double(data.activityData.suffix(7).count) / totalExpectedEntries)

        return (sleepCompleteness + activityCompleteness) / 2.0
    }

    private func calculateProgressHistory(_ goal: AdaptiveGoal, data: ProcessedHealthData) async throws -> [Double] {
        // Simplified progress history - would implement day-by-day calculation
        var progressHistory: [Double] = []

        for dayOffset in 1...30 {
            let dayDate = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            let dayData = data.filterForDate(dayDate)
            let dayProgress = try await calculateGoalProgress(goal, with: dayData)
            progressHistory.append(dayProgress)
        }

        return progressHistory.reversed()
    }

    private func calculateProgressConsistency(_ progressHistory: [Double]) -> Double {
        return calculateDataConsistency(progressHistory)
    }

    private func calculateProgressTrend(_ progressHistory: [Double]) -> TrendDirection {
        guard progressHistory.count >= 7 else { return .stable }

        let firstWeek = progressHistory.prefix(7).reduce(0, +) / 7
        let lastWeek = progressHistory.suffix(7).reduce(0, +) / 7

        if lastWeek > firstWeek + 0.1 {
            return .improving
        } else if lastWeek < firstWeek - 0.1 {
            return .declining
        } else {
            return .stable
        }
    }

    private func calculateNeedsBasedTarget(_ goal: AdaptiveGoal, data: ProcessedHealthData) async throws -> Double {
        // Adjust target based on detected health needs
        switch goal.category {
        case .wellness:
            let currentStress = calculateTodayStressLevel(data)
            if currentStress > 0.7 {
                return goal.targetValue * 1.5 // Increase wellness target when stressed
            } else {
                return goal.targetValue
            }
        default:
            return goal.targetValue
        }
    }

    private func detectHealthAchievements(_ data: ProcessedHealthData) async -> [HealthAchievement] {
        var achievements: [HealthAchievement] = []

        // Sleep achievement
        let recentSleep = data.sleepData.suffix(7)
        if recentSleep.allSatisfy({ $0.qualityScore >= 0.8 }) {
            achievements.append(HealthAchievement(
                id: UUID().uuidString,
                type: .sleepConsistency,
                title: NSLocalizedString("Sleep Champion", comment: "Sleep achievement title"),
                description: NSLocalizedString("7 consecutive days of excellent sleep!", comment: "Sleep achievement description"),
                earnedDate: Date(),
                category: .sleep
            ))
        }

        // Activity achievement
        let recentActivity = data.activityData.suffix(7)
        if recentActivity.allSatisfy({ $0.steps >= 10000 }) {
            achievements.append(HealthAchievement(
                id: UUID().uuidString,
                type: .stepGoal,
                title: NSLocalizedString("Step Master", comment: "Activity achievement title"),
                description: NSLocalizedString("10,000+ steps for 7 days straight!", comment: "Activity achievement description"),
                earnedDate: Date(),
                category: .activity
            ))
        }

        return achievements
    }

    private func isAppropriateForCurrentContext(_ suggestion: ProactiveHealthSuggestion, userState: UserState, timeOfDay: Int) -> Bool {
        // Filter suggestions based on appropriateness for current context
        switch suggestion.timing {
        case .immediate:
            return true
        case .morning:
            return timeOfDay >= 6 && timeOfDay <= 11
        case .afternoon:
            return timeOfDay >= 12 && timeOfDay <= 17
        case .evening:
            return timeOfDay >= 18 && timeOfDay <= 22
        case .flexible:
            return timeOfDay >= 8 && timeOfDay <= 20 // During waking hours
        }
    }

    // MARK: - Suggestion Creation Methods

    private func createMorningEnergySuggestion(shortSleep: TimeInterval) -> ProactiveHealthSuggestion {
        let sleepDeficitHours = (8 * 60 * 60 - shortSleep) / (60 * 60)

        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Boost Morning Energy", comment: "Morning energy suggestion"),
            description: String(format: NSLocalizedString("You slept %.1f hours less than optimal. Try these energy boosters.", comment: "Morning energy description"), sleepDeficitHours),
            category: .energy,
            urgency: .medium,
            timing: .immediate,
            impactPotential: 0.7,
            engagementLikelihood: 0.8,
            actions: [
                NSLocalizedString("Get 10 minutes of natural sunlight", comment: "Morning energy action"),
                NSLocalizedString("Do 5 minutes of gentle stretching", comment: "Morning energy action"),
                NSLocalizedString("Drink a glass of water", comment: "Morning energy action")
            ],
            estimatedDuration: 15,
            validUntil: Date().addingTimeInterval(2 * 60 * 60)
        )
    }

    private func createMorningHydrationSuggestion() -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Start Hydrated", comment: "Morning hydration suggestion"),
            description: NSLocalizedString("Begin your day with proper hydration for optimal energy and focus.", comment: "Morning hydration description"),
            category: .hydration,
            urgency: .low,
            timing: .morning,
            impactPotential: 0.6,
            engagementLikelihood: 0.9,
            actions: [
                NSLocalizedString("Drink 16-20 oz of water upon waking", comment: "Morning hydration action"),
                NSLocalizedString("Add lemon for extra vitamin C", comment: "Morning hydration action")
            ],
            estimatedDuration: 2,
            validUntil: Date().addingTimeInterval(4 * 60 * 60)
        )
    }

    private func createAfternoonMovementSuggestion() -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Afternoon Activity Boost", comment: "Afternoon movement suggestion"),
            description: NSLocalizedString("You've been less active this morning. Let's get moving!", comment: "Afternoon movement description"),
            category: .activity,
            urgency: .medium,
            timing: .afternoon,
            impactPotential: 0.8,
            engagementLikelihood: 0.7,
            actions: [
                NSLocalizedString("Take a 10-minute brisk walk", comment: "Afternoon movement action"),
                NSLocalizedString("Use stairs instead of elevator", comment: "Afternoon movement action"),
                NSLocalizedString("Do desk exercises if unable to walk", comment: "Afternoon movement action")
            ],
            estimatedDuration: 10,
            validUntil: Date().addingTimeInterval(3 * 60 * 60)
        )
    }

    private func createEveningRelaxationSuggestion() -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Evening Wind-Down", comment: "Evening relaxation suggestion"),
            description: NSLocalizedString("High stress detected today. Let's help you relax before bedtime.", comment: "Evening relaxation description"),
            category: .relaxation,
            urgency: .high,
            timing: .evening,
            impactPotential: 0.9,
            engagementLikelihood: 0.8,
            actions: [
                NSLocalizedString("Practice deep breathing for 5 minutes", comment: "Evening relaxation action"),
                NSLocalizedString("Take a warm bath or shower", comment: "Evening relaxation action"),
                NSLocalizedString("Avoid screens 1 hour before bed", comment: "Evening relaxation action")
            ],
            estimatedDuration: 20,
            validUntil: Date().addingTimeInterval(4 * 60 * 60)
        )
    }

    // Additional suggestion creation methods would be implemented here...
    private func createVitalSignsPreventiveSuggestion(anomaly: HealthInsight) -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Monitor Vital Signs", comment: "Vital signs prevention"),
            description: NSLocalizedString("We've detected some unusual patterns in your vital signs. Let's keep a closer eye on them.", comment: "Vital signs prevention description"),
            category: .preventive,
            urgency: .high,
            timing: .flexible,
            impactPotential: 0.9,
            engagementLikelihood: 0.7,
            actions: [
                NSLocalizedString("Take a few deep breaths and rest for 5 minutes", comment: "Vital signs action"),
                NSLocalizedString("Check your blood pressure if available", comment: "Vital signs action"),
                NSLocalizedString("Contact healthcare provider if symptoms persist", comment: "Vital signs action")
            ],
            estimatedDuration: 10,
            validUntil: Date().addingTimeInterval(12 * 60 * 60)
        )
    }

    private func createSleepPreventiveSuggestion(anomaly: HealthInsight) -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Sleep Pattern Alert", comment: "Sleep prevention"),
            description: NSLocalizedString("Your sleep patterns show some concerning changes. Let's address them early.", comment: "Sleep prevention description"),
            category: .sleep,
            urgency: .medium,
            timing: .evening,
            impactPotential: 0.8,
            engagementLikelihood: 0.8,
            actions: [
                NSLocalizedString("Establish a consistent bedtime routine", comment: "Sleep prevention action"),
                NSLocalizedString("Limit caffeine after 2 PM", comment: "Sleep prevention action"),
                NSLocalizedString("Keep a sleep diary for one week", comment: "Sleep prevention action")
            ],
            estimatedDuration: 30,
            validUntil: Date().addingTimeInterval(24 * 60 * 60)
        )
    }

    private func createActivityPreventiveSuggestion(anomaly: HealthInsight) -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Activity Intervention", comment: "Activity prevention"),
            description: NSLocalizedString("Your activity levels have dropped significantly. Let's prevent further decline.", comment: "Activity prevention description"),
            category: .activity,
            urgency: .medium,
            timing: .flexible,
            impactPotential: 0.8,
            engagementLikelihood: 0.6,
            actions: [
                NSLocalizedString("Start with just 5 minutes of movement", comment: "Activity prevention action"),
                NSLocalizedString("Schedule short walks throughout the day", comment: "Activity prevention action"),
                NSLocalizedString("Find an accountability partner", comment: "Activity prevention action")
            ],
            estimatedDuration: 5,
            validUntil: Date().addingTimeInterval(8 * 60 * 60)
        )
    }

    private func createBehaviorChangeSuggestion(for recommendation: HealthRecommendation, data: ProcessedHealthData) -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Overcome Challenge", comment: "Behavior change suggestion"),
            description: String(format: NSLocalizedString("Having trouble with '%@'? Let's try a different approach.", comment: "Behavior change description"), recommendation.title),
            category: .behaviorChange,
            urgency: .medium,
            timing: .flexible,
            impactPotential: 0.7,
            engagementLikelihood: 0.6,
            actions: [
                NSLocalizedString("Break the goal into smaller steps", comment: "Behavior change action"),
                NSLocalizedString("Find what's blocking your progress", comment: "Behavior change action"),
                NSLocalizedString("Celebrate small wins along the way", comment: "Behavior change action")
            ],
            estimatedDuration: 10,
            validUntil: Date().addingTimeInterval(24 * 60 * 60)
        )
    }

    private func createOutdoorActivitySuggestion() -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Beautiful Day Outside", comment: "Outdoor activity suggestion"),
            description: NSLocalizedString("Perfect weather for outdoor activities! Get some fresh air and vitamin D.", comment: "Outdoor activity description"),
            category: .activity,
            urgency: .low,
            timing: .flexible,
            impactPotential: 0.8,
            engagementLikelihood: 0.7,
            actions: [
                NSLocalizedString("Take a walk in the park", comment: "Outdoor activity action"),
                NSLocalizedString("Try outdoor yoga or stretching", comment: "Outdoor activity action"),
                NSLocalizedString("Have lunch outside if possible", comment: "Outdoor activity action")
            ],
            estimatedDuration: 30,
            validUntil: Date().addingTimeInterval(6 * 60 * 60)
        )
    }

    private func createSocialWellnessSuggestion() -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Connect with Others", comment: "Social wellness suggestion"),
            description: NSLocalizedString("Social connections are important for mental health. Time to reach out!", comment: "Social wellness description"),
            category: .social,
            urgency: .low,
            timing: .flexible,
            impactPotential: 0.6,
            engagementLikelihood: 0.5,
            actions: [
                NSLocalizedString("Call a friend or family member", comment: "Social wellness action"),
                NSLocalizedString("Plan a coffee date or meal together", comment: "Social wellness action"),
                NSLocalizedString("Join a group activity or class", comment: "Social wellness action")
            ],
            estimatedDuration: 60,
            validUntil: Date().addingTimeInterval(48 * 60 * 60)
        )
    }

    private func createNewChallengeeSuggestion() -> ProactiveHealthSuggestion {
        return ProactiveHealthSuggestion(
            id: UUID().uuidString,
            title: NSLocalizedString("Ready for More?", comment: "New challenge suggestion"),
            description: NSLocalizedString("You've been consistent with your health habits! Time for a new challenge.", comment: "New challenge description"),
            category: .growth,
            urgency: .low,
            timing: .flexible,
            impactPotential: 0.7,
            engagementLikelihood: 0.6,
            actions: [
                NSLocalizedString("Try a new type of exercise", comment: "New challenge action"),
                NSLocalizedString("Set a more ambitious health goal", comment: "New challenge action"),
                NSLocalizedString("Learn a new wellness skill", comment: "New challenge action")
            ],
            estimatedDuration: 30,
            validUntil: Date().addingTimeInterval(72 * 60 * 60)
        )
    }

    // MARK: - Coaching Content Generation Methods

    private func generatePersonalizedCoachingMessages(for context: WellnessContext) async throws -> [PersonalizedCoachingMessage] {
        var messages: [PersonalizedCoachingMessage] = []

        switch context.situation {
        case .healthAlert:
            messages.append(PersonalizedCoachingMessage(
                content: NSLocalizedString("I've noticed some changes in your health patterns. Let's address this together.", comment: "Health alert coaching message"),
                tone: .supportive,
                priority: .high
            ))
        case .goalStruggling:
            messages.append(PersonalizedCoachingMessage(
                content: NSLocalizedString("Everyone faces challenges with their health goals. You're not alone in this journey.", comment: "Goal struggling coaching message"),
                tone: .encouraging,
                priority: .medium
            ))
        case .goalProgression:
            messages.append(PersonalizedCoachingMessage(
                content: NSLocalizedString("Your progress is impressive! Let's build on this momentum.", comment: "Goal progression coaching message"),
                tone: .celebratory,
                priority: .medium
            ))
        default:
            messages.append(PersonalizedCoachingMessage(
                content: NSLocalizedString("I'm here to support your wellness journey. What would you like to focus on?", comment: "General coaching message"),
                tone: .neutral,
                priority: .low
            ))
        }

        return messages
    }

    private func generateActionableCoachingSteps(for context: WellnessContext) async throws -> [ActionableCoachingStep] {
        var steps: [ActionableCoachingStep] = []

        switch context.situation {
        case .healthAlert:
            steps.append(ActionableCoachingStep(
                title: NSLocalizedString("Monitor Closely", comment: "Monitoring step"),
                description: NSLocalizedString("Keep tracking your health metrics more frequently", comment: "Monitoring description"),
                estimatedTime: 5,
                difficulty: .easy,
                category: .monitoring
            ))
        case .goalStruggling:
            steps.append(ActionableCoachingStep(
                title: NSLocalizedString("Adjust Strategy", comment: "Strategy step"),
                description: NSLocalizedString("Let's modify your approach to make it more achievable", comment: "Strategy description"),
                estimatedTime: 10,
                difficulty: .moderate,
                category: .strategy
            ))
        default:
            steps.append(ActionableCoachingStep(
                title: NSLocalizedString("Continue Progress", comment: "Progress step"),
                description: NSLocalizedString("Keep following your current wellness plan", comment: "Progress description"),
                estimatedTime: 0,
                difficulty: .easy,
                category: .maintenance
            ))
        }

        return steps
    }

    private func generateMotivationalContent(for context: WellnessContext) async throws -> [MotivationalContent] {
        var content: [MotivationalContent] = []

        content.append(MotivationalContent(
            type: .quote,
            content: NSLocalizedString("\"Health is not about the weight you lose, but about the life you gain.\"", comment: "Motivational quote"),
            source: NSLocalizedString("Health Wisdom", comment: "Quote source")
        ))

        content.append(MotivationalContent(
            type: .affirmation,
            content: NSLocalizedString("Every small step you take is building a healthier you.", comment: "Motivational affirmation"),
            source: nil
        ))

        return content
    }

    private func generateProgressCheckpoints(for context: WellnessContext) async throws -> [ProgressCheckpoint] {
        var checkpoints: [ProgressCheckpoint] = []

        checkpoints.append(ProgressCheckpoint(
            title: NSLocalizedString("Daily Check-in", comment: "Daily checkpoint"),
            description: NSLocalizedString("How are you feeling today?", comment: "Daily checkpoint description"),
            frequency: .daily,
            questions: [
                NSLocalizedString("Rate your energy level (1-10)", comment: "Energy question"),
                NSLocalizedString("Did you achieve your wellness goals today?", comment: "Goals question")
            ]
        ))

        return checkpoints
    }

    private func generateMotivationalContent(for achievement: HealthAchievement, style: MotivationalStyle) async -> MotivationalMessageContent {
        switch style {
        case .celebratory:
            return MotivationalMessageContent(
                title: NSLocalizedString("🎉 Amazing Achievement!", comment: "Celebratory title"),
                message: String(format: NSLocalizedString("Congratulations on earning '%@'! Your dedication is paying off.", comment: "Celebratory message"), achievement.title),
                callToAction: NSLocalizedString("Keep up the fantastic work!", comment: "Celebratory CTA"),
                visualElements: ["🎉", "⭐", "💪"]
            )
        case .encouraging:
            return MotivationalMessageContent(
                title: NSLocalizedString("Great Progress!", comment: "Encouraging title"),
                message: String(format: NSLocalizedString("You've earned '%@' through consistent effort. That's the key to lasting health.", comment: "Encouraging message"), achievement.title),
                callToAction: NSLocalizedString("Your consistency is inspiring!", comment: "Encouraging CTA"),
                visualElements: ["👏", "🌟", "💚"]
            )
        case .inspirational:
            return MotivationalMessageContent(
                title: NSLocalizedString("You're Inspiring!", comment: "Inspirational title"),
                message: String(format: NSLocalizedString("Earning '%@' shows your commitment to health. You're setting a wonderful example.", comment: "Inspirational message"), achievement.title),
                callToAction: NSLocalizedString("Continue inspiring others!", comment: "Inspirational CTA"),
                visualElements: ["✨", "🌈", "🙌"]
            )
        }
    }

    private func determineMotivationalStyle(for achievement: HealthAchievement) -> MotivationalStyle {
        switch achievement.category {
        case .sleep:
            return .encouraging
        case .activity:
            return .celebratory
        case .wellness:
            return .inspirational
        default:
            return .encouraging
        }
    }

    private func createGoalAdjustmentInsight(originalGoal: AdaptiveGoal, adjustedGoal: AdaptiveGoal) -> CoachingInsight {
        let improvementPercentage = ((adjustedGoal.targetValue - originalGoal.targetValue) / originalGoal.targetValue) * 100

        return CoachingInsight(
            id: UUID().uuidString,
            title: NSLocalizedString("Goal Adjusted", comment: "Goal adjustment insight title"),
            description: String(format: NSLocalizedString("Your %@ goal has been increased by %.1f%% based on your excellent progress!", comment: "Goal adjustment description"), originalGoal.title, improvementPercentage),
            category: .goalManagement,
            confidence: 0.9,
            timestamp: Date(),
            actionable: false,
            relatedGoalId: originalGoal.id
        )
    }

    private func scheduleMotivationalMessageDelivery(_ message: MotivationalMessage) async {
        // In a real implementation, this would integrate with UNUserNotificationCenter
        logger.info("Scheduling motivational message delivery: \(message.content.title)")

        // For now, just mark as delivered immediately
        if let index = motivationalMessages.firstIndex(where: { $0.id == message.id }) {
            motivationalMessages[index].hasBeenDelivered = true
        }
    }
}

// MARK: - Extension for Data Filtering

extension ProcessedHealthData {
    func filterForDate(_ date: Date) -> ProcessedHealthData {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        return ProcessedHealthData(
            sleepData: sleepData.filter { $0.startTime >= startOfDay && $0.startTime < endOfDay },
            activityData: activityData.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            vitalSignData: vitalSignData.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            hydrationData: hydrationData.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            mindfulnessData: mindfulnessData.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            nutritionData: nutritionData.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        )
    }
}