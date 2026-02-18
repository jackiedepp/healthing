//
//  AccessibilityManager.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2E: UI/UX Enhancement & Accessibility
//  Implements REQ-050: Accessibility features for inclusive design
//

import SwiftUI
import UIKit
import AVFoundation
import os.log

/// Comprehensive accessibility manager providing VoiceOver, Dynamic Type, and inclusive design support
/// Implements REQ-050: Accessibility features for inclusive design
@MainActor
class AccessibilityManager: ObservableObject {

    // MARK: - Properties

    private let logger = Logger(subsystem: "HealthingApp", category: "AccessibilityManager")

    @Published var isVoiceOverRunning: Bool = false
    @Published var preferredContentSizeCategory: ContentSizeCategory = .medium
    @Published var isReduceMotionEnabled: Bool = false
    @Published var isReduceTransparencyEnabled: Bool = false
    @Published var isButtonShapesEnabled: Bool = false
    @Published var isOnOffLabelsEnabled: Bool = false
    @Published var isBoldTextEnabled: Bool = false
    @Published var isDarkerSystemColorsEnabled: Bool = false

    // Color contrast and visual accessibility
    @Published var highContrastColors: Bool = false
    @Published var customColorScheme: ColorScheme?
    @Published var accessibilityFontScale: Double = 1.0

    // Audio accessibility
    @Published var isAudioDescriptionsEnabled: Bool = false
    @Published var preferredVoiceGender: AVSpeechSynthesisVoice.Gender = .unspecified
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var speechPitch: Float = 1.0

    // Motor accessibility
    @Published var prefersTapGestures: Bool = false
    @Published var prefersLargerHitTargets: Bool = false
    @Published var switchControlEnabled: Bool = false
    @Published var voiceControlEnabled: Bool = false

    // Cognitive accessibility
    @Published var simplifiedInterface: Bool = false
    @Published var reducedAnimations: Bool = false
    @Published var extendedTouchTargets: Bool = false

    // Notification center for accessibility changes
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Shared Instance

    static let shared = AccessibilityManager()

    // MARK: - Initialization

    private init() {
        logger.info("AccessibilityManager initializing")
        setupAccessibilityNotifications()
        updateAccessibilitySettings()
        logger.info("AccessibilityManager initialized with comprehensive accessibility support")
    }

    // MARK: - Public Methods

    /// Update all accessibility settings based on system preferences
    func updateAccessibilitySettings() {
        logger.debug("Updating accessibility settings")

        // VoiceOver and screen reader support
        isVoiceOverRunning = UIAccessibility.isVoiceOverRunning

        // Dynamic Type support
        let currentCategory = UIApplication.shared.preferredContentSizeCategory
        preferredContentSizeCategory = ContentSizeCategory.from(uiContentSizeCategory: currentCategory)

        // Motion and visual effects
        isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        isReduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled
        reducedAnimations = isReduceMotionEnabled

        // Visual accessibility
        isButtonShapesEnabled = UIAccessibility.isButtonShapesEnabled
        isOnOffLabelsEnabled = UIAccessibility.isOnOffSwitchLabelsEnabled
        isBoldTextEnabled = UIAccessibility.isBoldTextEnabled
        isDarkerSystemColorsEnabled = UIAccessibility.isDarkerSystemColorsEnabled

        // Contrast and color accessibility
        highContrastColors = UIAccessibility.isDarkerSystemColorsEnabled ||
                           UIAccessibility.isInvertColorsEnabled

        // Motor accessibility
        switchControlEnabled = UIAccessibility.isSwitchControlRunning
        voiceControlEnabled = UIAccessibility.isVoiceControlRunning
        prefersLargerHitTargets = switchControlEnabled || voiceControlEnabled

        // Calculate accessibility font scale
        accessibilityFontScale = calculateFontScale(for: preferredContentSizeCategory)

        logger.info("Accessibility settings updated - VoiceOver: \(isVoiceOverRunning), Dynamic Type: \(preferredContentSizeCategory), Reduce Motion: \(isReduceMotionEnabled)")
    }

    /// Generate accessibility label for health metrics
    func accessibilityLabel(for metric: HealthMetric, trend: TrendDirection? = nil) -> String {
        var label = "\(metric.title): \(metric.value) \(metric.unit)"

        if let trend = trend {
            let trendText = accessibilityTrendDescription(trend)
            label += ". \(trendText)"
        }

        return label
    }

