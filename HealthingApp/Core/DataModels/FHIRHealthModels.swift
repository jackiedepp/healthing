//
//  FHIRHealthModels.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import Foundation
import ModelsR4
import CoreData
import HealthKit

// MARK: - Core FHIR-Compliant Data Models

/// Patient model representing the user's basic profile and demographics
struct FHIRHealthingPatient {
    let id: String
    let identifier: [Identifier]
    let name: [HumanName]
    let gender: AdministrativeGender?
    let birthDate: FHIRDate?
    let address: [Address]
    let telecom: [ContactPoint]
    let active: Bool

    /// Convert to FHIR Patient resource
    func toFHIRPatient() -> Patient {
        let patient = Patient()
        patient.id = FHIRString(self.id)
        patient.identifier = self.identifier
        patient.name = self.name
        patient.gender = self.gender
        patient.birthDate = self.birthDate
        patient.address = self.address
        patient.telecom = self.telecom
        patient.active = FHIRBool(self.active)
        return patient
    }
}

/// Health observation model for measurements from HealthKit and wearable devices
struct FHIRHealthingObservation {
    let id: String
    let status: ObservationStatus
    let code: CodeableConcept
    let subject: Reference
    let effectiveDateTime: DateTime?
    let valueQuantity: Quantity?
    let valueCodeableConcept: CodeableConcept?
    let device: Reference?
    let component: [ObservationComponent]?
    let category: [CodeableConcept]

    /// Convert to FHIR Observation resource
    func toFHIRObservation() -> Observation {
        let observation = Observation(code: self.code, status: self.status, subject: self.subject)
        observation.id = FHIRString(self.id)
        observation.effectiveDateTime = self.effectiveDateTime
        observation.valueQuantity = self.valueQuantity
        observation.valueCodeableConcept = self.valueCodeableConcept
        observation.device = self.device
        observation.component = self.component
        observation.category = self.category
        return observation
    }

    /// Create from HealthKit sample
    static func fromHealthKitSample(_ sample: HKSample, patientReference: Reference) -> FHIRHealthingObservation? {
        guard let quantitySample = sample as? HKQuantitySample else { return nil }

        let code = CodeableConcept()
        let coding = Coding()

        // Map HealthKit identifiers to LOINC codes
        switch quantitySample.quantityType.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            coding.system = FHIRString("http://loinc.org")
            coding.code = FHIRString("8867-4")
            coding.display = FHIRString("Heart rate")
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            coding.system = FHIRString("http://loinc.org")
            coding.code = FHIRString("55423-8")
            coding.display = FHIRString("Number of steps")
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            coding.system = FHIRString("http://loinc.org")
            coding.code = FHIRString("41981-2")
            coding.display = FHIRString("Active energy burned")
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            coding.system = FHIRString("http://loinc.org")
            coding.code = FHIRString("29463-7")
            coding.display = FHIRString("Body weight")
        default:
            return nil
        }

        code.coding = [coding]

        let valueQuantity = Quantity()
        valueQuantity.value = FHIRDecimal(quantitySample.quantity.doubleValue(for: .count()))
        valueQuantity.unit = FHIRString(quantitySample.quantityType.identifier)

        let category = CodeableConcept()
        let categoryCoding = Coding()
        categoryCoding.system = FHIRString("http://terminology.hl7.org/CodeSystem/observation-category")
        categoryCoding.code = FHIRString("vital-signs")
        categoryCoding.display = FHIRString("Vital Signs")
        category.coding = [categoryCoding]

        return FHIRHealthingObservation(
            id: sample.uuid.uuidString,
            status: .final,
            code: code,
            subject: patientReference,
            effectiveDateTime: DateTime(sample.startDate),
            valueQuantity: valueQuantity,
            valueCodeableConcept: nil,
            device: nil,
            component: nil,
            category: [category]
        )
    }
}

/// Medical document reference model
struct FHIRHealthingDocumentReference {
    let id: String
    let masterIdentifier: Identifier?
    let status: DocumentReferenceStatus
    let type: CodeableConcept
    let category: [CodeableConcept]
    let subject: Reference
    let date: Instant?
    let author: [Reference]
    let description: String?
    let content: [DocumentReferenceContent]

    /// Convert to FHIR DocumentReference resource
    func toFHIRDocumentReference() -> DocumentReference {
        let docRef = DocumentReference(content: self.content, status: self.status)
        docRef.id = FHIRString(self.id)
        docRef.masterIdentifier = self.masterIdentifier
        docRef.type = self.type
        docRef.category = self.category
        docRef.subject = self.subject
        docRef.date = self.date
        docRef.author = self.author
        docRef.description_fhir = FHIRString(self.description ?? "")
        return docRef
    }
}

/// Connected device model for Apple Watch and Garmin devices
struct FHIRHealthingDevice {
    let id: String
    let identifier: [Identifier]
    let displayName: String?
    let type: CodeableConcept
    let manufacturer: String?
    let modelNumber: String?
    let version: [DeviceVersion]?
    let status: DeviceStatus?
    let patient: Reference

