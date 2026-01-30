import Foundation
import BackgroundTasks
import SwiftUI
import Combine

/// Background processing service for continuous data collection and sync
/// Implements REQ-020: Background processing for continuous data collection
/// Manages BGAppRefreshTask and BGProcessingTask for health data operations
@MainActor
class BackgroundProcessingService: ObservableObject {
    static let shared = BackgroundProcessingService()

    // Background task identifiers (must be registered in Info.plist)
    private struct TaskIdentifiers {
        static let healthDataSync = "com.healthing.app.healthsync"
        static let dataCleanup = "com.healthing.app.datacleanup"
        static let aiProcessing = "com.healthing.app.aiprocessing"
        static let deviceSync = "com.healthing.app.devicesync"
    }

    @Published var isBackgroundRefreshEnabled = false
    @Published var lastBackgroundSync: Date?
    @Published var backgroundSyncCount = 0
    @Published var backgroundTasksRegistered = false

    private let healthKitSync = HealthKitSyncService.shared
    private let dataStore = HealthDataStore.shared

    private init() {
        checkBackgroundRefreshStatus()
        registerBackgroundTasks()
    }

    /// Register all background tasks
    func registerBackgroundTasks() {
        // Health data sync - frequent updates
        BGTaskScheduler.shared.register(forTaskWithIdentifier: TaskIdentifiers.healthDataSync, using: nil) { task in
            Task {
                await self.handleHealthDataSync(task: task as! BGAppRefreshTask)
            }
        }

        // Data cleanup - less frequent, longer running
        BGTaskScheduler.shared.register(forTaskWithIdentifier: TaskIdentifiers.dataCleanup, using: nil) { task in
            Task {
                await self.handleDataCleanup(task: task as! BGProcessingTask)
            }
        }

        // AI processing - analyze recent health data
        BGTaskScheduler.shared.register(forTaskWithIdentifier: TaskIdentifiers.aiProcessing, using: nil) { task in
            Task {
                await self.handleAIProcessing(task: task as! BGProcessingTask)
            }
        }

        // Device sync - sync with connected wearables
        BGTaskScheduler.shared.register(forTaskWithIdentifier: TaskIdentifiers.deviceSync, using: nil) { task in
            Task {
                await self.handleDeviceSync(task: task as! BGAppRefreshTask)
            }
        }

        backgroundTasksRegistered = true
        print("✅ BackgroundProcessingService: All background tasks registered")
    }

    /// Schedule next background refresh task
    func scheduleBackgroundTasks() {
        scheduleHealthDataSync()
        scheduleDataCleanup()
        scheduleAIProcessing()
        scheduleDeviceSync()
    }

