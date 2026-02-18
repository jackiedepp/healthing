import XCTest
import HealthKit
@testable import HealthingApp

final class MockHealthKitProviderTests: XCTestCase {

    func testMockProviderAuthorizationAndAvailability() async throws {
        let provider = MockHealthKitProvider(source: .appleWatch)
        XCTAssertTrue(provider.isMock, "Mock provider should report isMock = true")
        XCTAssertTrue(provider.isHealthDataAvailable(), "Mock provider should always be available")

        let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let status = provider.authorizationStatus(for: heartRate)
        XCTAssertEqual(status, .sharingAuthorized, "Mock provider should always be authorized")
    }

    func testMockProviderQuantitySamplesMetadata() async throws {
        let provider = MockHealthKitProvider(source: .appleWatch)
        let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let samples = try await provider.fetchQuantitySamples(
            of: heartRate,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date()
        )

        XCTAssertEqual(samples.count, 5, "Mock provider should return 5 heart rate samples")

        for sample in samples {
            let source = sample.metadata?[HealthingSampleMetadataKey.source] as? String
            XCTAssertEqual(source, HealthingSampleSource.appleWatch.rawValue, "Sample metadata should include source")
        }
    }

    func testMockProviderWorkoutMetadata() async throws {
        let provider = MockHealthKitProvider(source: .phone)
        let workouts = try await provider.fetchWorkouts(startDate: Date().addingTimeInterval(-3600))

        XCTAssertEqual(workouts.count, 1, "Mock provider should return one workout")
        let source = workouts.first?.metadata?[HealthingSampleMetadataKey.source] as? String
        XCTAssertEqual(source, HealthingSampleSource.phone.rawValue, "Workout metadata should include source")
    }

    func testMockProviderDateFiltering() async throws {
        let provider = MockHealthKitProvider(source: .appleWatch)
        let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let startDate = Date().addingTimeInterval(-900) // last 15 minutes
        let samples = try await provider.fetchQuantitySamples(
            of: heartRate,
            startDate: startDate,
            endDate: Date()
        )

        XCTAssertEqual(samples.count, 2, "Mock provider should return samples within the date range")
    }

    func testMockProviderCategorySamples() async throws {
        let provider = MockHealthKitProvider(source: .appleWatch)
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!

        let samples = try await provider.fetchCategorySamples(
            of: sleepType,
            startDate: Date().addingTimeInterval(-12 * 3600),
            endDate: Date()
        )

        XCTAssertEqual(samples.count, 1, "Mock provider should return one sleep sample")
        let source = samples.first?.metadata?[HealthingSampleMetadataKey.source] as? String
        XCTAssertEqual(source, HealthingSampleSource.appleWatch.rawValue, "Sleep sample metadata should include source")
    }
}
