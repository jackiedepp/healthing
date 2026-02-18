import Foundation
import HealthKit

/// Simplified health data models for internal use by HealthingApp services
/// These complement the FHIR models but are optimized for app performance and service integration

// MARK: - Core Health Data Structures

/// Simplified health observation for internal processing
struct HealthingObservation: Codable, Identifiable, Hashable {
    let id: String
    var status: String
    let code: String // LOINC code
    let subject: String
    let effectiveDateTime: Date
    var valueQuantity: HealthingQuantity?
    var valueCodeableConcept: HealthingCodeableConcept?
    var device: HealthingDevice?
    var component: [HealthingComponent]?
    let category: String
    var performer: String?
    var note: String?

    init(
        id: String = UUID().uuidString,
        status: String = "final",
        code: String,
        subject: String = "patient",
        effectiveDateTime: Date = Date(),
        valueQuantity: HealthingQuantity? = nil,
        valueCodeableConcept: HealthingCodeableConcept? = nil,
        device: HealthingDevice? = nil,
        component: [HealthingComponent]? = nil,
        category: String = "general"
    ) {
        self.id = id
        self.status = status
        self.code = code
        self.subject = subject
        self.effectiveDateTime = effectiveDateTime
        self.valueQuantity = valueQuantity
        self.valueCodeableConcept = valueCodeableConcept
        self.device = device
        self.component = component
        self.category = category
    }
}

/// Simplified quantity value
struct HealthingQuantity: Codable, Hashable {
    var value: Double
    let unit: String
    var comparator: String?

    init(value: Double, unit: String, comparator: String? = nil) {
        self.value = value
        self.unit = unit
        self.comparator = comparator
    }
}

/// Simplified codeable concept
struct HealthingCodeableConcept: Codable, Hashable {
    let coding: [HealthingCoding]
    let text: String?

    init(coding: [HealthingCoding], text: String? = nil) {
        self.coding = coding
        self.text = text
    }
}

/// Simplified coding
struct HealthingCoding: Codable, Hashable {
    let system: String?
    let code: String
    let display: String?

    init(system: String? = "http://loinc.org", code: String, display: String? = nil) {
        self.system = system
        self.code = code
        self.display = display
    }
}

/// Simplified observation component
struct HealthingComponent: Codable, Hashable {
    let code: String // LOINC code for component
    let valueQuantity: HealthingQuantity?
    let valueCodeableConcept: HealthingCodeableConcept?

    init(code: String, valueQuantity: HealthingQuantity? = nil, valueCodeableConcept: HealthingCodeableConcept? = nil) {
        self.code = code
        self.valueQuantity = valueQuantity
        self.valueCodeableConcept = valueCodeableConcept
    }
}

/// Device information for health measurements
struct HealthingDevice: Codable, Hashable, Identifiable {
    let id: String
    let identifier: String?
    let displayName: String
    let type: String
    let manufacturer: String?
    let modelNumber: String?
    let version: String?
    let status: String
    let patient: String?

    init(
        id: String = UUID().uuidString,
        identifier: String? = nil,
        displayName: String,
        type: String,
        manufacturer: String? = nil,
        modelNumber: String? = nil,
        version: String? = nil,
        status: String = "active",
        patient: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.type = type
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
        self.version = version
        self.status = status
        self.patient = patient
    }

    /// Pre-configured Apple Watch device
    static func appleWatchDevice() -> HealthingDevice {
        return HealthingDevice(
            id: "apple-watch-health",
            identifier: "Apple Watch",
            displayName: "Apple Watch",
            type: "apple-watch",
            manufacturer: "Apple Inc.",
            modelNumber: "Apple Watch",
            version: "watchOS",
            status: "active"
        )
    }

    /// Pre-configured Garmin device
    static func garminDevice(modelName: String = "Garmin Device") -> HealthingDevice {
        return HealthingDevice(
            id: "garmin-device-health",
            identifier: "Garmin Connect",
            displayName: modelName,
            type: "garmin",
            manufacturer: "Garmin Ltd.",
            modelNumber: modelName,
            version: "Garmin Connect",
            status: "active"
        )
    }

