import Foundation

/// Device capabilities framework for different wearable devices
/// Defines what each device type can measure and support

// MARK: - Base Capability Structure

struct WearableDeviceCapabilities: Codable, Hashable {
    let supportedDataTypes: [String] // LOINC codes
    let batteryMonitoring: Bool
    let realTimeSync: Bool
    let gpsCapable: Bool
    let waterResistant: Bool
    let maxBatteryLifeDays: Int
    let supportedActivities: [ActivityType]
    let healthMetrics: [HealthMetric]
    let smartFeatures: [SmartFeature]

    init(
        supportedDataTypes: [String],
        batteryMonitoring: Bool = true,
        realTimeSync: Bool = true,
        gpsCapable: Bool = false,
        waterResistant: Bool = false,
        maxBatteryLifeDays: Int = 1,
        supportedActivities: [ActivityType] = [],
        healthMetrics: [HealthMetric] = [],
        smartFeatures: [SmartFeature] = []
    ) {
        self.supportedDataTypes = supportedDataTypes
        self.batteryMonitoring = batteryMonitoring
        self.realTimeSync = realTimeSync
        self.gpsCapable = gpsCapable
        self.waterResistant = waterResistant
        self.maxBatteryLifeDays = maxBatteryLifeDays
        self.supportedActivities = supportedActivities
        self.healthMetrics = healthMetrics
        self.smartFeatures = smartFeatures
    }
}

// MARK: - Activity Types

enum ActivityType: String, CaseIterable, Codable {
    case running = "running"
    case walking = "walking"
    case cycling = "cycling"
    case swimming = "swimming"
    case hiking = "hiking"
    case gym = "gym"
    case yoga = "yoga"
    case tennis = "tennis"
    case golf = "golf"
    case skiing = "skiing"
    case rowing = "rowing"
    case elliptical = "elliptical"
    case climbing = "climbing"
    case crossfit = "crossfit"
    case dance = "dance"
    case basketball = "basketball"
    case soccer = "soccer"
    case baseball = "baseball"

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .gym: return "Gym"
        case .yoga: return "Yoga"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .skiing: return "Skiing"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .climbing: return "Climbing"
        case .crossfit: return "CrossFit"
        case .dance: return "Dance"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .baseball: return "Baseball"
        }
    }
}

// MARK: - Health Metrics

enum HealthMetric: String, CaseIterable, Codable {
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case heartRateVariability = "hrv"
    case bloodPressure = "blood_pressure"
    case oxygenSaturation = "spo2"
    case respiratoryRate = "respiratory_rate"
    case bodyTemperature = "body_temperature"
    case skinTemperature = "skin_temperature"
    case steps = "steps"
    case calories = "calories"
    case distance = "distance"
    case floors = "floors"
    case sleepAnalysis = "sleep"
    case stressLevel = "stress"
    case vo2Max = "vo2_max"
    case bodyBattery = "body_battery" // Garmin specific
    case readiness = "readiness"
    case hydration = "hydration"
    case menstrualCycle = "menstrual_cycle"
    case bloodGlucose = "blood_glucose"
    case bodyWeight = "body_weight"
    case bodyFat = "body_fat"
    case muscleMass = "muscle_mass"
    case boneMass = "bone_mass"