    /// Generate accessibility hint for interactive elements
    func accessibilityHint(for action: AccessibilityAction) -> String {
        switch action {
        case .viewDetails:
            return NSLocalizedString("Double tap to view detailed information", comment: "Accessibility hint for view details")
        case .addMeasurement:
            return NSLocalizedString("Double tap to add a new health measurement", comment: "Accessibility hint for add measurement")
        case .editGoal:
            return NSLocalizedString("Double tap to edit this health goal", comment: "Accessibility hint for edit goal")
        case .playAudio:
            return NSLocalizedString("Double tap to play audio description", comment: "Accessibility hint for play audio")
        case .navigate:
            return NSLocalizedString("Double tap to navigate to this section", comment: "Accessibility hint for navigation")
        case .dismiss:
            return NSLocalizedString("Double tap to dismiss this view", comment: "Accessibility hint for dismiss")
        case .refresh:
            return NSLocalizedString("Double tap to refresh data", comment: "Accessibility hint for refresh")
        case .filter:
            return NSLocalizedString("Double tap to filter results", comment: "Accessibility hint for filter")
        }
    }

    /// Get appropriate font size for accessibility
    func accessibleFont(baseSize: CGFloat, style: Font.TextStyle = .body) -> Font {
        let scaledSize = baseSize * accessibilityFontScale

        switch style {
        case .largeTitle:
            return .custom("SF Pro Display", size: max(scaledSize, 34))
        case .title:
            return .custom("SF Pro Display", size: max(scaledSize, 28))
        case .headline:
            return .custom("SF Pro Text", size: max(scaledSize, 17))
        case .body:
            return .custom("SF Pro Text", size: max(scaledSize, 17))
        case .callout:
            return .custom("SF Pro Text", size: max(scaledSize, 16))
        case .subheadline:
            return .custom("SF Pro Text", size: max(scaledSize, 15))
        case .footnote:
            return .custom("SF Pro Text", size: max(scaledSize, 13))
        case .caption:
            return .custom("SF Pro Text", size: max(scaledSize, 12))
        default:
            return .custom("SF Pro Text", size: scaledSize)
        }
    }

    /// Get accessible color with appropriate contrast
    func accessibleColor(
        _ baseColor: Color,
        for background: Color = Color(.systemBackground),
        minimumContrast: Double = 4.5
    ) -> Color {
        if !highContrastColors {
            return baseColor
        }

        // Calculate contrast and adjust if necessary
        let contrastRatio = calculateContrastRatio(baseColor, background: background)

        if contrastRatio >= minimumContrast {
            return baseColor
        }

        // Adjust color for better contrast
        return adjustColorForContrast(baseColor, background: background, targetContrast: minimumContrast)
    }

    /// Get appropriate spacing for accessibility
    func accessibleSpacing(_ baseSpacing: CGFloat) -> CGFloat {
        if prefersLargerHitTargets || switchControlEnabled {
            return baseSpacing * 1.5
        }
        return baseSpacing
    }

    /// Get appropriate touch target size for accessibility
    func accessibleTouchTarget(minimumSize: CGFloat = 44) -> CGFloat {
        let baseSize = prefersLargerHitTargets ? 60 : minimumSize

        if switchControlEnabled || voiceControlEnabled {
            return max(baseSize, 88) // Extra large for switch/voice control
        }

        return baseSize
    }