    /// Create device from HealthKit device info
    static func fromHealthKitDevice(_ hkDevice: HKDevice?) -> HealthingDevice? {
        guard let device = hkDevice else { return nil }

        let deviceType: String
        let manufacturer: String
        let displayName: String

        if let name = device.name {
            if name.contains("Apple Watch") {
                deviceType = "apple-watch"
                manufacturer = "Apple Inc."
                displayName = name
            } else if name.contains("iPhone") {
                deviceType = "iphone"
                manufacturer = "Apple Inc."
                displayName = name
            } else {
                deviceType = "unknown"
                manufacturer = "Unknown"
                displayName = name
            }
        } else {
            deviceType = "unknown"
            manufacturer = "Unknown"
            displayName = "Unknown Device"
        }

        return HealthingDevice(
            id: device.udiDeviceIdentifier ?? UUID().uuidString,
            identifier: device.udiDeviceIdentifier,
            displayName: displayName,
            type: deviceType,
            manufacturer: manufacturer,
            modelNumber: device.model,
            version: device.softwareVersion,
            status: "active"
        )
    }
}

/// Medical document reference
struct HealthingDocumentReference: Codable, Identifiable {
    let id: String
    let masterIdentifier: String?
    let status: String
    let type: String
    let category: String
    let subject: String
    let date: Date
    let author: [String]
    let description: String?
    let contentType: String
    let contentUrl: String?
    var ocrResults: OCRResult?
    var fileURL: URL?

    init(
        id: String = UUID().uuidString,
        masterIdentifier: String? = nil,
        status: String = "current",
        type: String = "medical-record",
        category: String = "clinical-note",
        subject: String = "patient",
        date: Date = Date(),
        author: [String] = [],
        description: String? = nil,
        contentType: String = "application/pdf",
        contentUrl: String? = nil
    ) {
        self.id = id
        self.masterIdentifier = masterIdentifier
        self.status = status
        self.type = type
        self.category = category
        self.subject = subject
        self.date = date
        self.author = author
        self.description = description
        self.contentType = contentType
        self.contentUrl = contentUrl
    }
}

// MARK: - Extensions for HealthKit Integration

extension HealthingObservation {
    /// Create from HealthKit quantity sample
    static func fromHealthKitQuantitySample(
        _ sample: HKQuantitySample,
        category: String = "vital-signs"
    ) -> HealthingObservation {
        let loincCode = HealthKitMapping.getLoincCode(for: sample.quantityType.identifier)
        let unit = HealthKitMapping.getPreferredUnit(for: sample.quantityType.identifier)
        let value = sample.quantity.doubleValue(for: unit)

        return HealthingObservation(
            id: sample.uuid.uuidString,
            status: "final",
            code: loincCode,
            subject: "patient",
            effectiveDateTime: sample.startDate,
            valueQuantity: HealthingQuantity(value: value, unit: unit.unitString),
            device: HealthingDevice.fromHealthKitDevice(sample.device),
            category: category
        )
    }

    /// Create from HealthKit category sample
    static func fromHealthKitCategorySample(
        _ sample: HKCategorySample,
        category: String = "activity"
    ) -> HealthingObservation {
        let loincCode = HealthKitMapping.getLoincCode(for: sample.categoryType.identifier)
        let valueString = HealthKitMapping.getCategoryValueString(
            for: sample.categoryType.identifier,
            value: sample.value
        )

        return HealthingObservation(
            id: sample.uuid.uuidString,
            status: "final",
            code: loincCode,
            subject: "patient",
            effectiveDateTime: sample.startDate,
            valueCodeableConcept: HealthingCodeableConcept(
                coding: [HealthingCoding(code: "\(sample.value)", display: valueString)]
            ),
            device: HealthingDevice.fromHealthKitDevice(sample.device),
            category: category
        )
    }
}

// MARK: - FHIR Date/Time Handling

extension Date {
    /// Convert to FHIR DateTime string with proper timezone handling
    /// Implements REQ-009: Proper FHIR Date/Instant parsing
    func toFHIRDateTime() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Convert to FHIR Date string (date only, no time)
    func toFHIRDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }

    /// Create Date from FHIR DateTime string with timezone support
    static func fromFHIRDateTime(_ dateTimeString: String) -> Date? {
        // Try ISO8601 format first (preferred)
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateTimeString) {
            return date
        }

        // Try without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateTimeString) {
            return date
        }

        // Try basic date format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.date(from: dateTimeString)
    }

    /// Create Date from FHIR Date string (date only)
    static func fromFHIRDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }
}

// MARK: - HealthKit to LOINC Mapping (Reused from HealthKitSyncService)

struct HealthKitMapping {
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
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue:
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
        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return HKUnit.percent()
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return HKUnit.count()
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return HKUnit.secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue:
            return HKUnit.kilocalorie()
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return HKUnit.meter()
        case HKQuantityTypeIdentifier.dietaryWater.rawValue:
            return HKUnit.liter()
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
