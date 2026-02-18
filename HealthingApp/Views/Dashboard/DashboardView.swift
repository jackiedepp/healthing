//
//  DashboardView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import CareKit
import HealthKit
import os.log

struct DashboardView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @State private var healthMetrics: [HealthMetric] = []
    @State private var recentInsights: [HealthInsight] = []
    @State private var aiInsights: [HealthingInsight] = []
    @State private var coachingSuggestions: [ProactiveHealthSuggestion] = []
    @State private var adaptiveGoals: [AdaptiveGoal] = []
    @State private var isLoading = true
    @State private var selectedTimeRange: TimeRange = .today
    @State private var showingInsightsDetail = false
    @State private var showingCoachingDetail = false

    // AI Service dependencies
    @StateObject private var healthInsightsEngine = HealthInsightsEngine.shared
    @StateObject private var wellnessCoachingEngine: WellnessCoachingEngine
    @StateObject private var personalizedRecommendations: PersonalizedRecommendations

    private let logger = Logger(subsystem: "HealthingApp", category: "DashboardView")

    init() {
        let insights = HealthInsightsEngine.shared
        let patternService = PatternRecognitionService()
        let anomalyService = AnomalyDetectionService()
        let recommendations = PersonalizedRecommendations(
            healthInsightsEngine: insights,
            patternRecognitionService: patternService,
            anomalyDetectionService: anomalyService
        )

        self._personalizedRecommendations = StateObject(wrappedValue: recommendations)
        self._wellnessCoachingEngine = StateObject(wrappedValue: WellnessCoachingEngine(
            healthInsightsEngine: insights,
            personalizedRecommendations: recommendations,
            patternRecognitionService: patternService,
            anomalyDetectionService: anomalyService
        ))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header with greeting
                    HeaderSection(selectedTimeRange: $selectedTimeRange)

                    // AI-powered wellness coaching suggestions
                    if !coachingSuggestions.isEmpty {
                        CoachingSuggestionsSection(
                            suggestions: coachingSuggestions,
                            showingDetail: $showingCoachingDetail
                        )
                    }

                    // Adaptive goals progress
                    if !adaptiveGoals.isEmpty {
                        AdaptiveGoalsSection(goals: adaptiveGoals)
                    }

                    // Quick stats cards with AI insights
                    if !healthMetrics.isEmpty {
                        QuickStatsSection(metrics: healthMetrics, timeRange: selectedTimeRange)
                    }

                    // AI-generated health insights
                    if !aiInsights.isEmpty {
                        AIInsightsSection(
                            insights: aiInsights,
                            showingDetail: $showingInsightsDetail
                        )
                    }

                    // Health trends with pattern recognition
                    HealthTrendsSection(timeRange: selectedTimeRange, aiInsights: aiInsights)

                    // Quick actions enhanced with AI recommendations
                    QuickActionsSection()
                }
                .padding()
            }
            .refreshable {
                await refreshDashboard()
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Open settings or profile
                    }) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadDashboardData()
            }
        }
    }

    private func loadDashboardData() async {
        logger.info("Loading dashboard data with AI insights")
        isLoading = true

        do {
            // Load recent health metrics
            let endDate = Date()
            let startDate = selectedTimeRange.startDate

            let observations = try await dataStore.fetchHealthObservations(
                dateRange: startDate...endDate,
                limit: 50
            )

            // Process into dashboard metrics
            healthMetrics = processHealthMetrics(observations)

            // Load comprehensive health data for AI processing
            let healthData = try await healthInsightsEngine.collectHealthData()

            // Generate AI-powered insights
            aiInsights = try await healthInsightsEngine.generateComprehensiveInsights()

            // Get proactive coaching suggestions
            coachingSuggestions = try await wellnessCoachingEngine.generateProactiveHealthSuggestions(for: healthData)

            // Get adaptive goals
            adaptiveGoals = wellnessCoachingEngine.adaptiveGoals.filter { !$0.isCompleted }

            // Update coaching engine with latest data
            try await wellnessCoachingEngine.updateAdaptiveGoals(with: healthData)

            // Generate legacy insights for compatibility
            recentInsights = generateRecentInsights(from: observations)

        } catch {
            logger.error("Failed to load dashboard data: \(error.localizedDescription)")
            print("Failed to load dashboard data: \(error)")
        }

        isLoading = false
    }

    private func refreshDashboard() async {
        await loadDashboardData()
    }

    private func processHealthMetrics(_ observations: [HealthingObservation]) -> [HealthMetric] {
        var metrics: [HealthMetric] = []

        // Group observations by category
        let grouped = Dictionary(grouping: observations) { observation in
            observation.category.first?.coding?.first?.code?.string ?? "unknown"
        }

        // Process heart rate
        if let heartRateObs = grouped["8867-4"] {
            let values = heartRateObs.compactMap { $0.valueQuantity?.value?.decimal?.doubleValue }
            if !values.isEmpty {
                metrics.append(HealthMetric(
                    id: "heart-rate",
                    title: "Heart Rate",
                    value: "\(Int(values.last ?? 0))",
                    unit: "bpm",
                    trend: calculateTrend(values),
                    icon: "heart.fill",
                    color: .red
                ))
            }
        }

        // Process steps
        if let stepsObs = grouped["55423-8"] {
            let values = stepsObs.compactMap { $0.valueQuantity?.value?.decimal?.doubleValue }
            if !values.isEmpty {
                metrics.append(HealthMetric(
                    id: "steps",
                    title: "Steps",
                    value: "\(Int(values.reduce(0, +)))",
                    unit: "steps",
                    trend: .neutral,
                    icon: "figure.walk",
                    color: .blue
                ))
            }
        }

        // Process active energy
        if let energyObs = grouped["41981-2"] {
            let values = energyObs.compactMap { $0.valueQuantity?.value?.decimal?.doubleValue }
            if !values.isEmpty {
                metrics.append(HealthMetric(
                    id: "active-energy",
                    title: "Active Energy",
                    value: "\(Int(values.reduce(0, +)))",
                    unit: "cal",
                    trend: .neutral,
                    icon: "flame.fill",
                    color: .orange
                ))
            }
        }

        return metrics
    }

    private func generateRecentInsights(from observations: [HealthingObservation]) -> [HealthInsight] {
        // Placeholder for AI-generated insights
        return [
            HealthInsight(
                id: "sleep-trend",
                title: "Sleep Improvement",
                message: "Your sleep quality has improved by 15% this week. Keep up the consistent bedtime routine!",
                category: .sleep,
                priority: .medium,
                timestamp: Date()
            ),
            HealthInsight(
                id: "activity-goal",
                title: "Activity Goal Achieved",
                message: "Congratulations! You've exceeded your daily activity goal 5 days in a row.",
                category: .activity,
                priority: .high,
                timestamp: Date().addingTimeInterval(-3600)
            )
        ]
    }

    private func calculateTrend(_ values: [Double]) -> TrendDirection {
        guard values.count >= 2 else { return .neutral }

        let recent = Array(values.suffix(3))
        let previous = Array(values.prefix(max(1, values.count - 3)))

        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let previousAvg = previous.reduce(0, +) / Double(previous.count)

        let change = (recentAvg - previousAvg) / previousAvg

        if change > 0.05 {
            return .up
        } else if change < -0.05 {
            return .down
        } else {
            return .neutral
        }
    }
}