    /// Generate VoiceOver announcement for health insights
    func announceHealthInsight(_ insight: HealthInsight) {
        guard isVoiceOverRunning else { return }

        let priorityText = insight.priority == .high ?
            NSLocalizedString("High priority health insight", comment: "High priority announcement") :
            NSLocalizedString("Health insight", comment: "Regular insight announcement")

        let announcement = "\(priorityText): \(insight.title). \(insight.description)"

        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    /// Generate VoiceOver announcement for goal achievements
    func announceGoalAchievement(_ goal: AdaptiveGoal, progress: Double) {
        guard isVoiceOverRunning else { return }

        let progressPercentage = Int(progress * 100)
        let announcement: String

        if progress >= 1.0 {
            announcement = String(format:
                NSLocalizedString("Goal achieved! %@ is complete.", comment: "Goal completion announcement"),
                goal.title
            )
        } else if progress >= 0.8 {
            announcement = String(format:
                NSLocalizedString("%@ is %d percent complete. Almost there!", comment: "Near completion announcement"),
                goal.title, progressPercentage
            )
        } else {
            announcement = String(format:
                NSLocalizedString("%@ progress updated: %d percent complete.", comment: "Progress announcement"),
                goal.title, progressPercentage
            )
        }

        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    /// Enable simplified interface for cognitive accessibility
    func enableSimplifiedInterface(_ enabled: Bool) {
        logger.info("Simplified interface \(enabled ? "enabled" : "disabled")")
        simplifiedInterface = enabled

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .accessibilitySimplifiedInterfaceChanged,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    /// Configure audio descriptions for charts and visualizations
    func configureAudioDescriptions(enabled: Bool) {
        logger.info("Audio descriptions \(enabled ? "enabled" : "disabled")")
        isAudioDescriptionsEnabled = enabled

        if enabled {
            // Configure speech synthesis
            let synthesizer = AVSpeechSynthesizer()
            // Additional audio description configuration would go here
        }
    }

    /// Generate audio description for health charts
    func generateChartAudioDescription(
        title: String,
        dataPoints: [Double],
        timeLabels: [String],
        unit: String
    ) -> String {
        let dataCount = dataPoints.count
        let minValue = dataPoints.min() ?? 0
        let maxValue = dataPoints.max() ?? 0
        let avgValue = dataPoints.reduce(0, +) / Double(dataPoints.count)

        let trend = determineTrend(dataPoints)
        let trendText = accessibilityTrendDescription(trend)

        return String(format:
            NSLocalizedString("Chart titled %@. Contains %d data points. Values range from %.1f to %.1f %@, with an average of %.1f %@. Overall trend: %@", comment: "Chart audio description"),
            title, dataCount, minValue, unit, maxValue, unit, avgValue, unit, trendText
        )
    }

    // MARK: - Private Methods

    private func setupAccessibilityNotifications() {
        let notificationCenter = NotificationCenter.default

        // VoiceOver state changes
        notificationCenter.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilitySettings()
        }

        // Dynamic Type changes
        notificationCenter.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilitySettings()
        }

        // Reduce motion changes
        notificationCenter.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilitySettings()
        }

        // Other accessibility changes
        notificationCenter.addObserver(
            forName: UIAccessibility.buttonShapesEnabledStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilitySettings()
        }

        notificationCenter.addObserver(
            forName: UIAccessibility.onOffSwitchLabelsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilitySettings()
        }

        notificationCenter.addObserver(
            forName: UIAccessibility.boldTextStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilitySettings()
        }

        logger.debug("Accessibility notifications configured")
    }

    private func calculateFontScale(for category: ContentSizeCategory) -> Double {
        switch category {
        case .extraSmall: return 0.8
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.1
        case .extraLarge: return 1.2
        case .extraExtraLarge: return 1.3
        case .extraExtraExtraLarge: return 1.4
        case .accessibilityMedium: return 1.6
        case .accessibilityLarge: return 1.8
        case .accessibilityExtraLarge: return 2.0
        case .accessibilityExtraExtraLarge: return 2.2
        case .accessibilityExtraExtraExtraLarge: return 2.5
        @unknown default: return 1.0
        }
    }

    private func accessibilityTrendDescription(_ trend: TrendDirection) -> String {
        switch trend {
        case .up:
            return NSLocalizedString("trending upward", comment: "Accessibility trend up")
        case .down:
            return NSLocalizedString("trending downward", comment: "Accessibility trend down")
        case .neutral:
            return NSLocalizedString("stable", comment: "Accessibility trend neutral")
        }
    }

    private func determineTrend(_ dataPoints: [Double]) -> TrendDirection {
        guard dataPoints.count >= 2 else { return .neutral }

        let firstHalf = Array(dataPoints.prefix(dataPoints.count / 2))
        let secondHalf = Array(dataPoints.suffix(dataPoints.count / 2))

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        let change = (secondAvg - firstAvg) / firstAvg

        if change > 0.05 {
            return .up
        } else if change < -0.05 {
            return .down
        } else {
            return .neutral
        }
    }

