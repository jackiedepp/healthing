import Foundation
import SwiftUI
import Combine

/// Smart conflict resolution service for overlapping health data from multiple sources
/// Implements REQ-021: Smart conflict resolution for overlapping data sources
/// Resolves conflicts between HealthKit, manual entry, and wearable device data
@MainActor
class ConflictResolutionService: ObservableObject {
    static let shared = ConflictResolutionService()

    @Published var conflictResolutionStrategy: ConflictStrategy = .prioritizeDevice
    @Published var pendingConflicts: [DataConflict] = []
    @Published var resolvedConflictsCount = 0
    @Published var autoResolutionEnabled = true

    private let dataStore = HealthDataStore.shared

    // Data source priority hierarchy (higher number = higher priority)
    private let sourcePriority: [String: Int] = [
        "apple-watch": 90,
        "garmin-device": 85,
        "fitbit-device": 80,
        "manual-entry": 70,
        "healthkit-app": 60,
        "third-party-app": 50,
        "imported-data": 40,
        "estimated": 30
    ]

    private init() {}

    /// Detect and resolve conflicts for new health observation
    func processObservation(_ observation: HealthingObservation) async throws -> HealthingObservation {
        let conflicts = await detectConflicts(for: observation)

        if conflicts.isEmpty {
            // No conflicts, store as-is
            return observation
        }

        print("🔍 ConflictResolutionService: Detected \(conflicts.count) conflicts for \(observation.code)")

        if autoResolutionEnabled {
            // Attempt automatic resolution
            return try await resolveConflictsAutomatically(observation: observation, conflicts: conflicts)
        } else {
            // Add to pending conflicts for manual resolution
            let conflict = DataConflict(
                id: UUID().uuidString,
                newObservation: observation,
                conflictingObservations: conflicts,
                detectedAt: Date(),
                resolutionStrategy: conflictResolutionStrategy
            )

            pendingConflicts.append(conflict)
            return observation
        }
    }

    /// Detect conflicting observations for a new observation
    private func detectConflicts(for observation: HealthingObservation) async -> [HealthingObservation] {
        // Define time window for conflict detection based on measurement type
        let timeWindow = getConflictTimeWindow(for: observation.code)
        let startTime = observation.effectiveDateTime.addingTimeInterval(-timeWindow)
        let endTime = observation.effectiveDateTime.addingTimeInterval(timeWindow)

        do {
            // Fetch existing observations in the time window with same measurement type
            let existingObservations = try await dataStore.fetchHealthObservations(
                category: observation.category,
                dateRange: startTime...endTime,
                limit: 50
            )

            // Filter for same measurement type (LOINC code)
            let conflicting = existingObservations.filter { existing in
                existing.id != observation.id &&
                existing.code == observation.code &&
                abs(existing.effectiveDateTime.timeIntervalSince(observation.effectiveDateTime)) < timeWindow
            }

            return conflicting

        } catch {
            print("❌ ConflictResolutionService: Failed to detect conflicts: \(error)")
            return []
        }
    }

    /// Get appropriate time window for conflict detection based on measurement type
    private func getConflictTimeWindow(for loincCode: String) -> TimeInterval {
        switch loincCode {
        case "8867-4": // Heart rate
            return 60 // 1 minute window
        case "8480-6", "8462-4": // Blood pressure
            return 300 // 5 minute window
        case "8310-5": // Body temperature
            return 600 // 10 minute window
        case "29463-7": // Body weight
            return 3600 // 1 hour window
        case "8302-2": // Height
            return 86400 // 24 hour window (height doesn't change often)
        case "55423-8": // Step count
            return 3600 // 1 hour window for step aggregation
        case "41981-2": // Active energy
            return 900 // 15 minute window
        case "93832-4": // Sleep analysis
            return 1800 // 30 minute window
        default:
            return 300 // Default 5 minute window
        }
    }

