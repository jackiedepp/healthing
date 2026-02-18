//
//  CareKitChartView.swift
//  HealthingApp
//
//  Created by Claude on 2024-01-20.
//  Enhanced for Phase 2E: UI/UX Enhancement & Accessibility
//  Implements REQ-049: Beautiful data visualizations using CareKit charts
//

import SwiftUI
import CareKit
import CareKitUI
import HealthKit
import os.log

/// Beautiful data visualizations using CareKit's OCKCartesianChartView
/// Implements REQ-049: Beautiful data visualizations using CareKit charts
struct CareKitChartView: UIViewRepresentable {

    // MARK: - Properties

    let chartType: ChartType
    let dataPoints: [ChartDataPoint]
    let timeRange: TimeInterval
    let title: String
    let subtitle: String?
    let unit: String
    let configuration: ChartConfiguration

    private let logger = Logger(subsystem: "HealthingApp", category: "CareKitChartView")

    // MARK: - Initialization

    init(
        type: ChartType,
        dataPoints: [ChartDataPoint],
        timeRange: TimeInterval = 7 * 24 * 60 * 60, // 7 days
        title: String,
        subtitle: String? = nil,
        unit: String,
        configuration: ChartConfiguration = ChartConfiguration()
    ) {
        self.chartType = type
        self.dataPoints = dataPoints
        self.timeRange = timeRange
        self.title = title
        self.subtitle = subtitle
        self.unit = unit
        self.configuration = configuration
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> OCKCartesianChartView {
        logger.debug("Creating CareKit chart view: \(title)")

        let chartView = OCKCartesianChartView(type: chartType.ockChartType)

        // Configure accessibility
        configureAccessibility(for: chartView)

        // Apply configuration
        applyConfiguration(to: chartView)

        // Set up chart data
        updateChartData(chartView)

        return chartView
    }

    func updateUIView(_ uiView: OCKCartesianChartView, context: Context) {
        logger.debug("Updating CareKit chart view: \(title)")
        updateChartData(uiView)
    }

    // MARK: - Private Methods

    private func configureAccessibility(for chartView: OCKCartesianChartView) {
        let accessibilityManager = AccessibilityManager.shared

        // Basic accessibility setup
        chartView.isAccessibilityElement = true
        chartView.accessibilityLabel = generateAccessibilityLabel()
        chartView.accessibilityHint = accessibilityManager.accessibilityHint(for: .viewDetails)
        chartView.accessibilityTraits = [.image, .button]

        // Audio descriptions for charts
        if accessibilityManager.isAudioDescriptionsEnabled {
            let values = dataPoints.map(\.value)
            let timeLabels = dataPoints.map { DateFormatter.shortTime.string(from: $0.date) }

            let audioDescription = accessibilityManager.generateChartAudioDescription(
                title: title,
                dataPoints: values,
                timeLabels: timeLabels,
                unit: unit
            )

            chartView.accessibilityValue = audioDescription
        }

        // VoiceOver navigation
        if accessibilityManager.isVoiceOverRunning {
            chartView.accessibilityNavigationStyle = .automatic
        }
    }

    private func applyConfiguration(to chartView: OCKCartesianChartView) {
        let accessibilityManager = AccessibilityManager.shared

        // Header configuration
        chartView.headerView.titleLabel.text = title
        chartView.headerView.titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)

        if let subtitle = subtitle {
            chartView.headerView.detailLabel.text = subtitle
            chartView.headerView.detailLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        }

        // Colors with accessibility support
        let primaryColor = UIColor(accessibilityManager.accessibleColor(configuration.primaryColor))
        let secondaryColor = UIColor(accessibilityManager.accessibleColor(configuration.secondaryColor))

        chartView.graphView.tintColor = primaryColor
        chartView.graphView.selectedPointColor = secondaryColor

        // Grid and axis styling
        chartView.graphView.xAxis.showsMinorGridLines = configuration.showMinorGridLines
        chartView.graphView.yAxis.showsMinorGridLines = configuration.showMinorGridLines
        chartView.graphView.xAxis.axisColor = UIColor.secondaryLabel
        chartView.graphView.yAxis.axisColor = UIColor.secondaryLabel

        // Data point styling
        chartView.graphView.dataPointSize = configuration.dataPointSize
        chartView.graphView.lineWidth = configuration.lineWidth

        // Accessibility enhancements
        if accessibilityManager.highContrastColors {
            chartView.graphView.lineWidth = configuration.lineWidth * 1.5
            chartView.graphView.dataPointSize = configuration.dataPointSize * 1.2
        }

        if accessibilityManager.prefersLargerHitTargets {
            chartView.graphView.dataPointSize = max(configuration.dataPointSize, 8.0)
        }

        // Background and transparency
        if accessibilityManager.isReduceTransparencyEnabled {
            chartView.backgroundColor = UIColor.systemBackground
            chartView.graphView.backgroundColor = UIColor.secondarySystemBackground
        }
    }