    /// Schedule health data sync (most frequent - every 15 minutes when possible)
    private func scheduleHealthDataSync() {
        let request = BGAppRefreshTaskRequest(identifier: TaskIdentifiers.healthDataSync)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 BackgroundProcessingService: Scheduled health data sync")
        } catch {
            print("❌ BackgroundProcessingService: Could not schedule health data sync: \(error)")
        }
    }

    /// Schedule data cleanup (daily)
    private func scheduleDataCleanup() {
        let request = BGProcessingTaskRequest(identifier: TaskIdentifiers.dataCleanup)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60) // 24 hours
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 BackgroundProcessingService: Scheduled data cleanup")
        } catch {
            print("❌ BackgroundProcessingService: Could not schedule data cleanup: \(error)")
        }
    }

    /// Schedule AI processing (every 6 hours)
    private func scheduleAIProcessing() {
        let request = BGProcessingTaskRequest(identifier: TaskIdentifiers.aiProcessing)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) // 6 hours
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 BackgroundProcessingService: Scheduled AI processing")
        } catch {
            print("❌ BackgroundProcessingService: Could not schedule AI processing: \(error)")
        }
    }

    /// Schedule device sync (every 30 minutes)
    private func scheduleDeviceSync() {
        let request = BGAppRefreshTaskRequest(identifier: TaskIdentifiers.deviceSync)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 BackgroundProcessingService: Scheduled device sync")
        } catch {
            print("❌ BackgroundProcessingService: Could not schedule device sync: \(error)")
        }
    }

    /// Handle health data sync background task
    private func handleHealthDataSync(task: BGAppRefreshTask) async {
        print("🔄 BackgroundProcessingService: Starting health data sync background task")

        let taskCompleted = await withTaskCancellationHandler(
            operation: {
                do {
                    // Sync latest HealthKit data
                    await healthKitSync.manualSync()

                    // Update sync statistics
                    await MainActor.run {
                        lastBackgroundSync = Date()
                        backgroundSyncCount += 1
                    }

                    // Schedule next sync
                    scheduleHealthDataSync()

                    return true
                } catch {
                    print("❌ BackgroundProcessingService: Health sync failed: \(error)")
                    return false
                }
            },
            onCancel: {
                task.setTaskCompleted(success: false)
            }
        )

        task.setTaskCompleted(success: taskCompleted)
    }

    /// Handle data cleanup background task
    private func handleDataCleanup(task: BGProcessingTask) async {
        print("🔄 BackgroundProcessingService: Starting data cleanup background task")

        let taskCompleted = await withTaskCancellationHandler(
            operation: {
                do {
                    // Clean up old data (older than retention policy)
                    let cutoffDate = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
                    try await dataStore.cleanupOldData(olderThan: cutoffDate)

                    // Optimize database
                    try await dataStore.optimizeDatabase()

                    // Schedule next cleanup
                    scheduleDataCleanup()

                    return true
                } catch {
                    print("❌ BackgroundProcessingService: Data cleanup failed: \(error)")
                    return false
                }
            },
            onCancel: {
                task.setTaskCompleted(success: false)
            }
        )

        task.setTaskCompleted(success: taskCompleted)
    }

    /// Handle AI processing background task
    private func handleAIProcessing(task: BGProcessingTask) async {
        print("🔄 BackgroundProcessingService: Starting AI processing background task")

        let taskCompleted = await withTaskCancellationHandler(
            operation: {
                do {
                    // Process recent health data for insights
                    await processHealthInsights()

                    // Generate anomaly detection alerts
                    await processAnomalyDetection()

                    // Update personalized recommendations
                    await updatePersonalizedRecommendations()

                    // Schedule next processing
                    scheduleAIProcessing()

                    return true
                } catch {
                    print("❌ BackgroundProcessingService: AI processing failed: \(error)")
                    return false
                }
            },
            onCancel: {
                task.setTaskCompleted(success: false)
            }
        )

        task.setTaskCompleted(success: taskCompleted)
    }

    /// Handle device sync background task
    private func handleDeviceSync(task: BGAppRefreshTask) async {
        print("🔄 BackgroundProcessingService: Starting device sync background task")

        let taskCompleted = await withTaskCancellationHandler(
            operation: {
                do {
                    // Sync with connected wearable devices
                    await syncConnectedDevices()

                    // Update device battery levels and status
                    await updateDeviceStatus()

                    // Schedule next device sync
                    scheduleDeviceSync()

                    return true
                } catch {
                    print("❌ BackgroundProcessingService: Device sync failed: \(error)")
                    return false
                }
            },
            onCancel: {
                task.setTaskCompleted(success: false)
            }
        )

        task.setTaskCompleted(success: taskCompleted)
    }

    /// Check current background refresh permission status
    private func checkBackgroundRefreshStatus() {
        isBackgroundRefreshEnabled = UIApplication.shared.backgroundRefreshStatus == .available
    }

    /// Simulate immediate background task for testing
    func simulateBackgroundSync() async {
        print("🧪 BackgroundProcessingService: Simulating background sync for testing")
        await healthKitSync.manualSync()

        await MainActor.run {
            lastBackgroundSync = Date()
            backgroundSyncCount += 1
        }
    }

    /// Get background sync statistics
    func getBackgroundSyncStats() -> BackgroundSyncStats {
        return BackgroundSyncStats(
            isEnabled: isBackgroundRefreshEnabled,
            tasksRegistered: backgroundTasksRegistered,
            lastSync: lastBackgroundSync,
            syncCount: backgroundSyncCount,
            nextScheduledSync: Calendar.current.date(byAdding: .minute, value: 15, to: lastBackgroundSync ?? Date())
        )
    }

    /// Request background app refresh permission from user
    func requestBackgroundRefresh() {
        guard !isBackgroundRefreshEnabled else { return }

        // Guide user to Settings > General > Background App Refresh
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                UIApplication.shared.open(settingsUrl)
            }
        }
    }
}

// MARK: - AI Processing Helpers
private extension BackgroundProcessingService {
    /// Process health insights in background
    func processHealthInsights() async {
        print("🧠 BackgroundProcessingService: Processing health insights...")

        // Get recent health data (last 7 days)
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let endDate = Date()

        do {
            let observations = try await dataStore.fetchHealthObservations(
                category: nil,
                dateRange: startDate...endDate,
                limit: 1000
            )

            // Process insights for each category
            let categories = ["vital-signs", "activity", "sleep", "nutrition"]
            for category in categories {
                let categoryData = observations.filter { $0.category == category }
                if !categoryData.isEmpty {
                    // Process category-specific insights
                    // This will be enhanced when AI services are implemented
                    print("📊 Processed \(categoryData.count) \(category) observations")
                }
            }

        } catch {
            print("❌ BackgroundProcessingService: Failed to fetch health data for insights: \(error)")
        }
    }