    /// Automatically resolve conflicts based on configured strategy
    private func resolveConflictsAutomatically(
        observation: HealthingObservation,
        conflicts: [HealthingObservation]
    ) async throws -> HealthingObservation {

        switch conflictResolutionStrategy {
        case .prioritizeDevice:
            return resolveByDevicePriority(observation: observation, conflicts: conflicts)

        case .prioritizeRecent:
            return resolveByRecency(observation: observation, conflicts: conflicts)

        case .averageValues:
            return try resolveByAveraging(observation: observation, conflicts: conflicts)

        case .prioritizeAccuracy:
            return resolveByAccuracy(observation: observation, conflicts: conflicts)

        case .userPreference:
            return resolveByUserPreference(observation: observation, conflicts: conflicts)

        case .manual:
            // Should not auto-resolve in manual mode
            return observation
        }
    }

    /// Resolve conflicts by device/source priority
    private func resolveByDevicePriority(observation: HealthingObservation, conflicts: [HealthingObservation]) -> HealthingObservation {
        let allObservations = [observation] + conflicts
        let sorted = allObservations.sorted { obs1, obs2 in
            let priority1 = getSourcePriority(for: obs1)
            let priority2 = getSourcePriority(for: obs2)
            return priority1 > priority2
        }

        let winner = sorted.first!
        print("✅ ConflictResolutionService: Resolved by device priority - winner: \(getSourceName(for: winner))")

        // Mark conflicting observations as superseded
        for conflict in conflicts where conflict.id != winner.id {
            Task {
                await markObservationAsSuperseded(conflict, supersededBy: winner.id)
            }
        }

        resolvedConflictsCount += 1
        return winner
    }

    /// Resolve conflicts by recency (most recent wins)
    private func resolveByRecency(observation: HealthingObservation, conflicts: [HealthingObservation]) -> HealthingObservation {
        let allObservations = [observation] + conflicts
        let mostRecent = allObservations.max(by: { $0.effectiveDateTime < $1.effectiveDateTime })!

        print("✅ ConflictResolutionService: Resolved by recency - winner from \(mostRecent.effectiveDateTime)")

        resolvedConflictsCount += 1
        return mostRecent
    }

    /// Resolve conflicts by averaging values
    private func resolveByAveraging(observation: HealthingObservation, conflicts: [HealthingObservation]) throws -> HealthingObservation {
        let allObservations = [observation] + conflicts

        // Only average if all observations have numeric values
        guard allObservations.allSatisfy({ $0.valueQuantity != nil }) else {
            return resolveByDevicePriority(observation: observation, conflicts: conflicts)
        }

        let values = allObservations.compactMap { $0.valueQuantity?.value }
        let averageValue = values.reduce(0, +) / Double(values.count)

        var resolvedObservation = observation
        resolvedObservation.valueQuantity?.value = averageValue

        // Add note about averaging
        let sourceNames = allObservations.map { getSourceName(for: $0) }.joined(separator: ", ")
        resolvedObservation.note = "Averaged from \(values.count) sources: \(sourceNames)"

        print("✅ ConflictResolutionService: Resolved by averaging - result: \(averageValue)")

        resolvedConflictsCount += 1
        return resolvedObservation
    }

    /// Resolve conflicts by accuracy/reliability
    private func resolveByAccuracy(observation: HealthingObservation, conflicts: [HealthingObservation]) -> HealthingObservation {
        let allObservations = [observation] + conflicts

        // Prioritize observations with accuracy metadata or from high-precision devices
        let sorted = allObservations.sorted { obs1, obs2 in
            let accuracy1 = getAccuracyScore(for: obs1)
            let accuracy2 = getAccuracyScore(for: obs2)
            return accuracy1 > accuracy2
        }

        let winner = sorted.first!
        print("✅ ConflictResolutionService: Resolved by accuracy - winner: \(getSourceName(for: winner))")

        resolvedConflictsCount += 1
        return winner
    }