    private func updateChartData(_ chartView: OCKCartesianChartView) {
        let sortedDataPoints = dataPoints.sorted { $0.date < $1.date }

        switch chartType {
        case .line:
            setupLineChart(chartView, with: sortedDataPoints)
        case .bar:
            setupBarChart(chartView, with: sortedDataPoints)
        case .scatter:
            setupScatterChart(chartView, with: sortedDataPoints)
        }

        // Update date range
        if let firstDate = sortedDataPoints.first?.date,
           let lastDate = sortedDataPoints.last?.date {
            chartView.graphView.dateInterval = DateInterval(start: firstDate, end: lastDate)
        }
    }

    private func setupLineChart(_ chartView: OCKCartesianChartView, with dataPoints: [ChartDataPoint]) {
        let dataSeries = OCKDataSeries(
            values: dataPoints.map { CGFloat($0.value) },
            title: title,
            gradientStartColor: UIColor(configuration.primaryColor),
            gradientEndColor: UIColor(configuration.primaryColor.opacity(0.3)),
            size: configuration.dataPointSize
        )

        chartView.graphView.dataSeries = [dataSeries]

        // Configure line chart specific properties
        chartView.graphView.selectedPointColor = UIColor(configuration.secondaryColor)
    }

    private func setupBarChart(_ chartView: OCKCartesianChartView, with dataPoints: [ChartDataPoint]) {
        let dataSeries = OCKDataSeries(
            values: dataPoints.map { CGFloat($0.value) },
            title: title,
            gradientStartColor: UIColor(configuration.primaryColor),
            gradientEndColor: UIColor(configuration.primaryColor.opacity(0.7)),
            size: configuration.dataPointSize
        )

        chartView.graphView.dataSeries = [dataSeries]
    }

    private func setupScatterChart(_ chartView: OCKCartesianChartView, with dataPoints: [ChartDataPoint]) {
        let dataSeries = OCKDataSeries(
            values: dataPoints.map { CGFloat($0.value) },
            title: title,
            gradientStartColor: UIColor(configuration.primaryColor),
            gradientEndColor: UIColor(configuration.primaryColor),
            size: configuration.dataPointSize * 1.5
        )

        chartView.graphView.dataSeries = [dataSeries]
    }

    private func generateAccessibilityLabel() -> String {
        let dataCount = dataPoints.count
        let range = dataPoints.isEmpty ? "no data" : "\(dataPoints.count) data points"

        if let subtitle = subtitle {
            return "\(title) chart, \(subtitle), showing \(range)"
        } else {
            return "\(title) chart showing \(range)"
        }
    }
}

// MARK: - Chart Configuration

struct ChartConfiguration {
    let primaryColor: Color
    let secondaryColor: Color
    let backgroundColor: Color
    let dataPointSize: CGFloat
    let lineWidth: CGFloat
    let showMinorGridLines: Bool
    let animated: Bool