    var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariability: return "HRV"
        case .bloodPressure: return "Blood Pressure"
        case .oxygenSaturation: return "SpO2"
        case .respiratoryRate: return "Respiratory Rate"
        case .bodyTemperature: return "Body Temperature"
        case .skinTemperature: return "Skin Temperature"
        case .steps: return "Steps"
        case .calories: return "Calories"
        case .distance: return "Distance"
        case .floors: return "Floors Climbed"
        case .sleepAnalysis: return "Sleep Analysis"
        case .stressLevel: return "Stress Level"
        case .vo2Max: return "VO2 Max"
        case .bodyBattery: return "Body Battery"
        case .readiness: return "Readiness Score"
        case .hydration: return "Hydration"
        case .menstrualCycle: return "Menstrual Cycle"
        case .bloodGlucose: return "Blood Glucose"
        case .bodyWeight: return "Body Weight"
        case .bodyFat: return "Body Fat %"
        case .muscleMass: return "Muscle Mass"
        case .boneMass: return "Bone Mass"
        }
    }

    var loincCode: String {
        switch self {
        case .heartRate: return "8867-4"
        case .restingHeartRate: return "40443-4"
        case .heartRateVariability: return "80404-7"
        case .bloodPressure: return "85354-9" // Blood pressure panel
        case .oxygenSaturation: return "2708-6"
        case .respiratoryRate: return "9279-1"
        case .bodyTemperature: return "8310-5"
        case .skinTemperature: return "8328-7"
        case .steps: return "55423-8"
        case .calories: return "41981-2"
        case .distance: return "41953-1"
        case .floors: return "LA11619-6"
        case .sleepAnalysis: return "93832-4"
        case .stressLevel: return "LA18938-6"
        case .vo2Max: return "33747-0"
        case .bodyBattery: return "LA18939-4"
        case .readiness: return "LA18940-2"
        case .hydration: return "33747-0"
        case .menstrualCycle: return "LA6115-9"
        case .bloodGlucose: return "33747-0"
        case .bodyWeight: return "29463-7"
        case .bodyFat: return "41982-0"
        case .muscleMass: return "73708-0"
        case .boneMass: return "73964-9"
        }
    }
}

// MARK: - Smart Features

enum SmartFeature: String, CaseIterable, Codable {
    case notifications = "notifications"
    case musicControl = "music_control"
    case payments = "payments"
    case voiceAssistant = "voice_assistant"
    case appStore = "app_store"
    case weatherUpdates = "weather"
    case calendar = "calendar"
    case messaging = "messaging"
    case phoneCall = "phone_call"
    case findMyPhone = "find_my_phone"
    case flashlight = "flashlight"
    case timer = "timer"
    case stopwatch = "stopwatch"
    case alarm = "alarm"
    case worldClock = "world_clock"

    var displayName: String {
        switch self {
        case .notifications: return "Smart Notifications"
        case .musicControl: return "Music Control"
        case .payments: return "Contactless Payments"
        case .voiceAssistant: return "Voice Assistant"
        case .appStore: return "App Store"
        case .weatherUpdates: return "Weather Updates"
        case .calendar: return "Calendar"
        case .messaging: return "Messaging"
        case .phoneCall: return "Phone Calls"
        case .findMyPhone: return "Find My Phone"
        case .flashlight: return "Flashlight"
        case .timer: return "Timer"
        case .stopwatch: return "Stopwatch"
        case .alarm: return "Alarm"
        case .worldClock: return "World Clock"
        }
    }
}

// MARK: - Apple Watch Capabilities

struct AppleWatchCapabilities {
    static func allCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4",   // Heart Rate
                "40443-4",  // Resting Heart Rate
                "80404-7",  // Heart Rate Variability
                "2708-6",   // Oxygen Saturation
                "55423-8",  // Steps
                "41981-2",  // Active Energy
                "41953-1",  // Distance
                "LA11619-6", // Floors
                "93832-4",  // Sleep Analysis
                "33747-0",  // VO2 Max
                "8310-5",   // Body Temperature (Series 8+)
                "29463-7"   // Body Weight (via connected scales)
            ],
            batteryMonitoring: true,
            realTimeSync: true,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 2,
            supportedActivities: [
                .running, .walking, .cycling, .swimming, .hiking,
                .gym, .yoga, .tennis, .golf, .rowing, .elliptical,
                .climbing, .dance, .basketball, .soccer
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .heartRateVariability,
                .oxygenSaturation, .steps, .calories, .distance, .floors,
                .sleepAnalysis, .vo2Max, .bodyTemperature
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .voiceAssistant,
                .appStore, .weatherUpdates, .calendar, .messaging,
                .phoneCall, .findMyPhone, .timer, .stopwatch, .alarm
            ]
        )
    }
}

// MARK: - Garmin Capabilities