    /// Resolve conflicts by user preference settings
    private func resolveByUserPreference(observation: HealthingObservation, conflicts: [HealthingObservation]) -> HealthingObservation {
        // Get user's preferred sources from settings
        let preferredSources = getUserPreferredSources()
        let allObservations = [observation] + conflicts

        for preferredSource in preferredSources {
            if let preferred = allObservations.first(where: { getSourceName(for: $0) == preferredSource }) {
                print("✅ ConflictResolutionService: Resolved by user preference - winner: \(preferredSource)")
                resolvedConflictsCount += 1
                return preferred
            }
        }

        // Fallback to device priority if no preferred source found
        return resolveByDevicePriority(observation: observation, conflicts: conflicts)
    }

    /// Get source priority score for an observation
    private func getSourcePriority(for observation: HealthingObservation) -> Int {
        let sourceName = getSourceName(for: observation)
        return sourcePriority[sourceName] ?? 10
    }

    /// Get accuracy score for an observation
    private func getAccuracyScore(for observation: HealthingObservation) -> Int {
        let sourceName = getSourceName(for: observation)

        switch sourceName {
        case "apple-watch":
            return 95 // High accuracy for medical-grade sensors
        case "garmin-device":
            return 90
        case "manual-entry":
            return 85 // Assumes user entered carefully
        case "fitbit-device":
            return 80
        case "healthkit-app":
            return 75
        case "third-party-app":
            return 60
        case "imported-data":
            return 50
        case "estimated":
            return 30
        default:
            return 40
        }
    }

    /// Extract source name from observation
    private func getSourceName(for observation: HealthingObservation) -> String {
        if let device = observation.device {
            switch device.type {
            case "apple-watch":
                return "apple-watch"
            case "garmin":
                return "garmin-device"
            case "fitbit":
                return "fitbit-device"
            default:
                return device.type
            }
        } else if observation.performer?.contains("manual") == true {
            return "manual-entry"
        } else {
            return "healthkit-app"
        }
    }

    /// Mark observation as superseded by another observation
    private func markObservationAsSuperseded(_ observation: HealthingObservation, supersededBy winnerID: String) async {
        // Update observation status to indicate it was superseded
        var updatedObservation = observation
        updatedObservation.status = "superseded"
        updatedObservation.note = "Superseded by observation \(winnerID) via conflict resolution"

        do {
            try await dataStore.updateHealthObservation(updatedObservation)
            print("📝 ConflictResolutionService: Marked observation \(observation.id) as superseded")
        } catch {
            print("❌ ConflictResolutionService: Failed to mark observation as superseded: \(error)")
        }
    }

    /// Get user's preferred data sources from settings
    private func getUserPreferredSources() -> [String] {
        let defaults = UserDefaults.standard
        return defaults.stringArray(forKey: "preferredDataSources") ?? [
            "apple-watch",
            "garmin-device",
            "manual-entry",
            "healthkit-app"
        ]
    }

    /// Manually resolve a pending conflict
    func resolvePendingConflict(_ conflictID: String, selectedObservationID: String) async throws {
        guard let conflictIndex = pendingConflicts.firstIndex(where: { $0.id == conflictID }) else {
            throw ConflictResolutionError.conflictNotFound
        }

        let conflict = pendingConflicts[conflictIndex]
        let allObservations = [conflict.newObservation] + conflict.conflictingObservations

        guard let selectedObservation = allObservations.first(where: { $0.id == selectedObservationID }) else {
            throw ConflictResolutionError.observationNotFound
        }

        // Mark other observations as superseded
        for observation in allObservations where observation.id != selectedObservationID {
            await markObservationAsSuperseded(observation, supersededBy: selectedObservationID)
        }

        // Store the selected observation
        try await dataStore.storeHealthObservation(selectedObservation)

        // Remove from pending conflicts
        pendingConflicts.remove(at: conflictIndex)
        resolvedConflictsCount += 1

        print("✅ ConflictResolutionService: Manually resolved conflict \(conflictID)")
    }

