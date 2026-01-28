//
//  ProgressCelebrationService.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2F: Consumer Features & Gamification
//  Implements REQ-076: Achievement badges and progress celebrations
//  Handles milestone celebrations and user motivation
//

import SwiftUI
import AVFoundation
import UserNotifications
import os.log

/// Service for celebrating user progress and providing motivational feedback
/// Implements REQ-076: Achievement badges and progress celebrations
@MainActor
class ProgressCelebrationService: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "HealthingApp", category: "ProgressCelebrationService")

    @Published var currentCelebration: CelebrationEvent?
    @Published var celebrationQueue: [CelebrationEvent] = []
    @Published var isShowingCelebration = false
    @Published var motivationalQuotes: [MotivationalQuote] = []
    @Published var celebrationHistory: [CelebrationEvent] = []

    // Celebration settings
    @Published var celebrationPreferences = CelebrationPreferences()
    @Published var lastCelebrationTime: Date?

    // Animation and effects
    private var hapticFeedback = UIImpactFeedbackGenerator()
    private var audioPlayer: AVAudioPlayer?
    private let celebrationCooldown: TimeInterval = 60 // 1 minute between celebrations

    // Dependencies
    private let accessibilityManager = AccessibilityManager.shared
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Shared Instance

    static let shared = ProgressCelebrationService()

    // MARK: - Initialization

    private init() {
        logger.info("ProgressCelebrationService initialized")
        loadCelebrationPreferences()
        loadMotivationalQuotes()
        setupNotificationObservers()
    }

    // MARK: - Public Methods

    /// Trigger a celebration for an achievement
    func celebrateAchievement(_ achievement: Achievement, levelUp: Bool = false) async {
        logger.info("Celebrating achievement: \(achievement.title)")

        let celebration = CelebrationEvent(
            id: UUID().uuidString,
            type: .achievement,
            title: achievement.title,
            description: achievement.description,
            achievement: achievement,
            levelUp: levelUp,
            timestamp: Date(),
            celebrationStyle: determineCelebrationStyle(for: achievement)
        )

        await enqueueCelebration(celebration)
    }

    /// Trigger a celebration for goal completion
    func celebrateGoalCompletion(_ goal: HealthGoal) async {
        logger.info("Celebrating goal completion: \(goal.title)")

        let celebration = CelebrationEvent(
            id: UUID().uuidString,
            type: .goalCompletion,
            title: NSLocalizedString("Goal Completed!", comment: "Goal completion celebration title"),
            description: String(format: NSLocalizedString("You've successfully completed '%@'", comment: "Goal completion description"), goal.title),
            goal: goal,
            timestamp: Date(),
            celebrationStyle: .enthusiastic
        )

        await enqueueCelebration(celebration)
    }

    /// Trigger a celebration for milestone progress
    func celebrateMilestone(_ milestone: ProgressMilestone) async {
        logger.info("Celebrating milestone: \(milestone.title)")

        let celebration = CelebrationEvent(
            id: UUID().uuidString,
            type: .milestone,
            title: milestone.title,
            description: milestone.description,
            milestone: milestone,
            timestamp: Date(),
            celebrationStyle: .proud
        )

        await enqueueCelebration(celebration)
    }

    /// Trigger a celebration for streak achievements
    func celebrateStreak(_ streak: StreakData, type: StreakType) async {
        logger.info("Celebrating \(streak.days) day \(type) streak")

        let title = String(format: NSLocalizedString("%d Day Streak!", comment: "Streak celebration title"), streak.days)
        let description = generateStreakDescription(streak, type: type)

        let celebration = CelebrationEvent(
            id: UUID().uuidString,
            type: .streak,
            title: title,
            description: description,
            streak: streak,
            timestamp: Date(),
            celebrationStyle: .energetic
        )

        await enqueueCelebration(celebration)
    }

    /// Trigger a celebration for personal records
    func celebratePersonalRecord(_ record: PersonalRecord) async {
        logger.info("Celebrating personal record: \(record.metric)")

        let celebration = CelebrationEvent(
            id: UUID().uuidString,
            type: .personalRecord,
            title: NSLocalizedString("New Personal Record!", comment: "Personal record celebration title"),
            description: String(format: NSLocalizedString("You set a new record with %@ %@!", comment: "Personal record description"),
                               formatValue(record.value), record.unit),
            personalRecord: record,
            timestamp: Date(),
            celebrationStyle: .triumphant
        )

        await enqueueCelebration(celebration)
    }

    /// Show the next celebration in queue
    func showNextCelebration() {
        guard !isShowingCelebration, !celebrationQueue.isEmpty else { return }
        guard canShowCelebration() else { return }

        currentCelebration = celebrationQueue.removeFirst()
        isShowingCelebration = true
        lastCelebrationTime = Date()

        if let celebration = currentCelebration {
            performCelebrationEffects(celebration)
            saveCelebrationToHistory(celebration)
        }
    }

    /// Dismiss the current celebration
    func dismissCelebration() {
        logger.debug("Dismissing current celebration")

        isShowingCelebration = false
        currentCelebration = nil

        // Auto-show next celebration after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.showNextCelebration()
        }
    }

    /// Get a random motivational quote
    func getMotivationalQuote(for context: MotivationalContext = .general) -> MotivationalQuote? {
        let relevantQuotes = motivationalQuotes.filter { $0.context == context || $0.context == .general }
        return relevantQuotes.randomElement()
    }

    /// Update celebration preferences
    func updateCelebrationPreferences(_ preferences: CelebrationPreferences) {
        celebrationPreferences = preferences
        saveCelebrationPreferences()

        logger.info("Celebration preferences updated: sounds=\(preferences.enableSounds), haptics=\(preferences.enableHaptics)")
    }

    /// Get celebration statistics
    func getCelebrationStatistics() -> CelebrationStatistics {
        let totalCelebrations = celebrationHistory.count
        let achievementCelebrations = celebrationHistory.filter { $0.type == .achievement }.count
        let goalCelebrations = celebrationHistory.filter { $0.type == .goalCompletion }.count
        let streakCelebrations = celebrationHistory.filter { $0.type == .streak }.count

        let recentCelebrations = celebrationHistory.filter {
            $0.timestamp.timeIntervalSinceNow > -24 * 60 * 60 // Last 24 hours
        }.count

        return CelebrationStatistics(
            totalCelebrations: totalCelebrations,
            achievementCelebrations: achievementCelebrations,
            goalCelebrations: goalCelebrations,
            streakCelebrations: streakCelebrations,
            recentCelebrations: recentCelebrations
        )
    }

    // MARK: - Private Methods

    private func enqueueCelebration(_ celebration: CelebrationEvent) async {
        logger.debug("Enqueueing celebration: \(celebration.title)")

        celebrationQueue.append(celebration)

        // Auto-show if no celebration is currently displaying
        if !isShowingCelebration {
            showNextCelebration()
        }
    }

    private func canShowCelebration() -> Bool {
        // Check cooldown period
        if let lastTime = lastCelebrationTime,
           Date().timeIntervalSince(lastTime) < celebrationCooldown {
            return false
        }

        // Check user preferences
        if !celebrationPreferences.enableCelebrations {
            return false
        }

        // Check accessibility settings
        if accessibilityManager.isReduceMotionEnabled && !celebrationPreferences.respectReduceMotion {
            return false
        }

        return true
    }

    private func performCelebrationEffects(_ celebration: CelebrationEvent) {
        logger.debug("Performing celebration effects for: \(celebration.title)")

        // Haptic feedback
        if celebrationPreferences.enableHaptics {
            performHapticFeedback(for: celebration.celebrationStyle)
        }

        // Sound effects
        if celebrationPreferences.enableSounds {
            playCelebrationSound(for: celebration.celebrationStyle)
        }

        // Accessibility announcements
        if accessibilityManager.isVoiceOverRunning {
            announceForAccessibility(celebration)
        }

        // Visual effects are handled by the UI layer
    }

    private func performHapticFeedback(for style: CelebrationStyle) {
        switch style {
        case .subtle:
            let lightImpact = UIImpactFeedbackGenerator(style: .light)
            lightImpact.impactOccurred()

        case .enthusiastic, .energetic:
            let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
            mediumImpact.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                mediumImpact.impactOccurred()
            }

        case .triumphant, .proud:
            let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
            heavyImpact.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
                mediumImpact.impactOccurred()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let lightImpact = UIImpactFeedbackGenerator(style: .light)
                lightImpact.impactOccurred()
            }
        }
    }

    private func playCelebrationSound(for style: CelebrationStyle) {
        guard let soundFileName = getSoundFileName(for: style) else { return }

        guard let soundURL = Bundle.main.url(forResource: soundFileName, withExtension: "m4a") else {
            logger.warning("Celebration sound file not found: \(soundFileName)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.volume = celebrationPreferences.soundVolume
            audioPlayer?.play()
        } catch {
            logger.error("Failed to play celebration sound: \(error.localizedDescription)")
        }
    }

    private func getSoundFileName(for style: CelebrationStyle) -> String? {
        switch style {
        case .subtle: return "subtle_chime"
        case .enthusiastic: return "enthusiastic_fanfare"
        case .energetic: return "energetic_bells"
        case .triumphant: return "triumphant_horns"
        case .proud: return "proud_applause"
        }
    }

    private func announceForAccessibility(_ celebration: CelebrationEvent) {
        let announcement: String

        switch celebration.type {
        case .achievement:
            announcement = String(format: NSLocalizedString("Achievement unlocked: %@. %@", comment: "Achievement accessibility announcement"),
                                 celebration.title, celebration.description)
        case .goalCompletion:
            announcement = String(format: NSLocalizedString("Goal completed: %@", comment: "Goal completion accessibility announcement"),
                                 celebration.description)
        case .milestone:
            announcement = String(format: NSLocalizedString("Milestone reached: %@. %@", comment: "Milestone accessibility announcement"),
                                 celebration.title, celebration.description)
        case .streak:
            announcement = String(format: NSLocalizedString("Streak achievement: %@. %@", comment: "Streak accessibility announcement"),
                                 celebration.title, celebration.description)
        case .personalRecord:
            announcement = String(format: NSLocalizedString("Personal record: %@. %@", comment: "Personal record accessibility announcement"),
                                 celebration.title, celebration.description)
        }

        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private func determineCelebrationStyle(for achievement: Achievement) -> CelebrationStyle {
        switch achievement.badge.rarity {
        case .common:
            return .subtle
        case .uncommon:
            return .enthusiastic
        case .rare:
            return .energetic
        case .epic:
            return .triumphant
        case .legendary, .special:
            return .proud
        }
    }

    private func generateStreakDescription(_ streak: StreakData, type: StreakType) -> String {
        let typeDescription: String
        switch type {
        case .steps:
            typeDescription = NSLocalizedString("daily step goal", comment: "Steps streak description")
        case .sleep:
            typeDescription = NSLocalizedString("quality sleep", comment: "Sleep streak description")
        case .consistency:
            typeDescription = NSLocalizedString("health tracking", comment: "Consistency streak description")
        case .app:
            typeDescription = NSLocalizedString("app usage", comment: "App streak description")
        }

        return String(format: NSLocalizedString("You've maintained your %@ for %d consecutive days! Keep up the excellent work.", comment: "Streak description"),
                     typeDescription, streak.days)
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func saveCelebrationToHistory(_ celebration: CelebrationEvent) {
        celebrationHistory.append(celebration)

        // Keep only last 100 celebrations
        if celebrationHistory.count > 100 {
            celebrationHistory.removeFirst(celebrationHistory.count - 100)
        }

        // Save to persistent storage
        saveCelebrationHistory()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .achievementUnlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let achievement = notification.object as? Achievement else { return }

            let leveledUp = notification.userInfo?["leveledUp"] as? Bool ?? false

            Task {
                await self.celebrateAchievement(achievement, levelUp: leveledUp)
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.accessibilityManager.updateAccessibilitySettings()
        }
    }

    private func loadMotivationalQuotes() {
        motivationalQuotes = [
            // General motivation
            MotivationalQuote(
                text: NSLocalizedString("Every step forward is progress, no matter how small.", comment: "Motivational quote"),
                author: NSLocalizedString("Health Wisdom", comment: "Quote author"),
                context: .general
            ),
            MotivationalQuote(
                text: NSLocalizedString("Your health is an investment, not an expense.", comment: "Motivational quote"),
                author: NSLocalizedString("Wellness Guide", comment: "Quote author"),
                context: .general
            ),

            // Achievement specific
            MotivationalQuote(
                text: NSLocalizedString("Success is the sum of small efforts repeated day in and day out.", comment: "Achievement quote"),
                author: NSLocalizedString("R. Collier", comment: "Quote author"),
                context: .achievement
            ),
            MotivationalQuote(
                text: NSLocalizedString("You are stronger than you believe and more capable than you imagine.", comment: "Achievement quote"),
                author: NSLocalizedString("Health Champion", comment: "Quote author"),
                context: .achievement
            ),

            // Goal completion
            MotivationalQuote(
                text: NSLocalizedString("The only impossible journey is the one you never begin.", comment: "Goal quote"),
                author: NSLocalizedString("Tony Robbins", comment: "Quote author"),
                context: .goalCompletion
            ),
            MotivationalQuote(
                text: NSLocalizedString("Celebrating small victories leads to big achievements.", comment: "Goal quote"),
                author: NSLocalizedString("Wellness Mentor", comment: "Quote author"),
                context: .goalCompletion
            ),

            // Milestones
            MotivationalQuote(
                text: NSLocalizedString("Great things never come from comfort zones.", comment: "Milestone quote"),
                author: NSLocalizedString("Life Coach", comment: "Quote author"),
                context: .milestone
            ),
            MotivationalQuote(
                text: NSLocalizedString("Progress, not perfection, is the goal.", comment: "Milestone quote"),
                author: NSLocalizedString("Health Guide", comment: "Quote author"),
                context: .milestone
            ),

            // Streaks
            MotivationalQuote(
                text: NSLocalizedString("Consistency is the key to achieving extraordinary results.", comment: "Streak quote"),
                author: NSLocalizedString("Success Coach", comment: "Quote author"),
                context: .streak
            ),
            MotivationalQuote(
                text: NSLocalizedString("Habits are the building blocks of excellence.", comment: "Streak quote"),
                author: NSLocalizedString("Habit Expert", comment: "Quote author"),
                context: .streak
            )
        ]
    }

    private func loadCelebrationPreferences() {
        if let data = UserDefaults.standard.data(forKey: "celebration_preferences") {
            do {
                celebrationPreferences = try JSONDecoder().decode(CelebrationPreferences.self, from: data)
            } catch {
                logger.error("Failed to load celebration preferences: \(error.localizedDescription)")
                celebrationPreferences = CelebrationPreferences() // Use defaults
            }
        }
    }

    private func saveCelebrationPreferences() {
        do {
            let data = try JSONEncoder().encode(celebrationPreferences)
            UserDefaults.standard.set(data, forKey: "celebration_preferences")
        } catch {
            logger.error("Failed to save celebration preferences: \(error.localizedDescription)")
        }
    }

    private func saveCelebrationHistory() {
        do {
            let data = try JSONEncoder().encode(celebrationHistory)
            UserDefaults.standard.set(data, forKey: "celebration_history")
        } catch {
            logger.error("Failed to save celebration history: \(error.localizedDescription)")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Supporting Data Structures

struct CelebrationEvent: Identifiable, Codable {
    let id: String
    let type: CelebrationType
    let title: String
    let description: String
    let achievement: Achievement?
    let goal: HealthGoal?
    let milestone: ProgressMilestone?
    let streak: StreakData?
    let personalRecord: PersonalRecord?
    let levelUp: Bool
    let timestamp: Date
    let celebrationStyle: CelebrationStyle

    init(id: String, type: CelebrationType, title: String, description: String,
         achievement: Achievement? = nil, goal: HealthGoal? = nil, milestone: ProgressMilestone? = nil,
         streak: StreakData? = nil, personalRecord: PersonalRecord? = nil, levelUp: Bool = false,
         timestamp: Date, celebrationStyle: CelebrationStyle) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.achievement = achievement
        self.goal = goal
        self.milestone = milestone
        self.streak = streak
        self.personalRecord = personalRecord
        self.levelUp = levelUp
        self.timestamp = timestamp
        self.celebrationStyle = celebrationStyle
    }
}

enum CelebrationType: String, Codable {
    case achievement
    case goalCompletion
    case milestone
    case streak
    case personalRecord

    var displayName: String {
        switch self {
        case .achievement: return NSLocalizedString("Achievement", comment: "Achievement celebration type")
        case .goalCompletion: return NSLocalizedString("Goal Completion", comment: "Goal completion celebration type")
        case .milestone: return NSLocalizedString("Milestone", comment: "Milestone celebration type")
        case .streak: return NSLocalizedString("Streak", comment: "Streak celebration type")
        case .personalRecord: return NSLocalizedString("Personal Record", comment: "Personal record celebration type")
        }
    }

    var icon: String {
        switch self {
        case .achievement: return "star.fill"
        case .goalCompletion: return "checkmark.circle.fill"
        case .milestone: return "flag.fill"
        case .streak: return "flame.fill"
        case .personalRecord: return "crown.fill"
        }
    }

    var color: Color {
        switch self {
        case .achievement: return .yellow
        case .goalCompletion: return .green
        case .milestone: return .blue
        case .streak: return .orange
        case .personalRecord: return .purple
        }
    }
}

enum CelebrationStyle: String, Codable {
    case subtle
    case enthusiastic
    case energetic
    case triumphant
    case proud

    var animationDuration: TimeInterval {
        switch self {
        case .subtle: return 1.5
        case .enthusiastic: return 2.0
        case .energetic: return 2.5
        case .triumphant: return 3.0
        case .proud: return 3.5
        }
    }

    var particles: Int {
        switch self {
        case .subtle: return 10
        case .enthusiastic: return 25
        case .energetic: return 40
        case .triumphant: return 60
        case .proud: return 80
        }
    }
}

struct ProgressMilestone: Codable {
    let id: String
    let title: String
    let description: String
    let metric: String
    let value: Double
    let unit: String
    let category: String
    let achievedDate: Date
}

struct PersonalRecord: Codable {
    let id: String
    let metric: String
    let value: Double
    let unit: String
    let previousRecord: Double?
    let improvementPercent: Double
    let achievedDate: Date
}

struct MotivationalQuote: Codable {
    let text: String
    let author: String
    let context: MotivationalContext
}

enum MotivationalContext: String, CaseIterable, Codable {
    case general
    case achievement
    case goalCompletion
    case milestone
    case streak

    var displayName: String {
        switch self {
        case .general: return NSLocalizedString("General", comment: "General motivation context")
        case .achievement: return NSLocalizedString("Achievement", comment: "Achievement motivation context")
        case .goalCompletion: return NSLocalizedString("Goal Completion", comment: "Goal completion motivation context")
        case .milestone: return NSLocalizedString("Milestone", comment: "Milestone motivation context")
        case .streak: return NSLocalizedString("Streak", comment: "Streak motivation context")
        }
    }
}

struct CelebrationPreferences: Codable {
    var enableCelebrations: Bool = true
    var enableSounds: Bool = true
    var enableHaptics: Bool = true
    var respectReduceMotion: Bool = true
    var soundVolume: Float = 0.7
    var autoShowCelebrations: Bool = true
    var celebrationDuration: TimeInterval = 3.0

    var minimumAchievementRarity: AchievementBadge.BadgeRarity = .common
    var enableMilestones: Bool = true
    var enableStreaks: Bool = true
    var enablePersonalRecords: Bool = true
}

struct CelebrationStatistics {
    let totalCelebrations: Int
    let achievementCelebrations: Int
    let goalCelebrations: Int
    let streakCelebrations: Int
    let recentCelebrations: Int
}

// MARK: - Celebration View Modifier

struct CelebrationModifier: ViewModifier {
    @StateObject private var celebrationService = ProgressCelebrationService.shared
    @State private var showingCelebrationView = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if celebrationService.isShowingCelebration,
                       let celebration = celebrationService.currentCelebration {
                        CelebrationOverlay(
                            celebration: celebration,
                            onDismiss: {
                                celebrationService.dismissCelebration()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
            )
            .onAppear {
                celebrationService.showNextCelebration()
            }
    }
}

// MARK: - Celebration Overlay

struct CelebrationOverlay: View {
    let celebration: CelebrationEvent
    let onDismiss: () -> Void

    @StateObject private var accessibilityManager = AccessibilityManager.shared
    @State private var animationScale: CGFloat = 0.1
    @State private var animationOpacity: Double = 0.0
    @State private var particlesVisible = false

    var body: some View {
        ZStack {
            // Background overlay
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Celebration content
            VStack(spacing: accessibilityManager.accessibleSpacing(20)) {
                // Celebration icon
                Image(systemName: celebration.type.icon)
                    .accessibleFont(60, style: .largeTitle)
                    .accessibleForegroundColor(celebration.type.color)
                    .scaleEffect(animationScale)
                    .opacity(animationOpacity)

                // Title and description
                VStack(spacing: accessibilityManager.accessibleSpacing(8)) {
                    Text(celebration.title)
                        .accessibleFont(24, style: .title, weight: .bold)
                        .multilineTextAlignment(.center)

                    Text(celebration.description)
                        .accessibleFont(16, style: .body)
                        .accessibleForegroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessiblePadding(.horizontal, 20)
                }
                .opacity(animationOpacity)

                // Level up indicator if applicable
                if celebration.levelUp {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .accessibleForegroundColor(.yellow)

                        Text("Level Up!")
                            .accessibleFont(18, style: .headline, weight: .semibold)
                            .accessibleForegroundColor(.yellow)
                    }
                    .opacity(animationOpacity)
                    .scaleEffect(animationScale)
                }

                // Dismiss button
                Button(action: onDismiss) {
                    Text("Continue")
                        .accessibleFont(17, style: .body, weight: .medium)
                        .foregroundColor(.white)
                        .accessiblePadding(.horizontal, 30)
                        .accessiblePadding(.vertical, 12)
                        .background(celebration.type.color)
                        .clipShape(Capsule())
                }
                .opacity(animationOpacity)
                .accessibilityEnhanced(
                    label: "Continue",
                    hint: "Dismiss this celebration and continue using the app",
                    action: .dismiss
                )
                .accessibleTouchTarget()
            }
            .accessiblePadding(.all, 40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 10)
            )
            .scaleEffect(animationScale)

            // Particle effect overlay
            if particlesVisible && !accessibilityManager.isReduceMotionEnabled {
                ParticleEffect(
                    style: celebration.celebrationStyle,
                    color: celebration.type.color
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityEnhanced(
            label: "Celebration: \(celebration.title). \(celebration.description)",
            hint: "Tap anywhere to dismiss this celebration"
        )
        .onAppear {
            startCelebrationAnimation()
        }
    }

    private func startCelebrationAnimation() {
        // Main content animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            animationScale = 1.0
            animationOpacity = 1.0
        }

        // Particle effect delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.5)) {
                particlesVisible = true
            }
        }

        // Auto-dismiss after duration
        let duration = celebration.celebrationStyle.animationDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 2.0) {
            if ProgressCelebrationService.shared.celebrationPreferences.autoShowCelebrations {
                onDismiss()
            }
        }
    }
}

// MARK: - Particle Effect

struct ParticleEffect: View {
    let style: CelebrationStyle
    let color: Color

    @State private var particles: [Particle] = []
    @State private var animationActive = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                        .scaleEffect(particle.scale)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            generateParticles()
            startAnimation()
        }
    }

    private func generateParticles() {
        particles = (0..<style.particles).map { _ in
            Particle(
                color: [color, color.opacity(0.7), .white].randomElement() ?? color,
                size: Double.random(in: 4...12),
                x: Double.random(in: 0...UIScreen.main.bounds.width),
                y: UIScreen.main.bounds.height + 50,
                opacity: Double.random(in: 0.6...1.0),
                scale: Double.random(in: 0.5...1.0)
            )
        }
    }

    private func startAnimation() {
        withAnimation(.easeOut(duration: style.animationDuration)) {
            for i in particles.indices {
                particles[i].y = -50
                particles[i].opacity = 0
            }
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    let color: Color
    let size: Double
    var x: Double
    var y: Double
    var opacity: Double
    var scale: Double
}

// MARK: - View Extension

extension View {
    func withCelebrations() -> some View {
        self.modifier(CelebrationModifier())
    }
}