    init(
        primaryColor: Color = .blue,
        secondaryColor: Color = .orange,
        backgroundColor: Color = .clear,
        dataPointSize: CGFloat = 6.0,
        lineWidth: CGFloat = 3.0,
        showMinorGridLines: Bool = false,
        animated: Bool = true
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.backgroundColor = backgroundColor
        self.dataPointSize = dataPointSize
        self.lineWidth = lineWidth
        self.showMinorGridLines = showMinorGridLines
        self.animated = animated
    }
}

// MARK: - Chart Types

enum ChartType {
    case line
    case bar
    case scatter

    var ockChartType: OCKCartesianGraphView.PlotType {
        switch self {
        case .line:
            return .line
        case .bar:
            return .bar
        case .scatter:
            return .scatter
        }
    }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String?
    let metadata: [String: Any]?

    init(date: Date, value: Double, label: String? = nil, metadata: [String: Any]? = nil) {
        self.date = date
        self.value = value
        self.label = label
        self.metadata = metadata
    }
}

// MARK: - Pre-configured Chart Views

extension CareKitChartView {
    /// Heart rate trend chart
    static func heartRateChart(
        dataPoints: [ChartDataPoint],
        timeRange: TimeInterval = 7 * 24 * 60 * 60
    ) -> CareKitChartView {
        let config = ChartConfiguration(
            primaryColor: .red,
            secondaryColor: .pink,
            dataPointSize: 5.0,
            lineWidth: 2.5
        )

        return CareKitChartView(
            type: .line,
            dataPoints: dataPoints,
            timeRange: timeRange,
            title: NSLocalizedString("Heart Rate", comment: "Heart rate chart title"),
            subtitle: NSLocalizedString("Resting heart rate over time", comment: "Heart rate chart subtitle"),
            unit: "bpm",
            configuration: config
        )
    }

    /// Daily steps chart
    static func stepsChart(
        dataPoints: [ChartDataPoint],
        timeRange: TimeInterval = 7 * 24 * 60 * 60
    ) -> CareKitChartView {
        let config = ChartConfiguration(
            primaryColor: .blue,
            secondaryColor: .cyan,
            dataPointSize: 6.0,
            lineWidth: 3.0
        )

        return CareKitChartView(
            type: .bar,
            dataPoints: dataPoints,
            timeRange: timeRange,
            title: NSLocalizedString("Daily Steps", comment: "Steps chart title"),
            subtitle: NSLocalizedString("Step count per day", comment: "Steps chart subtitle"),
            unit: "steps",
            configuration: config
        )
    }

    /// Sleep quality chart
    static func sleepChart(
        dataPoints: [ChartDataPoint],
        timeRange: TimeInterval = 7 * 24 * 60 * 60
    ) -> CareKitChartView {
        let config = ChartConfiguration(
            primaryColor: .purple,
            secondaryColor: .indigo,
            dataPointSize: 7.0,
            lineWidth: 3.5
        )

        return CareKitChartView(
            type: .line,
            dataPoints: dataPoints,
            timeRange: timeRange,
            title: NSLocalizedString("Sleep Quality", comment: "Sleep chart title"),
            subtitle: NSLocalizedString("Sleep quality score over time", comment: "Sleep chart subtitle"),
            unit: "score",
            configuration: config
        )
    }

    /// Weight trend chart
    static func weightChart(
        dataPoints: [ChartDataPoint],
        timeRange: TimeInterval = 30 * 24 * 60 * 60
    ) -> CareKitChartView {
        let config = ChartConfiguration(
            primaryColor: .green,
            secondaryColor: .mint,
            dataPointSize: 5.0,
            lineWidth: 2.0
        )

        return CareKitChartView(
            type: .line,
            dataPoints: dataPoints,
            timeRange: timeRange,
            title: NSLocalizedString("Weight Trend", comment: "Weight chart title"),
            subtitle: NSLocalizedString("Weight changes over time", comment: "Weight chart subtitle"),
            unit: "kg",
            configuration: config
        )
    }