// MARK: - Header Section

struct HeaderSection: View {
    @Binding var selectedTimeRange: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Here's your health summary")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }
}

// MARK: - Quick Stats Section

struct QuickStatsSection: View {
    let metrics: [HealthMetric]
    let timeRange: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)
                .fontWeight(.semibold)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(metrics.prefix(4)) { metric in
                    HealthMetricCard(metric: metric)
                }
            }
        }
    }
}

struct HealthMetricCard: View {
    let metric: HealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: metric.icon)
                    .foregroundColor(metric.color)
                    .font(.title2)

                Spacer()

                TrendIndicator(trend: metric.trend)
            }

            Text(metric.title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(alignment: .bottom, spacing: 2) {
                Text(metric.value)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(metric.unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Supporting Types

struct HealthMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let trend: TrendDirection
    let icon: String
    let color: Color
}

enum TrendDirection {
    case up, down, neutral
}

struct TrendIndicator: View {
    let trend: TrendDirection

    var body: some View {
        Group {
            switch trend {
            case .up:
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.green)
            case .down:
                Image(systemName: "arrow.down.right")
                    .foregroundColor(.red)
            case .neutral:
                Image(systemName: "minus")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }
}

enum TimeRange: CaseIterable {
    case today, week, month

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        }
    }
}

struct HealthInsight: Identifiable {
    let id: String
    let title: String
    let message: String
    let category: InsightCategory
    let priority: InsightPriority
    let timestamp: Date
}

enum InsightCategory {
    case sleep, activity, nutrition, vital
}

enum InsightPriority {
    case low, medium, high
}

// MARK: - Insights Section

struct InsightsSection: View {
    let insights: [HealthInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Insights")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ForEach(insights.prefix(3)) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }
}

struct InsightCard: View {
    let insight: HealthInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categoryIcon)
                .foregroundColor(categoryColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .fontWeight(.semibold)

                Text(insight.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(insight.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var categoryIcon: String {
        switch insight.category {
        case .sleep: return "bed.double.fill"
        case .activity: return "figure.run"
        case .nutrition: return "leaf.fill"
        case .vital: return "heart.fill"
        }
    }

    private var categoryColor: Color {
        switch insight.category {
        case .sleep: return .purple
        case .activity: return .blue
        case .nutrition: return .green
        case .vital: return .red
        }
    }
}

// MARK: - Health Trends Section

struct HealthTrendsSection: View {
    let timeRange: TimeRange
    let aiInsights: [HealthingInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health Trends")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if hasAITrendInsights {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                        .font(.caption)
                }
            }

            // Enhanced CareKit charts with AI pattern insights
            VStack(spacing: 12) {
                CareKitChartView.heartRateChart(
                    dataPoints: generateHeartRateData(),
                    timeRange: timeRangeInterval
                )
                .frame(height: 180)
                .overlay(alignment: .topTrailing) {
                    if let insight = heartRateInsight {
                        AIInsightBadge(insight: insight)
                    }
                }

                CareKitChartView.stepsChart(
                    dataPoints: generateStepsData(),
                    timeRange: timeRangeInterval
                )
                .frame(height: 180)
                .overlay(alignment: .topTrailing) {
                    if let insight = activityInsight {
                        AIInsightBadge(insight: insight)
                    }
                }

                CareKitChartView.sleepChart(
                    dataPoints: generateSleepData(),
                    timeRange: timeRangeInterval
                )
                .frame(height: 180)
                .overlay(alignment: .topTrailing) {
                    if let insight = sleepInsight {
                        AIInsightBadge(insight: insight)
                    }
                }
            }
        }
    }

    private var hasAITrendInsights: Bool {
        aiInsights.contains { insight in
            insight.category == .vitalSigns || insight.category == .activity || insight.category == .sleep
        }
    }

    private var heartRateInsight: String? {
        aiInsights.first { $0.category == .vitalSigns }?.description
    }

    private var activityInsight: String? {
        aiInsights.first { $0.category == .activity }?.description
    }

    private var sleepInsight: String? {
        aiInsights.first { $0.category == .sleep }?.description
    }

    private var timeRangeInterval: TimeInterval {
        switch timeRange {
        case .today: return 24 * 60 * 60 // 1 day
        case .week: return 7 * 24 * 60 * 60 // 7 days
        case .month: return 30 * 24 * 60 * 60 // 30 days
        }
    }

    // MARK: - Chart Data Generation

    private func generateHeartRateData() -> [ChartDataPoint] {
        let days = timeRange == .today ? 1 : (timeRange == .week ? 7 : 30)
        let calendar = Calendar.current

        return (0..<days).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else {
                return nil
            }

            return ChartDataPoint(
                date: date,
                value: Double.random(in: 65...80),
                label: DateFormatter.shortDate.string(from: date)
            )
        }.sorted { $0.date < $1.date }
    }

    private func generateStepsData() -> [ChartDataPoint] {
        let days = timeRange == .today ? 1 : (timeRange == .week ? 7 : 30)
        let calendar = Calendar.current

        return (0..<days).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else {
                return nil
            }

            return ChartDataPoint(
                date: date,
                value: Double.random(in: 6000...12000),
                label: DateFormatter.shortDate.string(from: date)
            )
        }.sorted { $0.date < $1.date }
    }

    private func generateSleepData() -> [ChartDataPoint] {
        let days = timeRange == .today ? 1 : (timeRange == .week ? 7 : 30)
        let calendar = Calendar.current

        return (0..<days).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else {
                return nil
            }

            return ChartDataPoint(
                date: date,
                value: Double.random(in: 0.6...0.9),
                label: DateFormatter.shortDate.string(from: date)
            )
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - AI Insight Badge

struct AIInsightBadge: View {
    let insight: String

    @StateObject private var accessibilityManager = AccessibilityManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile")
                .font(.caption2)
                .foregroundColor(.white)

            Text("AI")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.purple.gradient)
        )
        .shadow(radius: 2)
        .accessibilityEnhanced(
            label: "AI insight available",
            hint: "Tap to view AI-generated insights for this chart",
            value: insight
        )
    }


// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                QuickActionButton(
                    icon: "plus.circle.fill",
                    title: "Add Measurement",
                    color: .blue
                ) {
                    // Add manual measurement
                }

                QuickActionButton(
                    icon: "doc.badge.plus",
                    title: "Upload Document",
                    color: .green
                ) {
                    // Upload medical document
                }

                QuickActionButton(
                    icon: "applewatch",
                    title: "Sync Devices",
                    color: .purple
                ) {
                    // Sync wearable devices
                }

                QuickActionButton(
                    icon: "chart.xyaxis.line",
                    title: "View Reports",
                    color: .orange
                ) {
                    // View health reports
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - AI-Powered Dashboard Sections

struct CoachingSuggestionsSection: View {
    let suggestions: [ProactiveHealthSuggestion]
    @Binding var showingDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.fill.checkmark")
                    .foregroundColor(.blue)
                Text("Wellness Coaching")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("View All") {
                    showingDetail = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                ForEach(suggestions.prefix(2)) { suggestion in
                    CoachingSuggestionCard(suggestion: suggestion)
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            // Detailed coaching view would be implemented
            NavigationView {
                VStack {
                    Text("Detailed Coaching")
                        .font(.title)
                    Text("Full coaching interface would be here")
                        .foregroundColor(.secondary)
                }
                .navigationTitle("Wellness Coaching")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingDetail = false
                        }
                    }
                }
            }
        }
    }
}