    /// Convert to FHIR Device resource
    func toFHIRDevice() -> Device {
        let device = Device()
        device.id = FHIRString(self.id)
        device.identifier = self.identifier
        device.displayName = FHIRString(self.displayName ?? "")
        device.type = self.type
        device.manufacturer = FHIRString(self.manufacturer ?? "")
        device.modelNumber = FHIRString(self.modelNumber ?? "")
        device.version = self.version
        device.status = self.status
        device.patient = self.patient
        return device
    }

    /// Create Apple Watch device reference
    static func appleWatchDevice(for patientReference: Reference) -> FHIRHealthingDevice {
        let type = CodeableConcept()
        let coding = Coding()
        coding.system = FHIRString("http://snomed.info/sct")
        coding.code = FHIRString("706689003")
        coding.display = FHIRString("Wearable fitness tracker")
        type.coding = [coding]

        let identifier = Identifier()
        identifier.system = FHIRString("http://healthing.app/device-identifiers")
        identifier.value = FHIRString("apple-watch-\(UUID().uuidString)")

        return FHIRHealthingDevice(
            id: UUID().uuidString,
            identifier: [identifier],
            displayName: "Apple Watch",
            type: type,
            manufacturer: "Apple Inc.",
            modelNumber: nil,
            version: nil,
            status: .active,
            patient: patientReference
        )
    }

    /// Create Garmin device reference
    static func garminDevice(modelNumber: String, for patientReference: Reference) -> FHIRHealthingDevice {
        let type = CodeableConcept()
        let coding = Coding()
        coding.system = FHIRString("http://snomed.info/sct")
        coding.code = FHIRString("706689003")
        coding.display = FHIRString("Wearable fitness tracker")
        type.coding = [coding]

        let identifier = Identifier()
        identifier.system = FHIRString("http://healthing.app/device-identifiers")
        identifier.value = FHIRString("garmin-\(modelNumber)-\(UUID().uuidString)")

        return FHIRHealthingDevice(
            id: UUID().uuidString,
            identifier: [identifier],
            displayName: "Garmin \(modelNumber)",
            type: type,
            manufacturer: "Garmin Ltd.",
            modelNumber: modelNumber,
            version: nil,
            status: .active,
            patient: patientReference
        )
    }
}

/// Care plan model for personal health goals
struct FHIRHealthingCarePlan {
    let id: String
    let status: CarePlanStatus
    let intent: CarePlanIntent
    let title: String
    let description: String?
    let subject: Reference
    let period: Period?
    let author: [Reference]
    let goal: [Reference]
    let activity: [CarePlanActivity]

    /// Convert to FHIR CarePlan resource
    func toFHIRCarePlan() -> CarePlan {
        let carePlan = CarePlan(intent: self.intent, status: self.status, subject: self.subject)
        carePlan.id = FHIRString(self.id)
        carePlan.title = FHIRString(self.title)
        carePlan.description_fhir = FHIRString(self.description ?? "")
        carePlan.period = self.period
        carePlan.author = self.author
        carePlan.goal = self.goal
        carePlan.activity = self.activity
        return carePlan
    }
}

/// Diagnostic report model for AI-generated health insights
struct FHIRHealthingDiagnosticReport {
    let id: String
    let status: DiagnosticReportStatus
    let category: [CodeableConcept]
    let code: CodeableConcept
    let subject: Reference
    let effectiveDateTime: DateTime?
    let issued: Instant?
    let performer: [Reference]
    let resultsInterpreter: [Reference]
    let result: [Reference]
    let conclusion: String?
    let conclusionCode: [CodeableConcept]

    /// Convert to FHIR DiagnosticReport resource
    func toFHIRDiagnosticReport() -> DiagnosticReport {
        let report = DiagnosticReport(code: self.code, status: self.status, subject: self.subject)
        report.id = FHIRString(self.id)
        report.category = self.category
        report.effectiveDateTime = self.effectiveDateTime
        report.issued = self.issued
        report.performer = self.performer
        report.resultsInterpreter = self.resultsInterpreter
        report.result = self.result
        report.conclusion = FHIRString(self.conclusion ?? "")
        report.conclusionCode = self.conclusionCode
        return report
    }
}

// MARK: - Extensions for Data Conversion with Proper Timezone Handling (REQ-009)

extension DateTime {
    /// Create FHIR DateTime with proper timezone handling and precision
    init(_ date: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        self.init(formatter.string(from: date))
    }

    /// Create DateTime from string with timezone parsing
    init?(fromString dateString: String) {
        let formatters = Self.createDateTimeFormatters()

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                self.init(date)
                return
            }
        }
        return nil
    }

    /// Convert to Date with proper timezone handling
    var dateValue: Date? {
        let formatters = Self.createDateTimeFormatters()

        guard let string = self.string else { return nil }

        for formatter in formatters {
            if let date = formatter.date(from: string.value) {
                return date
            }
        }
        return nil
    }

    private static func createDateTimeFormatters() -> [DateFormatter] {
        var formatters: [DateFormatter] = []

        // ISO 8601 formatter with fractional seconds
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoDateFormatter = DateFormatter()
        isoDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        isoDateFormatter.timeZone = TimeZone.current

        // Standard FHIR DateTime formats
        let fhirFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",  // Full precision with timezone
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",      // Without fractional seconds
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",      // Z timezone
            "yyyy-MM-dd'T'HH:mm:ssZ",          // Z timezone without fractions
            "yyyy-MM-dd'T'HH:mm:ss",           // Local time
            "yyyy-MM-dd'T'HH:mm",              // Hour precision
            "yyyy-MM-dd"                        // Date only
        ]

        for format in fhirFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone.current
            formatters.append(formatter)
        }

        return formatters
    }
}