    /// Blood pressure chart
    static func bloodPressureChart(
        systolicPoints: [ChartDataPoint],
        diastolicPoints: [ChartDataPoint],
        timeRange: TimeInterval = 14 * 24 * 60 * 60
    ) -> CareKitChartView {
        let config = ChartConfiguration(
            primaryColor: .orange,
            secondaryColor: .yellow,
            dataPointSize: 5.0,
            lineWidth: 2.5
        )

        // Combine systolic and diastolic points
        let combinedPoints = systolicPoints + diastolicPoints

        return CareKitChartView(
            type: .line,
            dataPoints: combinedPoints,
            timeRange: timeRange,
            title: NSLocalizedString("Blood Pressure", comment: "Blood pressure chart title"),
            subtitle: NSLocalizedString("Systolic and diastolic readings", comment: "Blood pressure chart subtitle"),
            unit: "mmHg",
            configuration: config
        )
    }

    /// Active energy chart
    static func activeEnergyChart(
        dataPoints: [ChartDataPoint],
        timeRange: TimeInterval = 7 * 24 * 60 * 60
    ) -> CareKitChartView {
        let config = ChartConfiguration(
            primaryColor: .orange,
            secondaryColor: .red,
            dataPointSize: 6.0,
            lineWidth: 3.0
        )

        return CareKitChartView(
            type: .bar,
            dataPoints: dataPoints,
            timeRange: timeRange,
            title: NSLocalizedString("Active Energy", comment: "Active energy chart title"),
            subtitle: NSLocalizedString("Calories burned through activity", comment: "Active energy chart subtitle"),
            unit: "cal",
            configuration: config
        )
    }
}

// MARK: - Chart Data Conversion Helpers

extension ChartDataPoint {
    /// Create chart data point from health observation
    static func from(observation: HealthingObservation) -> ChartDataPoint? {
        guard let value = observation.valueQuantity?.value?.decimal?.doubleValue,
              let date = observation.effectiveDateTime?.date else {
            return nil
        }

        return ChartDataPoint(
            date: date,
            value: value,
            label: observation.category.first?.coding?.first?.display?.string,
            metadata: [
                "observation_id": observation.id?.string ?? "",
                "category": observation.category.first?.coding?.first?.code?.string ?? ""
            ]
        )
    }

    /// Create chart data points from health kit samples
    static func from(samples: [HKQuantitySample], unit: HKUnit) -> [ChartDataPoint] {
        return samples.map { sample in
            ChartDataPoint(
                date: sample.startDate,
                value: sample.quantity.doubleValue(for: unit),
                label: DateFormatter.shortTime.string(from: sample.startDate),
                metadata: [
                    "sample_uuid": sample.uuid.uuidString,
                    "source": sample.sourceRevision.source.name
                ]
            )
        }
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .short
        return formatter
    }()
}

// MARK: - Preview Support

#if DEBUG
extension ChartDataPoint {
    static func sampleHeartRateData() -> [ChartDataPoint] {
        let dates = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
        return dates.map { date in
            ChartDataPoint(
                date: date,
                value: Double.random(in: 60...80),
                label: DateFormatter.shortDate.string(from: date)
            )
        }
    }

    static func sampleStepsData() -> [ChartDataPoint] {
        let dates = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
        return dates.map { date in
            ChartDataPoint(
                date: date,
                value: Double.random(in: 5000...12000),
                label: DateFormatter.shortDate.string(from: date)
            )
        }
    }
}

struct CareKitChartView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CareKitChartView.heartRateChart(dataPoints: ChartDataPoint.sampleHeartRateData())
                .frame(height: 200)

            CareKitChartView.stepsChart(dataPoints: ChartDataPoint.sampleStepsData())
                .frame(height: 200)
        }
        .padding()
    }
}
#endif