struct GarminCapabilities {
    static func getCapabilities(for modelName: String) -> WearableDeviceCapabilities {
        switch modelName.lowercased() {
        case let model where model.contains("forerunner"):
            return forerunnerCapabilities()
        case let model where model.contains("fenix"):
            return fenixCapabilities()
        case let model where model.contains("venu"):
            return venuCapabilities()
        case let model where model.contains("vivoactive"):
            return vivoactiveCapabilities()
        case let model where model.contains("instinct"):
            return instinctCapabilities()
        default:
            return basicGarminCapabilities()
        }
    }

    private static func forerunnerCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "80404-7", "2708-6", "55423-8",
                "41981-2", "41953-1", "93832-4", "33747-0", "LA18938-6"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 15,
            supportedActivities: [
                .running, .cycling, .swimming, .hiking, .gym, .tennis, .golf
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .heartRateVariability,
                .oxygenSaturation, .steps, .calories, .distance,
                .sleepAnalysis, .vo2Max, .stressLevel, .bodyBattery
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .weatherUpdates,
                .timer, .stopwatch, .alarm
            ]
        )
    }

    private static func fenixCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "80404-7", "2708-6", "55423-8",
                "41981-2", "41953-1", "93832-4", "33747-0", "LA18938-6"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 21,
            supportedActivities: ActivityType.allCases, // Fenix supports all activities
            healthMetrics: [
                .heartRate, .restingHeartRate, .heartRateVariability,
                .oxygenSaturation, .steps, .calories, .distance,
                .sleepAnalysis, .vo2Max, .stressLevel, .bodyBattery
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .weatherUpdates,
                .timer, .stopwatch, .alarm, .worldClock
            ]
        )
    }

    private static func venuCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "80404-7", "2708-6", "55423-8",
                "41981-2", "41953-1", "93832-4", "33747-0", "LA18938-6"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 5,
            supportedActivities: [
                .running, .walking, .cycling, .swimming, .yoga, .gym,
                .dance, .tennis, .golf
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .heartRateVariability,
                .oxygenSaturation, .steps, .calories, .distance,
                .sleepAnalysis, .vo2Max, .stressLevel, .bodyBattery, .hydration
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .weatherUpdates,
                .calendar, .timer, .stopwatch, .alarm
            ]
        )
    }

    private static func vivoactiveCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "55423-8", "41981-2", "41953-1", "93832-4"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 8,
            supportedActivities: [
                .running, .walking, .cycling, .swimming, .yoga, .gym
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .steps, .calories,
                .distance, .sleepAnalysis, .stressLevel
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .weatherUpdates,
                .timer, .stopwatch
            ]
        )
    }

    private static func instinctCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "55423-8", "41981-2", "41953-1"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 54, // Solar versions
            supportedActivities: [
                .running, .hiking, .cycling, .swimming, .climbing, .skiing
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .steps, .calories, .distance
            ],
            smartFeatures: [
                .notifications, .timer, .stopwatch, .alarm, .worldClock
            ]
        )
    }

    private static func basicGarminCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "55423-8", "41981-2", "41953-1"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: false,
            maxBatteryLifeDays: 5,
            supportedActivities: [
                .running, .walking, .cycling
            ],
            healthMetrics: [
                .heartRate, .steps, .calories, .distance
            ],
            smartFeatures: [
                .notifications, .timer, .stopwatch
            ]
        )
    }
}

// MARK: - Fitbit Capabilities

struct FitbitCapabilities {
    static func getCapabilities(for modelName: String) -> WearableDeviceCapabilities {
        switch modelName.lowercased() {
        case let model where model.contains("sense"):
            return senseCapabilities()
        case let model where model.contains("versa"):
            return versaCapabilities()
        case let model where model.contains("charge"):
            return chargeCapabilities()
        case let model where model.contains("inspire"):
            return inspireCapabilities()
        default:
            return basicFitbitCapabilities()
        }
    }

