//
//  HealthMetricCard.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2E: UI/UX Enhancement & Accessibility
//  Reusable metric display components with accessibility support
//

import SwiftUI
import CareKit
import os.log

/// Reusable health metric display card with comprehensive accessibility support
struct HealthMetricCard: View {

    // MARK: - Properties

    let metric: HealthMetric
    let style: CardStyle
    let showTrend: Bool
    let showChart: Bool
    let onTap: (() -> Void)?

    @StateObject private var accessibilityManager = AccessibilityManager.shared
    private let logger = Logger(subsystem: "HealthingApp", category: "HealthMetricCard")

    // MARK: - Initialization

    init(
        metric: HealthMetric,
        style: CardStyle = .standard,
        showTrend: Bool = true,
        showChart: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.metric = metric
        self.style = style
        self.showTrend = showTrend
        self.showChart = showChart
        self.onTap = onTap
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap ?? {}) {
            VStack(alignment: .leading, spacing: accessibilityManager.accessibleSpacing(8)) {
                // Header with icon and trend
                headerSection

                // Main value display
                valueSection

                // Optional chart section
                if showChart && metric.chartData?.isEmpty == false {
                    chartSection
                }

                // Optional status or additional info
                if let status = metric.status {
                    statusSection(status)
                }
            }
            .accessiblePadding(.all, style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
            .shadow(
                color: accessibilityManager.highContrastColors ? .clear : Color.black.opacity(0.1),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowOffset
            )
        }
        .buttonStyle(MetricCardButtonStyle())
        .accessibilityEnhanced(
            label: accessibilityLabel,
            hint: accessibilityHint,
            value: accessibilityValue,
            action: onTap != nil ? .viewDetails : nil
        )
        .accessibleTouchTarget()
    }

    // MARK: - View Components

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            // Metric icon
            Image(systemName: metric.icon)
                .accessibleFont(style.iconSize, style: .title2)
                .accessibleForegroundColor(metric.color)
                .accessibilityHidden(true)

            // Title
            Text(metric.title)
                .accessibleFont(style.titleSize, style: .subheadline, weight: .medium)
                .accessibleForegroundColor(.primary)
                .lineLimit(accessibilityManager.simplifiedInterface ? 1 : 2)

            Spacer()

            // Trend indicator
            if showTrend {
                TrendIndicator(
                    trend: metric.trend,
                    style: style,
                    accessibilityManager: accessibilityManager
                )
            }
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        HStack(alignment: .lastTextBaseline, spacing: accessibilityManager.accessibleSpacing(4)) {
            // Main value
            Text(metric.value)
                .accessibleFont(style.valueSize, style: .title2, weight: .bold)
                .accessibleForegroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Unit
            Text(metric.unit)
                .accessibleFont(style.unitSize, style: .caption, weight: .medium)
                .accessibleForegroundColor(.secondary)
                .accessibilityHidden(true) // Included in main accessibility label
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if let chartData = metric.chartData, !chartData.isEmpty {
            MiniChart(
                dataPoints: chartData,
                color: metric.color,
                style: style,
                accessibilityManager: accessibilityManager
            )
            .frame(height: style.chartHeight)
            .accessibilityHidden(true) // Chart data included in card accessibility
        }
    }

    @ViewBuilder
    private func statusSection(_ status: HealthMetricStatus) -> some View {
        HStack(spacing: accessibilityManager.accessibleSpacing(4)) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(status.text)
                .accessibleFont(style.statusSize, style: .caption2, weight: .medium)
                .accessibleForegroundColor(status.color)
                .lineLimit(1)
        }
    }

    // MARK: - Computed Properties

    private var backgroundStyle: some View {
        Group {
            if accessibilityManager.highContrastColors {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    .background(Color(.systemBackground))
            } else {
                Color(style.backgroundColor)
            }
        }
    }

    private var accessibilityLabel: String {
        accessibilityManager.accessibilityLabel(for: metric, trend: showTrend ? metric.trend : nil)
    }

    private var accessibilityHint: String? {
        onTap != nil ?
            NSLocalizedString("Double tap to view detailed information about this health metric", comment: "Health metric accessibility hint") :
            nil
    }

    private var accessibilityValue: String? {
        var components: [String] = []

        if let status = metric.status {
            components.append(status.text)
        }

        if let lastUpdate = metric.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let relativeTime = formatter.localizedString(for: lastUpdate, relativeTo: Date())
            components.append("Updated \(relativeTime)")
        }

        return components.isEmpty ? nil : components.joined(separator: ". ")
    }
}