    /// Clear all pending conflicts (accept all new observations)
    func clearAllPendingConflicts() async {
        for conflict in pendingConflicts {
            do {
                try await dataStore.storeHealthObservation(conflict.newObservation)
            } catch {
                print("❌ ConflictResolutionService: Failed to store observation during cleanup: \(error)")
            }
        }

        pendingConflicts.removeAll()
        print("🧹 ConflictResolutionService: Cleared all pending conflicts")
    }

    /// Update conflict resolution strategy
    func updateStrategy(_ strategy: ConflictStrategy) {
        conflictResolutionStrategy = strategy
        UserDefaults.standard.set(strategy.rawValue, forKey: "conflictResolutionStrategy")
        print("⚙️ ConflictResolutionService: Updated strategy to \(strategy.rawValue)")
    }

    /// Get conflict resolution statistics
    func getConflictStats() -> ConflictResolutionStats {
        return ConflictResolutionStats(
            strategy: conflictResolutionStrategy,
            pendingCount: pendingConflicts.count,
            resolvedCount: resolvedConflictsCount,
            autoResolutionEnabled: autoResolutionEnabled
        )
    }
}

// MARK: - Supporting Types
enum ConflictStrategy: String, CaseIterable {
    case prioritizeDevice = "device_priority"
    case prioritizeRecent = "most_recent"
    case averageValues = "average_values"
    case prioritizeAccuracy = "highest_accuracy"
    case userPreference = "user_preference"
    case manual = "manual_resolution"

    var displayName: String {
        switch self {
        case .prioritizeDevice:
            return "Prioritize Device Quality"
        case .prioritizeRecent:
            return "Use Most Recent"
        case .averageValues:
            return "Average Values"
        case .prioritizeAccuracy:
            return "Highest Accuracy"
        case .userPreference:
            return "User Preference"
        case .manual:
            return "Manual Resolution"
        }
    }

    var description: String {
        switch self {
        case .prioritizeDevice:
            return "Prefer data from higher-quality devices (Apple Watch > Garmin > Manual)"
        case .prioritizeRecent:
            return "Always use the most recently recorded measurement"
        case .averageValues:
            return "Calculate average of conflicting numeric values"
        case .prioritizeAccuracy:
            return "Choose the most accurate source based on device capabilities"
        case .userPreference:
            return "Use your preferred data sources in order"
        case .manual:
            return "Review each conflict manually before resolving"
        }
    }
}

struct DataConflict: Identifiable {
    let id: String
    let newObservation: HealthingObservation
    let conflictingObservations: [HealthingObservation]
    let detectedAt: Date
    let resolutionStrategy: ConflictStrategy

    var measurementType: String {
        switch newObservation.code {
        case "8867-4": return "Heart Rate"
        case "8480-6": return "Blood Pressure (Systolic)"
        case "8462-4": return "Blood Pressure (Diastolic)"
        case "29463-7": return "Body Weight"
        case "55423-8": return "Step Count"
        default: return "Health Measurement"
        }
    }

    var conflictDescription: String {
        let sources = conflictingObservations.map { observation in
            ConflictResolutionService.shared.getSourceName(for: observation)
        }.joined(separator: ", ")
        return "Multiple sources recorded \(measurementType): \(sources)"
    }
}

struct ConflictResolutionStats {
    let strategy: ConflictStrategy
    let pendingCount: Int
    let resolvedCount: Int
    let autoResolutionEnabled: Bool

    var efficiencyRate: Double {
        let total = pendingCount + resolvedCount
        return total > 0 ? Double(resolvedCount) / Double(total) : 0.0
    }
}

enum ConflictResolutionError: LocalizedError {
    case conflictNotFound
    case observationNotFound
    case resolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .conflictNotFound:
            return "Conflict not found"
        case .observationNotFound:
            return "Observation not found in conflict"
        case .resolutionFailed(let message):
            return "Resolution failed: \(message)"
        }
    }
}