    private static func senseCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "80404-7", "2708-6", "8328-7",
                "55423-8", "41981-2", "41953-1", "LA11619-6", "93832-4",
                "LA18938-6"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 6,
            supportedActivities: [
                .running, .walking, .cycling, .swimming, .yoga,
                .gym, .dance, .tennis, .hiking
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .heartRateVariability,
                .oxygenSaturation, .skinTemperature, .steps, .calories,
                .distance, .floors, .sleepAnalysis, .stressLevel
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .voiceAssistant,
                .weatherUpdates, .timer, .stopwatch, .alarm
            ]
        )
    }

    private static func versaCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "55423-8", "41981-2", "41953-1",
                "LA11619-6", "93832-4"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 6,
            supportedActivities: [
                .running, .walking, .cycling, .swimming, .yoga, .gym, .dance
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .steps, .calories,
                .distance, .floors, .sleepAnalysis
            ],
            smartFeatures: [
                .notifications, .musicControl, .payments, .weatherUpdates,
                .timer, .stopwatch, .alarm
            ]
        )
    }

    private static func chargeCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "40443-4", "55423-8", "41981-2", "41953-1",
                "LA11619-6", "93832-4"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: true,
            waterResistant: true,
            maxBatteryLifeDays: 7,
            supportedActivities: [
                .running, .walking, .cycling, .gym
            ],
            healthMetrics: [
                .heartRate, .restingHeartRate, .steps, .calories,
                .distance, .floors, .sleepAnalysis
            ],
            smartFeatures: [
                .notifications, .timer, .stopwatch, .alarm
            ]
        )
    }

    private static func inspireCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "55423-8", "41981-2", "41953-1", "93832-4"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: false,
            waterResistant: true,
            maxBatteryLifeDays: 10,
            supportedActivities: [
                .running, .walking, .cycling, .gym
            ],
            healthMetrics: [
                .heartRate, .steps, .calories, .distance, .sleepAnalysis
            ],
            smartFeatures: [
                .notifications, .timer, .stopwatch, .alarm
            ]
        )
    }

    private static func basicFitbitCapabilities() -> WearableDeviceCapabilities {
        return WearableDeviceCapabilities(
            supportedDataTypes: [
                "8867-4", "55423-8", "41981-2", "93832-4"
            ],
            batteryMonitoring: true,
            realTimeSync: false,
            gpsCapable: false,
            waterResistant: false,
            maxBatteryLifeDays: 5,
            supportedActivities: [
                .running, .walking, .cycling
            ],
            healthMetrics: [
                .heartRate, .steps, .calories, .sleepAnalysis
            ],
            smartFeatures: [
                .notifications, .timer, .alarm
            ]
        )
    }
}

// MARK: - Capability Helper Functions

extension WearableDeviceCapabilities {
    /// Check if device supports a specific health metric
    func supports(_ metric: HealthMetric) -> Bool {
        return supportedDataTypes.contains(metric.loincCode)
    }

    /// Check if device supports a specific activity
    func supports(_ activity: ActivityType) -> Bool {
        return supportedActivities.contains(activity)
    }

    /// Check if device has a specific smart feature
    func hasFeature(_ feature: SmartFeature) -> Bool {
        return smartFeatures.contains(feature)
    }

    /// Get capability summary for display
    var summary: String {
        let metrics = "\(healthMetrics.count) health metrics"
        let activities = "\(supportedActivities.count) activities"
        let features = "\(smartFeatures.count) smart features"
        let battery = "\(maxBatteryLifeDays) day\(maxBatteryLifeDays == 1 ? "" : "s") battery"

        return "\(metrics), \(activities), \(features), \(battery)"
    }

    /// Get detailed capability description
    var detailedDescription: [String] {
        var description: [String] = []

        if !healthMetrics.isEmpty {
            description.append("Health: \(healthMetrics.map { $0.displayName }.joined(separator: ", "))")
        }

        if gpsCapable {
            description.append("Built-in GPS")
        }

        if waterResistant {
            description.append("Water resistant")
        }

        if realTimeSync {
            description.append("Real-time sync")
        }

        description.append("Battery: \(maxBatteryLifeDays) day\(maxBatteryLifeDays == 1 ? "" : "s")")

        return description
    }
}