import Foundation
import HealthKit
import SwiftUI
import Combine

/// Real-time HealthKit synchronization service with background observers
/// Implements REQ-019: Real-time HealthKit sync of vital signs, workouts, and health metrics
/// Implements REQ-020: Background processing for continuous data collection
@MainActor
class HealthKitSyncService: ObservableObject {
    static let shared = HealthKitSyncService()

    private let provider: HealthKitProviding
    private let dataStore = HealthDataStore.shared
    private let securityManager = SecurityManager.shared

    @Published var isAuthorized = false
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var syncProgress: Double = 0.0
    @Published var errorMessage: String?

    // Background observers for real-time updates
    private var backgroundObservers: [AnyObject] = []
    private var anchoredObjectQueries: [String: HKAnchoredObjectQuery] = [:]

    // Supported HealthKit data types for sync
    private let healthKitTypes: Set<HKSampleType> = [
        // Vital Signs
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,

        // Body Measurements
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,

        // Activity & Fitness
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,

        // Sleep & Recovery
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,

        // Nutrition & Hydration
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!,

        // Workouts
        HKObjectType.workoutType()
    ]

    private init() {
        provider = HealthKitProviderFactory.makeProvider(source: .phone)
        checkHealthKitAuthorization()
    }

    /// Request HealthKit permissions and start sync
    func requestPermissions() async throws {
        guard provider.isHealthDataAvailable() else {
            throw HealthKitError.healthDataNotAvailable
        }

        try await provider.requestAuthorization(read: healthKitTypes)

        await MainActor.run {
            isAuthorized = true
            lastSyncDate = UserDefaults.standard.object(forKey: "lastHealthKitSync") as? Date
        }

        await startBackgroundObservers()
        await performInitialSync()
    }

    /// Check current HealthKit authorization status
    private func checkHealthKitAuthorization() {
        guard provider.isHealthDataAvailable() else { return }

        let authorized = healthKitTypes.allSatisfy { type in
            provider.authorizationStatus(for: type) == .sharingAuthorized
        }

        isAuthorized = authorized
    }

    /// Start background observers for real-time sync
    private func startBackgroundObservers() async {
        print("🔄 HealthKitSyncService: Starting background observers...")

        for healthKitType in healthKitTypes {
            await startObserver(for: healthKitType)
        }
    }

    /// Start background observer for a specific HealthKit type
    private func startObserver(for sampleType: HKSampleType) async {
        let token = provider.startObserver(for: sampleType) { [weak self] error in
            guard let self = self else { return }
            Task {
                if let error = error {
                    await MainActor.run {
                        self.errorMessage = "Observer error for \(sampleType.identifier): \(error.localizedDescription)"
                    }
                    return
                }

                await self.syncDataType(sampleType)
            }
        }

        if let token = token {
            backgroundObservers.append(token)
        }

        print("✅ HealthKitSyncService: Started observer for \(sampleType.identifier)")
    }

    /// Perform initial full sync of all HealthKit data
    private func performInitialSync() async {
        await MainActor.run {
            syncStatus = .syncing
            syncProgress = 0.0
        }

        print("🔄 HealthKitSyncService: Starting initial sync...")

        let totalTypes = Double(healthKitTypes.count)
        var completedTypes = 0.0

        for healthKitType in healthKitTypes {
            await syncDataType(healthKitType)

            completedTypes += 1
            await MainActor.run {
                syncProgress = completedTypes / totalTypes
            }
        }

        await MainActor.run {
            syncStatus = .completed
            syncProgress = 1.0
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastHealthKitSync")
        }

        print("✅ HealthKitSyncService: Initial sync completed")
    }

    /// Sync data for a specific HealthKit type
    private func syncDataType(_ sampleType: HKSampleType) async {
        let startDate = lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let endDate = Date()

        await withCheckedContinuation { continuation in
            if sampleType == HKObjectType.workoutType() {
                // Handle workouts separately
                syncWorkouts(from: startDate, endDate: endDate) {
                    continuation.resume()
                }
            } else if let quantityType = sampleType as? HKQuantityType {
                syncQuantityType(quantityType, startDate: startDate, endDate: endDate) {
                    continuation.resume()
                }
            } else if let categoryType = sampleType as? HKCategoryType {
                syncCategoryType(categoryType, startDate: startDate, endDate: endDate) {
                    continuation.resume()
                }
            } else {
                continuation.resume()
            }
        }
    }