// MARK: - Card Styles

enum CardStyle {
    case compact
    case standard
    case large
    case detailed

    var padding: CGFloat {
        switch self {
        case .compact: return 12
        case .standard: return 16
        case .large: return 20
        case .detailed: return 24
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 8
        case .standard: return 12
        case .large: return 16
        case .detailed: return 20
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: return 16
        case .standard: return 20
        case .large: return 24
        case .detailed: return 28
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .compact: return 14
        case .standard: return 15
        case .large: return 16
        case .detailed: return 17
        }
    }

    var valueSize: CGFloat {
        switch self {
        case .compact: return 20
        case .standard: return 24
        case .large: return 28
        case .detailed: return 32
        }
    }

    var unitSize: CGFloat {
        switch self {
        case .compact: return 11
        case .standard: return 12
        case .large: return 13
        case .detailed: return 14
        }
    }

    var statusSize: CGFloat {
        switch self {
        case .compact: return 10
        case .standard: return 11
        case .large: return 12
        case .detailed: return 13
        }
    }

    var chartHeight: CGFloat {
        switch self {
        case .compact: return 30
        case .standard: return 40
        case .large: return 50
        case .detailed: return 60
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .compact, .standard: return .secondarySystemGroupedBackground
        case .large, .detailed: return .systemGroupedBackground
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .compact: return 2
        case .standard: return 4
        case .large: return 6
        case .detailed: return 8
        }
    }

    var shadowOffset: CGFloat {
        switch self {
        case .compact: return 1
        case .standard: return 2
        case .large: return 3
        case .detailed: return 4
        }
    }
}

// MARK: - Trend Indicator

struct TrendIndicator: View {
    let trend: TrendDirection
    let style: CardStyle
    let accessibilityManager: AccessibilityManager

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trendIcon)
                .accessibleFont(style.statusSize, style: .caption2, weight: .bold)
                .accessibleForegroundColor(trendColor)

            if !accessibilityManager.simplifiedInterface {
                Text(trendPercentage)
                    .accessibleFont(style.statusSize - 1, style: .caption2, weight: .medium)
                    .accessibleForegroundColor(trendColor)
            }
        }
        .accessibilityHidden(true) // Included in main card accessibility
    }

    private var trendIcon: String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .neutral: return "minus"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .up: return accessibilityManager.accessibleColor(.green)
        case .down: return accessibilityManager.accessibleColor(.red)
        case .neutral: return accessibilityManager.accessibleColor(.gray)
        }
    }

    private var trendPercentage: String {
        switch trend {
        case .up: return "+5%"
        case .down: return "-3%"
        case .neutral: return "0%"
        }
    }
}

// MARK: - Mini Chart

struct MiniChart: View {
    let dataPoints: [Double]
    let color: Color
    let style: CardStyle
    let accessibilityManager: AccessibilityManager

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard dataPoints.count > 1 else { return }

                let width = geometry.size.width
                let height = geometry.size.height
                let stepWidth = width / CGFloat(dataPoints.count - 1)

                let minValue = dataPoints.min() ?? 0
                let maxValue = dataPoints.max() ?? 1
                let range = maxValue - minValue

                for (index, value) in dataPoints.enumerated() {
                    let x = CGFloat(index) * stepWidth
                    let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                    let y = height - (CGFloat(normalizedValue) * height)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                accessibilityManager.accessibleColor(color),
                style: StrokeStyle(
                    lineWidth: accessibilityManager.highContrastColors ? 3.0 : 2.0,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .accessibleAnimation(.easeInOut, value: dataPoints)
        }
        .clipped()
    }
}

// MARK: - Button Style

struct MetricCardButtonStyle: ButtonStyle {
    @StateObject private var accessibilityManager = AccessibilityManager.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .accessibleAnimation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Supporting Types

struct HealthMetricStatus {
    let text: String
    let color: Color