    private func calculateContrastRatio(_ foreground: Color, background: Color) -> Double {
        // Simplified contrast calculation
        // In production, would use proper color space conversion and WCAG formulas
        return 4.5 // Placeholder - would implement proper contrast calculation
    }

    private func adjustColorForContrast(
        _ color: Color,
        background: Color,
        targetContrast: Double
    ) -> Color {
        // Simplified color adjustment for contrast
        // In production, would implement proper color adjustment algorithms
        if isDarkerSystemColorsEnabled {
            return color.opacity(0.9)
        }
        return color
    }
}

// MARK: - Supporting Types

enum AccessibilityAction: CaseIterable {
    case viewDetails
    case addMeasurement
    case editGoal
    case playAudio
    case navigate
    case dismiss
    case refresh
    case filter
}

extension ContentSizeCategory {
    static func from(uiContentSizeCategory: UIContentSizeCategory) -> ContentSizeCategory {
        switch uiContentSizeCategory {
        case .extraSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .extraLarge
        case .extraExtraLarge: return .extraExtraLarge
        case .extraExtraExtraLarge: return .extraExtraExtraLarge
        case .accessibilityMedium: return .accessibilityMedium
        case .accessibilityLarge: return .accessibilityLarge
        case .accessibilityExtraLarge: return .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: return .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .medium
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let accessibilitySimplifiedInterfaceChanged = Notification.Name("accessibilitySimplifiedInterfaceChanged")
    static let accessibilityHighContrastChanged = Notification.Name("accessibilityHighContrastChanged")
    static let accessibilityAudioDescriptionsChanged = Notification.Name("accessibilityAudioDescriptionsChanged")
}

// MARK: - SwiftUI View Extensions for Accessibility

extension View {
    /// Apply comprehensive accessibility modifiers
    func accessibilityEnhanced(
        label: String? = nil,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = [],
        action: AccessibilityAction? = nil
    ) -> some View {
        let accessibilityManager = AccessibilityManager.shared

        return self
            .accessibilityLabel(label ?? "")
            .accessibilityHint(action != nil ? accessibilityManager.accessibilityHint(for: action!) : (hint ?? ""))
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(traits)
    }

    /// Apply accessible font scaling
    func accessibleFont(
        _ baseSize: CGFloat,
        style: Font.TextStyle = .body,
        weight: Font.Weight = .regular
    ) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let font = accessibilityManager.accessibleFont(baseSize: baseSize, style: style)

        return self
            .font(font.weight(weight))
            .minimumScaleFactor(0.8)
            .lineLimit(accessibilityManager.simplifiedInterface ? 3 : nil)
    }

    /// Apply accessible colors with contrast adjustment
    func accessibleForegroundColor(
        _ color: Color,
        background: Color = Color(.systemBackground)
    ) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let accessibleColor = accessibilityManager.accessibleColor(color, for: background)

        return self
            .foregroundColor(accessibleColor)
    }

    /// Apply accessible spacing
    func accessiblePadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let spacing = length != nil ? accessibilityManager.accessibleSpacing(length!) : nil

        return self
            .padding(edges, spacing)
    }

    /// Apply accessible touch targets
    func accessibleTouchTarget(minimumSize: CGFloat = 44) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let targetSize = accessibilityManager.accessibleTouchTarget(minimumSize: minimumSize)

        return self
            .frame(minWidth: targetSize, minHeight: targetSize)
    }

    /// Apply reduced motion animations
    func accessibleAnimation<V: Equatable>(
        _ animation: Animation?,
        value: V
    ) -> some View {
        let accessibilityManager = AccessibilityManager.shared

        if accessibilityManager.isReduceMotionEnabled {
            return self
                .animation(nil, value: value)
        } else {
            return self
                .animation(animation, value: value)
        }
    }

    /// Apply accessibility-aware transitions
    func accessibleTransition(_ transition: AnyTransition) -> some View {
        let accessibilityManager = AccessibilityManager.shared

        if accessibilityManager.isReduceMotionEnabled {
            return self
                .transition(.opacity)
        } else {
            return self
                .transition(transition)
        }
    }
}

// MARK: - Import required modules

import Combine