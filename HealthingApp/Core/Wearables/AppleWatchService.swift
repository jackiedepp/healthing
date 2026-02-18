import Foundation
import HealthKit
import SwiftUI
import Combine
import WatchConnectivity

/// Native Apple Watch integration service for comprehensive wearable data collection
/// Implements REQ-023: Apple Watch native integration for comprehensive wearable data
/// Implements REQ-065: Real-time data synchronization from connected devices
/// Implements REQ-066: Battery level monitoring for connected devices
@MainActor
class AppleWatchService: NSObject, ObservableObject {
    static let shared = AppleWatchService()

    @Published var isWatchConnected = false
    @Published var watchConnectionState: WCSessionActivationState = .notActivated
    @Published var watchBatteryLevel: Float = 0.0
    @Published var lastSyncDate: Date?
    @Published var watchAppInstalled = false
    @Published var watchReachable = false

    // Watch-specific health data types
    private let watchHealthTypes: [HKQuantityType] = {
        var types: [HKQuantityType] = []
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) { types.append(type) }
        if let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) { types.append(type) }
        return types
    }()

    private let provider: HealthKitProviding
    private let healthKitSync = HealthKitSyncService.shared
    private let dataProcessor = WearableDataProcessor.shared
    private let conflictResolver = ConflictResolutionService.shared
    private var hasStartedMonitoring = false
    private var observerTokens: [AnyObject] = []

    // Watch Connectivity
    private var wcSession: WCSession?

    private override init() {
        provider = HealthKitProviderFactory.makeProvider(source: .appleWatch)
        super.init()
        setupWatchConnectivity()
        startWatchHealthMonitoringIfAuthorized()
    }

    // MARK: - Watch Connectivity Setup

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("⌚ AppleWatchService: Watch Connectivity not supported")
            return
        }

        wcSession = WCSession.default
        wcSession?.delegate = self
        wcSession?.activate()

        print("⌚ AppleWatchService: Watch Connectivity activated")
    }

    // MARK: - Watch Health Data Monitoring

    private func startWatchHealthMonitoringIfAuthorized() {
        guard !hasStartedMonitoring else { return }
        guard canStartMonitoring() else {
            print("⌚ AppleWatchService: HealthKit not authorized yet, deferring watch monitoring")
            return
        }

        hasStartedMonitoring = true
        startWatchHealthMonitoring()
    }

    private func canStartMonitoring() -> Bool {
        guard provider.isHealthDataAvailable() else { return false }
        return !authorizedWatchHealthTypes().isEmpty
    }

    private func startWatchHealthMonitoring() {
        print("⌚ AppleWatchService: Starting Apple Watch health data monitoring...")

        let authorizedTypes = authorizedWatchHealthTypes()
        guard !authorizedTypes.isEmpty else {
            print("⌚ AppleWatchService: No authorized HealthKit types for watch monitoring")
            return
        }

        // Monitor watch-specific health data types
        for healthType in authorizedTypes {
            startWatchSpecificObserver(for: healthType)
        }

        // Monitor workout data specifically from Apple Watch
        startWatchWorkoutObserver()

        print("✅ AppleWatchService: All watch health observers started")
    }

    /// Start observer for watch-specific health data type
    private func startWatchSpecificObserver(for quantityType: HKQuantityType) {
        let token = provider.startObserver(for: quantityType) { [weak self] error in
            guard let self = self else { return }
            Task {
                await self.processWatchHealthUpdate(for: quantityType)
            }
        }

        if let token = token {
            observerTokens.append(token)
        }
        print("⌚ Started watch observer for: \(quantityType.identifier)")
    }

    /// Process health data updates from Apple Watch
    private func processWatchHealthUpdate(
        for quantityType: HKQuantityType,
        since startDate: Date? = nil,
        updateLastSync: Bool = true
    ) async {
        let syncStart = startDate ?? self.lastSyncDate ?? Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()

        do {
            let samples = try await provider.fetchQuantitySamples(of: quantityType, startDate: syncStart, endDate: Date())
            let watchSamples = samples.filter { self.isAppleWatchSample($0) }
            await self.processBatchWatchSamples(watchSamples)
            if updateLastSync {
                await MainActor.run {
                    self.lastSyncDate = Date()
                }
            }
        } catch {
            print("❌ AppleWatchService: Failed to fetch samples: \(error)")
        }
    }

    /// Process batch of Apple Watch health samples
    private func processBatchWatchSamples(_ samples: [HKQuantitySample]) async {
        print("⌚ AppleWatchService: Processing \(samples.count) watch samples...")

        for sample in samples {
            // Convert to HealthingObservation
            let observation = HealthingObservation.fromHealthKitQuantitySample(
                sample,
                category: HealthKitMapping.getCategory(for: sample.quantityType.identifier)
            )

            do {
                // Process through conflict resolution and data processor
                let resolvedObservation = try await conflictResolver.processObservation(observation)
                await dataProcessor.processWearableData(resolvedObservation, from: .appleWatch)

                print("⌚ Processed watch sample: \(sample.quantityType.identifier)")
            } catch {
                print("❌ Failed to process watch sample: \(error)")
            }
        }
    }

    /// Start observer for Apple Watch workouts
    private func startWatchWorkoutObserver() {
        let workoutType = HKObjectType.workoutType()
        let token = provider.startObserver(for: workoutType) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.processWatchWorkouts()
            }
        }

        if let token = token {
            observerTokens.append(token)
        }
        print("⌚ Started Apple Watch workout observer")
    }

    /// Process new Apple Watch workouts
    private func processWatchWorkouts(
        since startDate: Date? = nil,
        updateLastSync: Bool = true
    ) async {
        let syncStart = startDate ?? self.lastSyncDate ?? Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()

        do {
            let workouts = try await provider.fetchWorkouts(startDate: syncStart)
            for workout in workouts where isAppleWatchSample(workout) {
                await self.processWatchWorkout(workout)
            }
            if updateLastSync {
                await MainActor.run {
                    self.lastSyncDate = Date()
                }
            }
        } catch {
            print("❌ AppleWatchService: Failed to fetch workouts: \(error)")
        }
    }

    /// Process individual Apple Watch workout
    private func processWatchWorkout(_ workout: HKWorkout) async {
        // Create workout observation
        let observation = HealthingObservation(
            id: workout.uuid.uuidString,
            status: "final",
            code: "LA11834-1", // LOINC code for physical activity
            subject: "patient",
            effectiveDateTime: workout.startDate,
            valueQuantity: HealthingQuantity(
                value: workout.duration / 60.0, // Convert to minutes
                unit: "min"
            ),
            device: HealthingDevice.appleWatchDevice(),
            category: "activity"
        )

        // Add workout-specific components
        var components: [HealthingComponent] = []

        if let totalEnergyBurned = workout.totalEnergyBurned {
            components.append(HealthingComponent(
                code: "41981-2", // Active energy burned LOINC
                valueQuantity: HealthingQuantity(
                    value: totalEnergyBurned.doubleValue(for: .kilocalorie()),
                    unit: "kcal"
                )
            ))
        }

        if let totalDistance = workout.totalDistance {
            components.append(HealthingComponent(
                code: "41953-1", // Distance LOINC
                valueQuantity: HealthingQuantity(
                    value: totalDistance.doubleValue(for: .meter()),
                    unit: "m"
                )
            ))
        }

        // Add workout metadata
        components.append(HealthingComponent(
            code: "LA11837-4", // Activity type
            valueCodeableConcept: HealthingCodeableConcept(
                coding: [HealthingCoding(code: "\(workout.workoutActivityType.rawValue)", display: workout.workoutActivityType.name)]
            )
        ))

        let updatedObservation = HealthingObservation(
            id: observation.id,
            status: observation.status,
            code: observation.code,
            subject: observation.subject,
            effectiveDateTime: observation.effectiveDateTime,
            valueQuantity: observation.valueQuantity,
            device: observation.device,
            component: components,
            category: observation.category
        )

        do {
            let resolvedObservation = try await conflictResolver.processObservation(updatedObservation)
            await dataProcessor.processWearableData(resolvedObservation, from: .appleWatch)

            print("⌚ Processed Apple Watch workout: \(workout.workoutActivityType.name) - \(workout.duration/60) min")
        } catch {
            print("❌ Failed to process watch workout: \(error)")
        }
    }

    // MARK: - Watch Communication

    /// Send message to Apple Watch app
    func sendMessageToWatch(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let wcSession = wcSession,
              wcSession.isReachable else {
            print("⌚ AppleWatchService: Watch not reachable")
            return
        }

        wcSession.sendMessage(message, replyHandler: replyHandler) { error in
            print("❌ AppleWatchService: Failed to send message to watch: \(error)")
        }
    }

    /// Transfer user info to Apple Watch
    func transferUserInfoToWatch(_ userInfo: [String: Any]) {
        guard let wcSession = wcSession else {
            print("⌚ AppleWatchService: Watch session not available")
            return
        }

        wcSession.transferUserInfo(userInfo)
        print("⌚ AppleWatchService: Transferred user info to watch")
    }

    /// Request battery level from Apple Watch
    func requestWatchBatteryLevel() {
        let message = [
            "request": "battery_level",
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessageToWatch(message) { [weak self] reply in
            if let batteryLevel = reply["battery_level"] as? Float {
                Task { @MainActor in
                    self?.watchBatteryLevel = batteryLevel
                }
            }
        }
    }

    /// Check if Apple Watch app is installed
    func checkWatchAppInstallation() {
        guard let wcSession = wcSession else { return }

        watchAppInstalled = wcSession.isWatchAppInstalled
        print("⌚ AppleWatchService: Watch app installed: \(watchAppInstalled)")
    }

    // MARK: - Manual Sync

    /// Trigger manual sync of Apple Watch data
    func manualSync() async {
        print("⌚ AppleWatchService: Starting manual Apple Watch sync...")

        startWatchHealthMonitoringIfAuthorized()
        guard canStartMonitoring() else {
            print("⌚ AppleWatchService: HealthKit not authorized; skipping manual sync")
            return
        }

        let syncStart = lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())

        // Process all authorized watch health data types
        for quantityType in authorizedWatchHealthTypes() {
            await processWatchHealthUpdate(for: quantityType, since: syncStart, updateLastSync: false)
        }

        // Process workouts if authorized
        if provider.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized {
            await processWatchWorkouts(since: syncStart, updateLastSync: false)
        }

        // Request current battery level
        requestWatchBatteryLevel()

        await MainActor.run {
            lastSyncDate = Date()
        }

        print("✅ AppleWatchService: Manual sync completed")
    }

    /// Get Apple Watch device status
    func getWatchDeviceStatus() -> WatchDeviceStatus {
        return WatchDeviceStatus(
            isConnected: isWatchConnected,
            connectionState: watchConnectionState,
            batteryLevel: watchBatteryLevel,
            appInstalled: watchAppInstalled,
            reachable: watchReachable,
            lastSyncDate: lastSyncDate
        )
    }

    // MARK: - Device Filtering

    private func isAppleWatchSample(_ sample: HKSample) -> Bool {
        if let metadataSource = sample.metadata?[HealthingSampleMetadataKey.source] as? String {
            return metadataSource == HealthingSampleSource.appleWatch.rawValue
        }

        guard let device = sample.device else { return provider.isMock }
        let identifiers = [
            device.name,
            device.model,
            device.localizedModel
        ].compactMap { $0?.lowercased() }

        return identifiers.contains { $0.contains("watch") }
    }

    private func authorizedWatchHealthTypes() -> [HKQuantityType] {
        watchHealthTypes.filter { provider.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    private func doubleValue(from value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let intValue = value as? Int { return Double(intValue) }
        if let numberValue = value as? NSNumber { return numberValue.doubleValue }
        return nil
    }
}

// MARK: - WCSessionDelegate
extension AppleWatchService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.watchConnectionState = activationState
            self.isWatchConnected = activationState == .activated

            if let error = error {
                print("❌ AppleWatchService: Watch session activation failed: \(error)")
            } else {
                print("✅ AppleWatchService: Watch session activated with state: \(activationState.rawValue)")

                // Check initial states
                self.checkWatchAppInstallation()
                self.requestWatchBatteryLevel()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("⌚ AppleWatchService: Watch session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("⌚ AppleWatchService: Watch session deactivated")
        // Reactivate session
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.watchReachable = session.isReachable
            print("⌚ AppleWatchService: Watch reachability changed: \(session.isReachable)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("⌚ AppleWatchService: Received message from watch: \(message)")

        guard let messageType = message["type"] as? String else {
            replyHandler(["status": "error", "message": "Missing message type"])
            return
        }

        switch messageType {
        case "healthDataSync":
            Task {
                await handleHealthDataSync(message: message, replyHandler: replyHandler)
            }
        case "healthReading":
            Task {
                await handleHealthReading(message: message)
                replyHandler(["status": "reading_received", "timestamp": Date().timeIntervalSince1970])
            }
        case "dataRequest":
            Task {
                await handleDataRequest(replyHandler: replyHandler)
            }
        default:
            print("⌚ AppleWatchService: Unknown message type: \(messageType)")
            replyHandler(["status": "unknown_message_type", "type": messageType])
        }
    }

    /// Handle health data sync from Apple Watch
    private func handleHealthDataSync(message: [String: Any], replyHandler: @escaping ([String : Any]) -> Void) async {
        print("⌚ AppleWatchService: Processing health data sync from watch...")

        guard let data = message["data"] as? [String: Any] else {
            replyHandler(["status": "error", "message": "Missing health data"])
            return
        }

        do {
            // Process heart rate data
            if let heartRateData = data["heartRate"] as? [String: Any],
               let value = doubleValue(from: heartRateData["value"]),
               let timestamp = heartRateData["timestamp"] as? TimeInterval {

                let observation = HealthingObservation(
                    id: UUID().uuidString,
                    status: "final",
                    code: "8867-4", // Heart rate LOINC
                    subject: "patient",
                    effectiveDateTime: Date(timeIntervalSince1970: timestamp),
                    valueQuantity: HealthingQuantity(value: value, unit: "beats/min"),
                    device: HealthingDevice.appleWatchDevice(),
                    category: "vital-signs"
                )

                let resolvedObservation = try await conflictResolver.processObservation(observation)
                await dataProcessor.processWearableData(resolvedObservation, from: .appleWatch)
            }

            // Process steps data
            if let stepsData = data["steps"] as? [String: Any],
               let value = doubleValue(from: stepsData["value"]),
               let timestamp = stepsData["timestamp"] as? TimeInterval {

                let observation = HealthingObservation(
                    id: UUID().uuidString,
                    status: "final",
                    code: "55423-8", // Number of steps LOINC
                    subject: "patient",
                    effectiveDateTime: Date(timeIntervalSince1970: timestamp),
                    valueQuantity: HealthingQuantity(value: value, unit: "steps"),
                    device: HealthingDevice.appleWatchDevice(),
                    category: "activity"
                )

                let resolvedObservation = try await conflictResolver.processObservation(observation)
                await dataProcessor.processWearableData(resolvedObservation, from: .appleWatch)
            }

            // Process active energy data
            if let activeEnergyData = data["activeEnergy"] as? [String: Any],
               let value = doubleValue(from: activeEnergyData["value"]),
               let timestamp = activeEnergyData["timestamp"] as? TimeInterval {

                let observation = HealthingObservation(
                    id: UUID().uuidString,
                    status: "final",
                    code: "41981-2", // Active energy burned LOINC
                    subject: "patient",
                    effectiveDateTime: Date(timeIntervalSince1970: timestamp),
                    valueQuantity: HealthingQuantity(value: value, unit: "kcal"),
                    device: HealthingDevice.appleWatchDevice(),
                    category: "activity"
                )

                let resolvedObservation = try await conflictResolver.processObservation(observation)
                await dataProcessor.processWearableData(resolvedObservation, from: .appleWatch)
            }

            await MainActor.run {
                self.lastSyncDate = Date()
            }

            replyHandler([
                "status": "sync_completed",
                "timestamp": Date().timeIntervalSince1970,
                "processed_metrics": ["heartRate", "steps", "activeEnergy"]
            ])

            print("✅ AppleWatchService: Successfully processed health data sync from watch")

        } catch {
            print("❌ AppleWatchService: Failed to process health data sync: \(error)")
            replyHandler(["status": "sync_failed", "error": error.localizedDescription])
        }
    }

    /// Handle individual health reading from Apple Watch
    private func handleHealthReading(message: [String: Any]) async {
        guard let readingData = message["data"] as? [String: Any] else {
            print("❌ AppleWatchService: Missing reading data")
            return
        }

        print("⌚ AppleWatchService: Processing health reading from watch...")

        guard let readingType = readingData["type"] as? String,
              let value = doubleValue(from: readingData["value"]),
              let timestamp = readingData["timestamp"] as? TimeInterval else {
            print("❌ AppleWatchService: Invalid reading payload")
            return
        }

        let unit = (readingData["unit"] as? String) ?? ""
        let (code, fallbackUnit, category): (String, String, String)

        switch readingType {
        case "heartRate":
            code = "8867-4"
            fallbackUnit = "beats/min"
            category = "vital-signs"
        case "steps":
            code = "55423-8"
            fallbackUnit = "steps"
            category = "activity"
        case "activeEnergy":
            code = "41981-2"
            fallbackUnit = "kcal"
            category = "activity"
        default:
            print("❌ AppleWatchService: Unsupported reading type: \(readingType)")
            return
        }

        let observation = HealthingObservation(
            id: UUID().uuidString,
            status: "final",
            code: code,
            subject: "patient",
            effectiveDateTime: Date(timeIntervalSince1970: timestamp),
            valueQuantity: HealthingQuantity(value: value, unit: unit.isEmpty ? fallbackUnit : unit),
            device: HealthingDevice.appleWatchDevice(),
            category: category
        )

        do {
            let resolvedObservation = try await conflictResolver.processObservation(observation)
            await dataProcessor.processWearableData(resolvedObservation, from: .appleWatch)
        } catch {
            print("❌ AppleWatchService: Failed to process health reading: \(error)")
        }
    }

    /// Handle data request from Apple Watch
    private func handleDataRequest(replyHandler: @escaping ([String : Any]) -> Void) async {
        print("⌚ AppleWatchService: Handling data request from watch...")

        // Respond with current health data summary
        let response: [String: Any] = [
            "status": "data_provided",
            "timestamp": Date().timeIntervalSince1970,
            "data": [
                "sync_enabled": true,
                "last_sync": lastSyncDate?.timeIntervalSince1970 ?? 0,
                "battery_requested": true
            ]
        ]

        replyHandler(response)

        // Request battery level from watch
        requestWatchBatteryLevel()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        print("⌚ AppleWatchService: Received user info from watch: \(userInfo)")
        // Handle background user info transfers from watch
    }
}

// MARK: - Supporting Types
struct WatchDeviceStatus {
    let isConnected: Bool
    let connectionState: WCSessionActivationState
    let batteryLevel: Float
    let appInstalled: Bool
    let reachable: Bool
    let lastSyncDate: Date?

    var statusDescription: String {
        switch connectionState {
        case .activated:
            return reachable ? "Connected" : "Connected (Not Reachable)"
        case .inactive:
            return "Inactive"
        case .notActivated:
            return "Not Activated"
        @unknown default:
            return "Unknown"
        }
    }

    var batteryPercentage: String {
        return "\(Int(batteryLevel * 100))%"
    }
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .hiking: return "Hiking"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .dance: return "Dance"
        case .crossTraining: return "Cross Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        default: return "Workout"
        }
    }
}