    /// Sync quantity type data (vital signs, measurements, activity)
    private func syncQuantityType(_ quantityType: HKQuantityType, startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        Task {
            do {
                let samples = try await provider.fetchQuantitySamples(of: quantityType, startDate: startDate, endDate: endDate)
                for sample in samples {
                    await self.processQuantitySample(sample)
                }
            } catch {
                print("❌ Failed to sync quantity type \(quantityType.identifier): \(error)")
            }
            completion()
        }
    }

    /// Sync category type data (sleep analysis)
    private func syncCategoryType(_ categoryType: HKCategoryType, startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        Task {
            do {
                let samples = try await provider.fetchCategorySamples(of: categoryType, startDate: startDate, endDate: endDate)
                for sample in samples {
                    await self.processCategorySample(sample)
                }
            } catch {
                print("❌ Failed to sync category type \(categoryType.identifier): \(error)")
            }
            completion()
        }
    }

    /// Sync workout data
    private func syncWorkouts(from startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        Task {
            do {
                let workouts = try await provider.fetchWorkouts(startDate: startDate)
                let filteredWorkouts = workouts.filter { $0.duration >= 60 && $0.startDate <= endDate }
                for workout in filteredWorkouts {
                    await self.processWorkout(workout)
                }
            } catch {
                print("❌ Failed to sync workouts: \(error)")
            }
            completion()
        }
    }

    /// Process and store a quantity sample
    private func processQuantitySample(_ sample: HKQuantitySample) async {
        guard !isAppleWatchSample(sample) else { return }

        let loincCode = HealthKitMapping.getLoincCode(for: sample.quantityType.identifier)
        let unit = HealthKitMapping.getPreferredUnit(for: sample.quantityType.identifier)
        let value = sample.quantity.doubleValue(for: unit)

        let observation = HealthingObservation(
            id: sample.uuid.uuidString,
            status: "final",
            code: loincCode,
            subject: "patient", // Will be set by data store
            effectiveDateTime: sample.startDate,
            valueQuantity: HealthingQuantity(value: value, unit: unit.unitString),
            device: HealthingDevice.fromHealthKitDevice(sample.device),
            category: HealthKitMapping.getCategory(for: sample.quantityType.identifier)
        )

        do {
            try await dataStore.storeHealthObservation(observation)
            print("✅ Stored HealthKit sample: \(sample.quantityType.identifier) = \(value) \(unit.unitString)")
        } catch {
            print("❌ Failed to store HealthKit sample: \(error)")
        }
    }

    /// Process and store a category sample
    private func processCategorySample(_ sample: HKCategorySample) async {
        guard !isAppleWatchSample(sample) else { return }

        let loincCode = HealthKitMapping.getLoincCode(for: sample.categoryType.identifier)
        let valueString = HealthKitMapping.getCategoryValueString(for: sample.categoryType.identifier, value: sample.value)

        let observation = HealthingObservation(
            id: sample.uuid.uuidString,
            status: "final",
            code: loincCode,
            subject: "patient",
            effectiveDateTime: sample.startDate,
            valueCodeableConcept: HealthingCodeableConcept(
                coding: [HealthingCoding(code: "\(sample.value)", display: valueString)]
            ),
            device: HealthingDevice.fromHealthKitDevice(sample.device),
            category: HealthKitMapping.getCategory(for: sample.categoryType.identifier)
        )

        do {
            try await dataStore.storeHealthObservation(observation)
            print("✅ Stored HealthKit category: \(sample.categoryType.identifier) = \(valueString)")
        } catch {
            print("❌ Failed to store HealthKit category: \(error)")
        }
    }