    static let normal = HealthMetricStatus(
        text: NSLocalizedString("Normal", comment: "Normal health status"),
        color: .green
    )

    static let warning = HealthMetricStatus(
        text: NSLocalizedString("Warning", comment: "Warning health status"),
        color: .orange
    )

    static let critical = HealthMetricStatus(
        text: NSLocalizedString("Critical", comment: "Critical health status"),
        color: .red
    )

    static let unknown = HealthMetricStatus(
        text: NSLocalizedString("Unknown", comment: "Unknown health status"),
        color: .gray
    )
}

// MARK: - HealthMetric Extension

extension HealthMetric {
    var status: HealthMetricStatus? {
        // This would be determined by health logic
        // For now, return nil to not show status
        return nil
    }

    var chartData: [Double]? {
        // This would come from actual chart data
        // For now, return sample data for demonstration
        return [65, 70, 68, 72, 75, 73, 71]
    }

    var lastUpdated: Date? {
        // This would come from actual data
        return Date().addingTimeInterval(-3600) // 1 hour ago
    }
}

// MARK: - Preset Card Configurations

extension HealthMetricCard {
    /// Heart rate card with standard styling
    static func heartRateCard(
        value: String,
        trend: TrendDirection = .neutral,
        onTap: (() -> Void)? = nil
    ) -> HealthMetricCard {
        let metric = HealthMetric(
            id: "heart-rate",
            title: NSLocalizedString("Heart Rate", comment: "Heart rate metric title"),
            value: value,
            unit: "bpm",
            trend: trend,
            icon: "heart.fill",
            color: .red
        )

        return HealthMetricCard(
            metric: metric,
            style: .standard,
            showTrend: true,
            showChart: true,
            onTap: onTap
        )
    }

    /// Steps card with bar chart styling
    static func stepsCard(
        value: String,
        trend: TrendDirection = .neutral,
        onTap: (() -> Void)? = nil
    ) -> HealthMetricCard {
        let metric = HealthMetric(
            id: "steps",
            title: NSLocalizedString("Daily Steps", comment: "Steps metric title"),
            value: value,
            unit: "steps",
            trend: trend,
            icon: "figure.walk",
            color: .blue
        )

        return HealthMetricCard(
            metric: metric,
            style: .standard,
            showTrend: true,
            showChart: true,
            onTap: onTap
        )
    }

    /// Sleep card with detailed styling
    static func sleepCard(
        value: String,
        trend: TrendDirection = .neutral,
        onTap: (() -> Void)? = nil
    ) -> HealthMetricCard {
        let metric = HealthMetric(
            id: "sleep",
            title: NSLocalizedString("Sleep Quality", comment: "Sleep metric title"),
            value: value,
            unit: "score",
            trend: trend,
            icon: "bed.double.fill",
            color: .purple
        )

        return HealthMetricCard(
            metric: metric,
            style: .detailed,
            showTrend: true,
            showChart: true,
            onTap: onTap
        )
    }

    /// Weight card with compact styling
    static func weightCard(
        value: String,
        trend: TrendDirection = .neutral,
        onTap: (() -> Void)? = nil
    ) -> HealthMetricCard {
        let metric = HealthMetric(
            id: "weight",
            title: NSLocalizedString("Weight", comment: "Weight metric title"),
            value: value,
            unit: "kg",
            trend: trend,
            icon: "scalemass.fill",
            color: .green
        )

        return HealthMetricCard(
            metric: metric,
            style: .compact,
            showTrend: true,
            showChart: false,
            onTap: onTap
        )
    }
}

// MARK: - Preview Support

#if DEBUG
struct HealthMetricCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HealthMetricCard.heartRateCard(value: "72", trend: .up)
            HealthMetricCard.stepsCard(value: "8,456", trend: .neutral)
            HealthMetricCard.sleepCard(value: "8.2", trend: .down)
            HealthMetricCard.weightCard(value: "70.5", trend: .up)
        }
        .padding()
        .background(Color(.systemBackground))
        .previewDisplayName("Health Metric Cards")
    }
}
#endif