extension Instant {
    /// Create FHIR Instant with precise timestamp and timezone
    init(_ date: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Instant must always be in UTC
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.init(formatter.string(from: date))
    }

    /// Create Instant from string with timezone conversion to UTC
    init?(fromString dateString: String) {
        let formatters = Self.createInstantFormatters()

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                self.init(date)
                return
            }
        }
        return nil
    }

    /// Convert to Date (always in UTC for Instant)
    var dateValue: Date? {
        let formatters = Self.createInstantFormatters()

        guard let string = self.string else { return nil }

        for formatter in formatters {
            if let date = formatter.date(from: string.value) {
                return date
            }
        }
        return nil
    }

    private static func createInstantFormatters() -> [DateFormatter] {
        var formatters: [DateFormatter] = []

        // FHIR Instant must be precise to at least the second
        let fhirInstantFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",  // Full precision with any timezone
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",      // Second precision with timezone
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",      // UTC with fractional seconds
            "yyyy-MM-dd'T'HH:mm:ssZ",          // UTC second precision
            "yyyy-MM-dd'T'HH:mm:ss'Z'",        // UTC with literal Z
        ]

        for format in fhirInstantFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            // For parsing, try both UTC and current timezone
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatters.append(formatter)

            // Also add a formatter with current timezone for conversion
            let localFormatter = DateFormatter()
            localFormatter.dateFormat = format
            localFormatter.timeZone = TimeZone.current
            formatters.append(localFormatter)
        }

        return formatters
    }
}

extension FHIRDate {
    /// Create FHIR Date with proper date handling (no time component)
    init(_ date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        self.init(formatter.string(from: date))
    }

    /// Create FHIRDate from string with multiple format support
    init?(fromString dateString: String) {
        let formatters = Self.createDateFormatters()

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                self.init(date)
                return
            }
        }
        return nil
    }

    /// Convert to Date (start of day in current timezone)
    var dateValue: Date? {
        let formatters = Self.createDateFormatters()

        guard let string = self.string else { return nil }

        for formatter in formatters {
            if let date = formatter.date(from: string.value) {
                return date
            }
        }
        return nil
    }

    private static func createDateFormatters() -> [DateFormatter] {
        var formatters: [DateFormatter] = []

        // FHIR Date format variations
        let fhirDateFormats = [
            "yyyy-MM-dd",    // Full date
            "yyyy-MM",       // Year and month
            "yyyy"           // Year only
        ]

        for format in fhirDateFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone.current
            formatters.append(formatter)
        }

        return formatters
    }
}

// MARK: - FHIR DateTime Utility Functions

/// Utility class for FHIR date/time operations with timezone handling
final class FHIRDateTimeUtils {

    /// Convert HealthKit date to FHIR DateTime with timezone preservation
    static func healthKitDateToFHIRDateTime(_ date: Date) -> DateTime {
        return DateTime(date)
    }

    /// Convert HealthKit date to FHIR Instant (UTC)
    static func healthKitDateToFHIRInstant(_ date: Date) -> Instant {
        return Instant(date)
    }

    /// Parse any FHIR date/time string to Swift Date
    static func parseFHIRDateTimeString(_ dateString: String) -> Date? {
        // Try DateTime first
        if let dateTime = DateTime(fromString: dateString) {
            return dateTime.dateValue
        }

        // Try Instant
        if let instant = Instant(fromString: dateString) {
            return instant.dateValue
        }

        // Try FHIRDate
        if let fhirDate = FHIRDate(fromString: dateString) {
            return fhirDate.dateValue
        }

        return nil
    }

    /// Format Date for FHIR with specified precision
    static func formatDateForFHIR(_ date: Date, precision: FHIRDatePrecision) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current

        switch precision {
        case .year:
            formatter.dateFormat = "yyyy"
        case .month:
            formatter.dateFormat = "yyyy-MM"
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
        case .hour:
            formatter.dateFormat = "yyyy-MM-dd'T'HH"
        case .minute:
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        case .second:
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        case .millisecond:
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        }

        return formatter.string(from: date)
    }

    /// Validate FHIR date/time string format
    static func validateFHIRDateTimeString(_ dateString: String) -> Bool {
        return parseFHIRDateTimeString(dateString) != nil
    }

    /// Get current timezone offset for FHIR formatting
    static func getCurrentTimezoneOffset() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "XXXXX"  // ISO 8601 timezone format
        return formatter.string(from: Date())
    }
}

enum FHIRDatePrecision {
    case year
    case month
    case day
    case hour
    case minute
    case second
    case millisecond
}
