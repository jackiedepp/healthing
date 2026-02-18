import Foundation
import HealthKit

enum HealthingSampleSource: String {
    case appleWatch = "apple_watch"
    case phone = "phone"
}

enum HealthingSampleMetadataKey {
    static let source = "healthing_sample_source"
}

protocol HealthKitProviding {
    var isMock: Bool { get }

    func isHealthDataAvailable() -> Bool
    func authorizationStatus(for sampleType: HKSampleType) -> HKAuthorizationStatus
    func requestAuthorization(read types: Set<HKSampleType>) async throws

    func startObserver(for sampleType: HKSampleType, handler: @escaping (Error?) -> Void) -> AnyObject?
    func stopObserver(_ token: AnyObject)

    func fetchQuantitySamples(
        of type: HKQuantityType,
        startDate: Date,
        endDate: Date
    ) async throws -> [HKQuantitySample]

    func fetchCategorySamples(
        of type: HKCategoryType,
        startDate: Date,
        endDate: Date
    ) async throws -> [HKCategorySample]

    func fetchWorkouts(startDate: Date) async throws -> [HKWorkout]
}

enum HealthKitProviderFactory {
    static func makeProvider(source: HealthingSampleSource) -> HealthKitProviding {
        if shouldUseMockProvider {
            return MockHealthKitProvider(source: source)
        }
        return RealHealthKitProvider()
    }

    private static var shouldUseMockProvider: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        let env = ProcessInfo.processInfo.environment
        return env["HEALTHING_MOCK_HEALTHKIT"] == "1" || env["CI"] == "1"
        #endif
    }
}

final class RealHealthKitProvider: HealthKitProviding {
    let isMock = false
    private let healthStore = HKHealthStore()

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationStatus(for sampleType: HKSampleType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: sampleType)
    }

    func requestAuthorization(read types: Set<HKSampleType>) async throws {
        try await healthStore.requestAuthorization(toShare: [], read: types)
    }

    func startObserver(for sampleType: HKSampleType, handler: @escaping (Error?) -> Void) -> AnyObject? {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
            handler(error)
            completionHandler()
        }
        healthStore.execute(query)
        return query
    }

    func stopObserver(_ token: AnyObject) {
        if let query = token as? HKObserverQuery {
            healthStore.stop(query)
        }
    }

    func fetchQuantitySamples(
        of type: HKQuantityType,
        startDate: Date,
        endDate: Date
    ) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchCategorySamples(
        of type: HKCategoryType,
        startDate: Date,
        endDate: Date
    ) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchWorkouts(startDate: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }
    }
}

final class MockHealthKitProvider: HealthKitProviding {
    let isMock = true
    private let source: HealthingSampleSource

    init(source: HealthingSampleSource) {
        self.source = source
    }

    func isHealthDataAvailable() -> Bool { true }

    func authorizationStatus(for sampleType: HKSampleType) -> HKAuthorizationStatus {
        .sharingAuthorized
    }

    func requestAuthorization(read types: Set<HKSampleType>) async throws { }

    func startObserver(for sampleType: HKSampleType, handler: @escaping (Error?) -> Void) -> AnyObject? {
        let token = NSObject()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            handler(nil)
        }
        return token
    }

    func stopObserver(_ token: AnyObject) { }

    func fetchQuantitySamples(
        of type: HKQuantityType,
        startDate: Date,
        endDate: Date
    ) async throws -> [HKQuantitySample] {
        let samples = MockHealthKitSampleFactory.quantitySamples(for: type, source: source)
        return samples.filter { $0.startDate >= startDate && $0.startDate <= endDate }
    }

    func fetchCategorySamples(
        of type: HKCategoryType,
        startDate: Date,
        endDate: Date
    ) async throws -> [HKCategorySample] {
        let samples = MockHealthKitSampleFactory.categorySamples(for: type, source: source)
        return samples.filter { $0.startDate >= startDate && $0.startDate <= endDate }
    }

    func fetchWorkouts(startDate: Date) async throws -> [HKWorkout] {
        let samples = MockHealthKitSampleFactory.workouts(source: source)
        return samples.filter { $0.startDate >= startDate }
    }
}

enum MockHealthKitSampleFactory {
    static func quantitySamples(for type: HKQuantityType, source: HealthingSampleSource) -> [HKQuantitySample] {
        let now = Date()
        let metadata = [HealthingSampleMetadataKey.source: source.rawValue]
        let values: [Double]
        let unit: HKUnit

        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            values = [68, 72, 75, 71, 69]
            unit = HKUnit(from: "count/min")
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            values = [1200, 2400, 3200, 4100, 5200]
            unit = HKUnit.count()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            values = [120, 180, 240, 300, 360]
            unit = HKUnit.kilocalorie()
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            values = [300, 900, 1500, 2100, 2800]
            unit = HKUnit.meter()
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            values = [97, 98, 96, 97, 98]
            unit = HKUnit.percent()
        default:
            values = [1, 2, 3, 4, 5]
            unit = HKUnit.count()
        }

        return values.enumerated().map { index, value in
            let start = Calendar.current.date(byAdding: .minute, value: -index * 10, to: now) ?? now
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            return HKQuantitySample(
                type: type,
                quantity: quantity,
                start: start,
                end: start,
                metadata: metadata
            )
        }
    }

    static func categorySamples(for type: HKCategoryType, source: HealthingSampleSource) -> [HKCategorySample] {
        let now = Date()
        let metadata = [HealthingSampleMetadataKey.source: source.rawValue]

        if type.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            let start = Calendar.current.date(byAdding: .hour, value: -8, to: now) ?? now
            return [
                HKCategorySample(
                    type: type,
                    value: HKCategoryValueSleepAnalysis.asleep.rawValue,
                    start: start,
                    end: now,
                    metadata: metadata
                )
            ]
        }

        return []
    }

    static func workouts(source: HealthingSampleSource) -> [HKWorkout] {
        let now = Date()
        let metadata = [HealthingSampleMetadataKey.source: source.rawValue]
        let start = Calendar.current.date(byAdding: .minute, value: -45, to: now) ?? now

        return [
            HKWorkout(
                activityType: .running,
                start: start,
                end: now,
                duration: 45 * 60,
                totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 300),
                totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
                metadata: metadata
            )
        ]
    }
}