    /// Process anomaly detection in background
    func processAnomalyDetection() async {
        print("⚠️ BackgroundProcessingService: Processing anomaly detection...")

        // Get recent vital signs for anomaly detection
        let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()

        do {
            let vitalSigns = try await dataStore.fetchHealthObservations(
                category: "vital-signs",
                dateRange: startDate...Date(),
                limit: 100
            )

            // Simple anomaly detection rules (will be enhanced with Core ML)
            for observation in vitalSigns {
                if let valueQuantity = observation.valueQuantity {
                    await checkForAnomalies(observation: observation, value: valueQuantity.value)
                }
            }

        } catch {
            print("❌ BackgroundProcessingService: Failed to process anomaly detection: \(error)")
        }
    }

    /// Check for simple anomalies in health data
    func checkForAnomalies(observation: HealthingObservation, value: Double) async {
        let isAnomaly: Bool

        switch observation.code {
        case "8867-4": // Heart rate
            isAnomaly = value > 120 || value < 50
        case "8480-6": // Systolic blood pressure
            isAnomaly = value > 140 || value < 90
        case "8462-4": // Diastolic blood pressure
            isAnomaly = value > 90 || value < 60
        case "8310-5": // Body temperature
            isAnomaly = value > 38.0 || value < 35.0 // Celsius
        case "2708-6": // Oxygen saturation
            isAnomaly = value < 95.0
        default:
            isAnomaly = false
        }

        if isAnomaly {
            print("⚠️ Anomaly detected: \(observation.code) = \(value)")
            // Here we would generate notifications or alerts
            // This will be enhanced when notification service is implemented
        }
    }

    /// Update personalized recommendations
    func updatePersonalizedRecommendations() async {
        print("🎯 BackgroundProcessingService: Updating personalized recommendations...")

        // Get user's recent activity and health trends
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        do {
            let activityData = try await dataStore.fetchHealthObservations(
                category: "activity",
                dateRange: startDate...Date(),
                limit: 500
            )

            // Analyze activity patterns and generate recommendations
            // This will be enhanced when AI recommendation engine is implemented
            let averageSteps = activityData
                .filter { $0.code == "55423-8" } // Step count
                .compactMap { $0.valueQuantity?.value }
                .reduce(0, +) / Double(max(activityData.count, 1))

            if averageSteps < 8000 {
                print("💡 Recommendation: Increase daily steps (current average: \(Int(averageSteps)))")
            }

        } catch {
            print("❌ BackgroundProcessingService: Failed to generate recommendations: \(error)")
        }
    }
}

// MARK: - Device Sync Helpers
private extension BackgroundProcessingService {
    /// Sync with connected wearable devices
    func syncConnectedDevices() async {
        print("⌚ BackgroundProcessingService: Syncing connected devices...")

        // Apple Watch sync (via HealthKit)
        await healthKitSync.manualSync()

        // Garmin device sync will be implemented when Garmin SDK is integrated
        // Fitbit device sync will be implemented when Fitbit SDK is integrated

        print("✅ Device sync completed")
    }

    /// Update device status and battery levels
    func updateDeviceStatus() async {
        print("🔋 BackgroundProcessingService: Updating device status...")

        // Get connected devices and update their status
        // This will be enhanced when device management service is implemented

        let connectedDevices = await getConnectedDevices()
        for device in connectedDevices {
            print("📱 Device status: \(device.displayName) - Connected")
        }
    }

    /// Get list of connected devices
    func getConnectedDevices() async -> [HealthingDevice] {
        // Mock implementation - will be enhanced with actual device integration
        return [
            HealthingDevice.appleWatchDevice(),
            // Additional devices will be added as integrations are completed
        ]
    }
}

// MARK: - Supporting Types
struct BackgroundSyncStats {
    let isEnabled: Bool
    let tasksRegistered: Bool
    let lastSync: Date?
    let syncCount: Int
    let nextScheduledSync: Date?

    var formattedLastSync: String {
        guard let lastSync = lastSync else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    var formattedNextSync: String {
        guard let nextSync = nextScheduledSync else { return "Not scheduled" }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: nextSync, relativeTo: Date())
    }
}