struct CoachingSuggestionCard: View {
    let suggestion: ProactiveHealthSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: urgencyIcon)
                .foregroundColor(urgencyColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(suggestion.title)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(suggestion.estimatedDuration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Text(suggestion.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                if !suggestion.actions.isEmpty {
                    Text("• \(suggestion.actions.first!)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var urgencyIcon: String {
        switch suggestion.urgency {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "lightbulb.fill"
        case .low: return "info.circle.fill"
        }
    }

    private var urgencyColor: Color {
        switch suggestion.urgency {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

struct AdaptiveGoalsSection: View {
    let goals: [AdaptiveGoal]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.green)
                Text("Adaptive Goals")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(completedGoalsCount)/\(goals.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(goals.prefix(3)) { goal in
                    AdaptiveGoalCard(goal: goal)
                }
            }
        }
    }

    private var completedGoalsCount: Int {
        goals.filter { $0.currentProgress >= 1.0 }.count
    }
}

struct AdaptiveGoalCard: View {
    let goal: AdaptiveGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.title)
                    .fontWeight(.semibold)

                Spacer()

                Text(progressPercentage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(progressColor)
            }

            ProgressView(value: goal.currentProgress)
                .tint(progressColor)

            HStack {
                Text(goal.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: adaptationIcon)
                        .font(.caption)
                        .foregroundColor(.purple)
                    Text("Adaptive")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var progressPercentage: String {
        "\(Int(goal.currentProgress * 100))%"
    }

    private var progressColor: Color {
        if goal.currentProgress >= 0.8 {
            return .green
        } else if goal.currentProgress >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    private var adaptationIcon: String {
        switch goal.adaptationStrategy {
        case .gradualIncrease: return "arrow.up.right"
        case .performanceBased: return "chart.line.uptrend.xyaxis"
        case .needsBased: return "person.crop.circle.badge.questionmark"
        }
    }
}

struct AIInsightsSection: View {
    let insights: [HealthingInsight]
    @Binding var showingDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("AI Health Insights")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("View All") {
                    showingDetail = true
                }
                .font(.subheadline)
                .foregroundColor(.purple)
            }

            VStack(spacing: 8) {
                ForEach(insights.prefix(3)) { insight in
                    AIInsightCard(insight: insight)
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            // Detailed AI insights view would be implemented
            NavigationView {
                VStack {
                    Text("AI Health Insights")
                        .font(.title)
                    Text("Detailed AI analysis would be here")
                        .foregroundColor(.secondary)
                }
                .navigationTitle("AI Insights")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingDetail = false
                        }
                    }
                }
            }
        }
    }
}

struct AIInsightCard: View {
    let insight: HealthingInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: categoryIcon)
                    .foregroundColor(priorityColor)
                    .font(.title2)

                if insight.confidence > 0.8 {
                    HStack(spacing: 1) {
                        ForEach(0..<3) { _ in
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 3, height: 3)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(insight.title)
                        .fontWeight(.semibold)

                    Spacer()

                    if insight.actionable {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                Text(insight.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    Text(insight.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Confidence: \(Int(insight.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var categoryIcon: String {
        switch insight.category {
        case .sleep: return "bed.double.fill"
        case .activity: return "figure.run"
        case .vitalSigns: return "heart.fill"
        case .patterns: return "chart.xyaxis.line"
        case .anomalies: return "exclamationmark.triangle.fill"
        case .nutrition: return "leaf.fill"
        case .wellness: return "sparkles"
        case .goals: return "target"
        case .social: return "person.3.fill"
        }
    }

    private var priorityColor: Color {
        switch insight.priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

// MARK: - Extensions

extension ProactiveHealthSuggestion: Identifiable {
    // ProactiveHealthSuggestion already has id property
}

extension AdaptiveGoal: Identifiable {
    // AdaptiveGoal already has id property
}

extension HealthingInsight: Identifiable {
    // HealthInsight already has id property
}

#Preview {
    DashboardView()
        .environmentObject(HealthDataStore.shared)
}