    /// Process and store a workout
    private func processWorkout(_ workout: HKWorkout) async {
        guard !isAppleWatchSample(workout) else { return }

        // Store workout as observation with activity type and duration
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
            device: HealthingDevice.fromHealthKitDevice(workout.device),
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

        if !components.isEmpty {
            observation.component = components
        }

        do {
            try await dataStore.storeHealthObservation(observation)
            print("✅ Stored workout: \(workout.workoutActivityType.name) - \(workout.duration/60) min")
        } catch {
            print("❌ Failed to store workout: \(error)")
        }
    }

    /// Stop all background observers
    func stopBackgroundObservers() {
        for observer in backgroundObservers {
            provider.stopObserver(observer)
        }
        backgroundObservers.removeAll()
        anchoredObjectQueries.removeAll()
        print("🔄 HealthKitSyncService: Stopped all background observers")
    }

    /// Manual sync trigger
    func manualSync() async {
        await performInitialSync()
    }

    // MARK: - Device Filtering
    private func isAppleWatchSample(_ sample: HKSample) -> Bool {
        if let metadataSource = sample.metadata?[HealthingSampleMetadataKey.source] as? String {
            return metadataSource == HealthingSampleSource.appleWatch.rawValue
        }

        guard let device = sample.device else { return false }
        let identifiers = [
            device.name,
            device.model,
            device.localizedModel
        ].compactMap { $0?.lowercased() }

        return identifiers.contains { $0.contains("watch") }
    }
}

// MARK: - Supporting Types
enum SyncStatus {
    case idle
    case syncing
    case completed
    case error(String)
}

enum HealthKitError: LocalizedError {
    case healthDataNotAvailable
    case authorizationDenied
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "Health data is not available on this device"
        case .authorizationDenied:
            return "HealthKit access was denied"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}

// MARK: - HealthKit to FHIR Mapping
private struct HealthKitMapping {
    static func getLoincCode(for identifier: String) -> String {
        switch identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return "8867-4"
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue:
            return "8480-6"
        case HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return "8462-4"
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return "9279-1"
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return "2708-6"
        case HKQuantityTypeIdentifier.bodyTemperature.rawValue:
            return "8310-5"
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return "29463-7"
        case HKQuantityTypeIdentifier.height.rawValue:
            return "8302-2"
        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return "39156-5"
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return "55423-8"
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return "41981-2"
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            return "93832-4"
        default:
            return "LA6115-9" // Generic observation
        }
    }

    static func getPreferredUnit(for identifier: String) -> HKUnit {
        switch identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return HKUnit(from: "count/min")
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return HKUnit.millimeterOfMercury()
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return HKUnit(from: "count/min")
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return HKUnit.percent()
        case HKQuantityTypeIdentifier.bodyTemperature.rawValue:
            return HKUnit.degreeCelsius()
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return HKUnit.gramUnit(with: .kilo)
        case HKQuantityTypeIdentifier.height.rawValue:
            return HKUnit.meter()
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return HKUnit.count()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue:
            return HKUnit.kilocalorie()
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return HKUnit.meter()
        default:
            return HKUnit.count()
        }
    }

    static func getCategory(for identifier: String) -> String {
        switch identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue,
             HKQuantityTypeIdentifier.respiratoryRate.rawValue,
             HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
             HKQuantityTypeIdentifier.bodyTemperature.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return "vital-signs"
        case HKQuantityTypeIdentifier.bodyMass.rawValue,
             HKQuantityTypeIdentifier.height.rawValue,
             HKQuantityTypeIdentifier.bodyMassIndex.rawValue,
             HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return "body-measurement"
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
             HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return "activity"
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            return "sleep"
        case HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue,
             HKQuantityTypeIdentifier.dietaryWater.rawValue:
            return "nutrition"
        default:
            return "general"
        }
    }

    static func getCategoryValueString(for identifier: String, value: Int) -> String {
        switch identifier {
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            switch value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                return "In Bed"
            case HKCategoryValueSleepAnalysis.asleep.rawValue:
                return "Asleep"
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return "Awake"
            default:
                return "Unknown"
            }
        default:
            return "Value: \(value)"
        }
    }
}

// MARK: - Extensions
extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        default: return "Workout"
        }
    }
}
