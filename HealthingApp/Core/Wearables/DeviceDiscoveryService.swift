import Foundation
import SwiftUI
import Combine
import CoreBluetooth
import WatchConnectivity

/// Automatic device discovery and pairing service
/// Implements REQ-064: Automatic device discovery and pairing
/// Discovers and manages connections to wearable devices
@MainActor
class DeviceDiscoveryService: NSObject, ObservableObject {
    static let shared = DeviceDiscoveryService()

    @Published var discoveredDevices: [DiscoveredWearableDevice] = []
    @Published var isDiscovering = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var lastDiscoveryDate: Date?
    @Published var discoveryProgress: Double = 0.0

    // Bluetooth Central Manager for BLE device discovery
    private var centralManager: CBCentralManager?

    // Device discovery timeouts and intervals
    private let discoveryTimeout: TimeInterval = 30.0 // 30 seconds
    private let deviceCacheExpiration: TimeInterval = 300.0 // 5 minutes

    // Discovery filters and device signatures
    private let supportedDeviceSignatures: [DeviceSignature] = [
        // Garmin devices
        DeviceSignature(
            name: "Garmin",
            serviceUUIDs: [CBUUID(string: "6A4E2401-667B-11E3-949A-0800200C9A66")],
            manufacturerData: nil,
            deviceType: .garmin
        ),
        // Fitbit devices
        DeviceSignature(
            name: "Fitbit",
            serviceUUIDs: [CBUUID(string: "ADABFFF0-6E7D-4601-BDA2-BFFAA68956BA")],
            manufacturerData: nil,
            deviceType: .fitbit
        ),
        // Generic fitness devices
        DeviceSignature(
            name: "Heart Rate",
            serviceUUIDs: [CBUUID(string: "180D")], // Heart Rate Service
            manufacturerData: nil,
            deviceType: .unknown
        ),
        DeviceSignature(
            name: "Health Thermometer",
            serviceUUIDs: [CBUUID(string: "1809")], // Health Thermometer Service
            manufacturerData: nil,
            deviceType: .unknown
        )
    ]

    private var discoveryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        setupBluetoothManager()
        loadCachedDevices()
    }

    // MARK: - Bluetooth Setup

    private func setupBluetoothManager() {
        print("🔍 DeviceDiscoveryService: Setting up Bluetooth manager...")

        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Device Discovery

    /// Start comprehensive device discovery
    func discoverDevices() async {
        print("🔍 DeviceDiscoveryService: Starting device discovery...")

        isDiscovering = true
        discoveryProgress = 0.0

        // Step 1: Discover Apple Watch (via WatchConnectivity)
        await discoverAppleWatch()
        discoveryProgress = 0.3

        // Step 2: Discover Bluetooth LE devices
        await discoverBluetoothDevices()
        discoveryProgress = 0.7

        // Step 3: Check for cached/paired devices
        await checkCachedDevices()
        discoveryProgress = 1.0

        lastDiscoveryDate = Date()
        isDiscovering = false

        print("✅ DeviceDiscoveryService: Discovery completed - found \(discoveredDevices.count) devices")
    }

    /// Discover Apple Watch through WatchConnectivity
    private func discoverAppleWatch() async {
        print("⌚ DeviceDiscoveryService: Checking Apple Watch availability...")

        guard WCSession.isSupported() else {
            print("⌚ Watch Connectivity not supported")
            return
        }

        let session = WCSession.default

        // Apple Watch is considered "discoverable" if WatchConnectivity is supported
        // Even if not currently paired, user can pair through Watch app
        let appleWatch = DiscoveredWearableDevice(
            id: "apple-watch-discovery",
            name: "Apple Watch",
            type: .appleWatch,
            manufacturer: "Apple",
            modelName: "Apple Watch",
            signalStrength: session.activationState == .activated ? -30 : -100, // dBm equivalent
            lastSeen: Date(),
            isConnectable: WCSession.isSupported(),
            requiresApp: true, // Requires Watch app for pairing
            capabilities: AppleWatchCapabilities.allCapabilities(),
            connectionMethod: .watchConnectivity,
            pairingInstructions: "To connect your Apple Watch, please use the Apple Watch app on your iPhone."
        )

        if !discoveredDevices.contains(where: { $0.type == .appleWatch }) {
            discoveredDevices.append(appleWatch)
            print("✅ Apple Watch added to discovery list")
        }
    }

    /// Discover Bluetooth Low Energy devices
    private func discoverBluetoothDevices() async {
        guard centralManager?.state == .poweredOn else {
            print("❌ Bluetooth is not available for device discovery")
            return
        }

        print("📱 DeviceDiscoveryService: Starting Bluetooth LE scan...")

        // Clear previous BLE discoveries (keep Apple Watch)
        discoveredDevices.removeAll { $0.connectionMethod == .bluetooth }

        // Start scanning for devices with health-related services
        let serviceUUIDs = supportedDeviceSignatures.flatMap { $0.serviceUUIDs }
        centralManager?.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Wait for discovery timeout
        await withCheckedContinuation { continuation in
            discoveryTimer = Timer.scheduledTimer(withTimeInterval: discoveryTimeout, repeats: false) { _ in
                self.centralManager?.stopScan()
                print("🔍 DeviceDiscoveryService: Bluetooth scan completed")
                continuation.resume()
            }
        }
    }

    /// Check for previously cached devices
    private func checkCachedDevices() async {
        print("💾 DeviceDiscoveryService: Checking cached devices...")

        // Load cached device information from UserDefaults
        if let cachedData = UserDefaults.standard.data(forKey: "cachedDiscoveredDevices"),
           let cachedDevices = try? JSONDecoder().decode([DiscoveredWearableDevice].self, from: cachedData) {

            for cachedDevice in cachedDevices {
                // Only add if not expired and not already discovered
                let cacheAge = Date().timeIntervalSince(cachedDevice.lastSeen)
                if cacheAge < deviceCacheExpiration &&
                   !discoveredDevices.contains(where: { $0.id == cachedDevice.id }) {

                    // Update last seen to current time for display purposes
                    var updatedDevice = cachedDevice
                    updatedDevice.lastSeen = Date()

                    discoveredDevices.append(updatedDevice)
                    print("💾 Added cached device: \(cachedDevice.name)")
                }
            }
        }

        // Add mock devices for development and demo purposes
        addMockDevicesForDevelopment()
    }

    /// Add mock devices for development and demonstration
    private func addMockDevicesForDevelopment() {
        #if DEBUG
        let mockDevices = [
            DiscoveredWearableDevice(
                id: "mock-garmin-forerunner",
                name: "Garmin Forerunner 965",
                type: .garmin,
                manufacturer: "Garmin",
                modelName: "Forerunner 965",
                signalStrength: -45,
                lastSeen: Date(),
                isConnectable: true,
                requiresApp: true,
                capabilities: GarminCapabilities.getCapabilities(for: "Forerunner 965"),
                connectionMethod: .garminConnect,
                pairingInstructions: "Install Garmin Connect app and follow pairing instructions."
            ),
            DiscoveredWearableDevice(
                id: "mock-garmin-venu",
                name: "Garmin Venu 3",
                type: .garmin,
                manufacturer: "Garmin",
                modelName: "Venu 3",
                signalStrength: -50,
                lastSeen: Date(),
                isConnectable: true,
                requiresApp: true,
                capabilities: GarminCapabilities.getCapabilities(for: "Venu 3"),
                connectionMethod: .garminConnect,
                pairingInstructions: "Install Garmin Connect app and follow pairing instructions."
            ),
            DiscoveredWearableDevice(
                id: "mock-fitbit-sense",
                name: "Fitbit Sense 2",
                type: .fitbit,
                manufacturer: "Fitbit",
                modelName: "Sense 2",
                signalStrength: -55,
                lastSeen: Date(),
                isConnectable: true,
                requiresApp: true,
                capabilities: FitbitCapabilities.getCapabilities(for: "Sense 2"),
                connectionMethod: .fitbitApp,
                pairingInstructions: "Install Fitbit app and follow device setup instructions."
            )
        ]

        for mockDevice in mockDevices {
            if !discoveredDevices.contains(where: { $0.id == mockDevice.id }) {
                discoveredDevices.append(mockDevice)
            }
        }

        print("🧪 Added \(mockDevices.count) mock devices for development")
        #endif
    }

    // MARK: - Device Filtering and Classification

    /// Classify discovered Bluetooth device
    private func classifyBluetoothDevice(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> DiscoveredWearableDevice? {

        let deviceName = peripheral.name ?? "Unknown Device"
        let rssi = (advertisementData[CBAdvertisementDataRSSIKey] as? NSNumber)?.intValue ?? -100

        // Check against known device signatures
        for signature in supportedDeviceSignatures {
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                // Check if any advertised services match our signature
                if !Set(serviceUUIDs).isDisjoint(with: Set(signature.serviceUUIDs)) ||
                   deviceName.localizedCaseInsensitiveContains(signature.name) {

                    let capabilities = getCapabilities(for: signature.deviceType, modelName: deviceName)

                    return DiscoveredWearableDevice(
                        id: peripheral.identifier.uuidString,
                        name: deviceName,
                        type: signature.deviceType,
                        manufacturer: getManufacturer(for: signature.deviceType),
                        modelName: deviceName,
                        signalStrength: rssi,
                        lastSeen: Date(),
                        isConnectable: true,
                        requiresApp: signature.deviceType != .unknown,
                        capabilities: capabilities,
                        connectionMethod: getConnectionMethod(for: signature.deviceType),
                        pairingInstructions: getPairingInstructions(for: signature.deviceType)
                    )
                }
            }
        }

        // Generic device if no specific signature matched
        return DiscoveredWearableDevice(
            id: peripheral.identifier.uuidString,
            name: deviceName,
            type: .unknown,
            manufacturer: "Unknown",
            modelName: deviceName,
            signalStrength: rssi,
            lastSeen: Date(),
            isConnectable: false, // Don't allow connection to unknown devices
            requiresApp: false,
            capabilities: WearableDeviceCapabilities(supportedDataTypes: [], batteryMonitoring: false, realTimeSync: false),
            connectionMethod: .bluetooth,
            pairingInstructions: "Device not supported for direct connection."
        )
    }

    /// Get capabilities for device type and model
    private func getCapabilities(for type: WearableDeviceType, modelName: String) -> WearableDeviceCapabilities {
        switch type {
        case .appleWatch:
            return AppleWatchCapabilities.allCapabilities()
        case .garmin:
            return GarminCapabilities.getCapabilities(for: modelName)
        case .fitbit:
            return FitbitCapabilities.getCapabilities(for: modelName)
        case .unknown:
            return WearableDeviceCapabilities(
                supportedDataTypes: ["8867-4"], // Basic heart rate
                batteryMonitoring: false,
                realTimeSync: false
            )
        }
    }

    /// Get manufacturer for device type
    private func getManufacturer(for type: WearableDeviceType) -> String {
        switch type {
        case .appleWatch: return "Apple"
        case .garmin: return "Garmin"
        case .fitbit: return "Fitbit"
        case .unknown: return "Unknown"
        }
    }

    /// Get connection method for device type
    private func getConnectionMethod(for type: WearableDeviceType) -> ConnectionMethod {
        switch type {
        case .appleWatch: return .watchConnectivity
        case .garmin: return .garminConnect
        case .fitbit: return .fitbitApp
        case .unknown: return .bluetooth
        }
    }

    /// Get pairing instructions for device type
    private func getPairingInstructions(for type: WearableDeviceType) -> String {
        switch type {
        case .appleWatch:
            return "Use the Apple Watch app on your iPhone to pair your Apple Watch."
        case .garmin:
            return "Download the Garmin Connect app and follow the device pairing instructions."
        case .fitbit:
            return "Download the Fitbit app and set up your device following the in-app instructions."
        case .unknown:
            return "Refer to your device manual for pairing instructions."
        }
    }

    // MARK: - Device Cache Management

    /// Cache discovered devices
    private func cacheDiscoveredDevices() {
        do {
            let encodedData = try JSONEncoder().encode(discoveredDevices)
            UserDefaults.standard.set(encodedData, forKey: "cachedDiscoveredDevices")
            print("💾 DeviceDiscoveryService: Cached \(discoveredDevices.count) discovered devices")
        } catch {
            print("❌ Failed to cache discovered devices: \(error)")
        }
    }

    /// Load cached devices
    private func loadCachedDevices() {
        // This will be called during checkCachedDevices
    }

    /// Clear device cache
    func clearDeviceCache() {
        UserDefaults.standard.removeObject(forKey: "cachedDiscoveredDevices")
        print("🗑️ DeviceDiscoveryService: Device cache cleared")
    }

    // MARK: - Discovery Control

    /// Stop current discovery
    func stopDiscovery() {
        centralManager?.stopScan()
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        isDiscovering = false

        print("🛑 DeviceDiscoveryService: Discovery stopped")
    }

    /// Get discovery statistics
    func getDiscoveryStats() -> DiscoveryStats {
        let deviceTypeCounts = Dictionary(grouping: discoveredDevices, by: { $0.type })
            .mapValues { $0.count }

        return DiscoveryStats(
            totalDevicesFound: discoveredDevices.count,
            deviceTypeBreakdown: deviceTypeCounts,
            lastDiscoveryDate: lastDiscoveryDate,
            bluetoothState: bluetoothState
        )
    }

    /// Check if device is already discovered
    func isDeviceDiscovered(_ deviceId: String) -> Bool {
        return discoveredDevices.contains { $0.id == deviceId }
    }

    /// Remove device from discovered list
    func removeDiscoveredDevice(_ deviceId: String) {
        discoveredDevices.removeAll { $0.id == deviceId }
        cacheDiscoveredDevices()
        print("🗑️ Removed device from discovery: \(deviceId)")
    }
}

// MARK: - CBCentralManagerDelegate
extension DeviceDiscoveryService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
        }

        switch central.state {
        case .poweredOn:
            print("📱 DeviceDiscoveryService: Bluetooth powered on - ready for discovery")
        case .poweredOff:
            print("📱 DeviceDiscoveryService: Bluetooth powered off")
        case .resetting:
            print("📱 DeviceDiscoveryService: Bluetooth resetting")
        case .unauthorized:
            print("📱 DeviceDiscoveryService: Bluetooth unauthorized")
        case .unsupported:
            print("📱 DeviceDiscoveryService: Bluetooth unsupported")
        case .unknown:
            print("📱 DeviceDiscoveryService: Bluetooth state unknown")
        @unknown default:
            print("📱 DeviceDiscoveryService: Bluetooth state unknown default")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

        // Skip devices with very weak signal
        guard RSSI.intValue > -90 else { return }

        // Classify the discovered device
        if let discoveredDevice = classifyBluetoothDevice(peripheral, advertisementData: advertisementData) {

            // Check if we've already discovered this device
            if !discoveredDevices.contains(where: { $0.id == discoveredDevice.id }) {
                DispatchQueue.main.async {
                    self.discoveredDevices.append(discoveredDevice)
                    self.cacheDiscoveredDevices()
                }

                print("🔍 Discovered new device: \(discoveredDevice.name) (\(discoveredDevice.type.displayName))")
            } else {
                // Update signal strength for existing device
                if let existingIndex = discoveredDevices.firstIndex(where: { $0.id == discoveredDevice.id }) {
                    DispatchQueue.main.async {
                        self.discoveredDevices[existingIndex].signalStrength = discoveredDevice.signalStrength
                        self.discoveredDevices[existingIndex].lastSeen = Date()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct DiscoveredWearableDevice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: WearableDeviceType
    let manufacturer: String
    let modelName: String
    var signalStrength: Int // dBm
    var lastSeen: Date
    let isConnectable: Bool
    let requiresApp: Bool
    let capabilities: WearableDeviceCapabilities
    let connectionMethod: ConnectionMethod
    let pairingInstructions: String

    var signalStrengthDescription: String {
        switch signalStrength {
        case -50...0: return "Excellent"
        case -60..<(-50): return "Good"
        case -70..<(-60): return "Fair"
        case -80..<(-70): return "Poor"
        default: return "Very Poor"
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredWearableDevice, rhs: DiscoveredWearableDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

enum ConnectionMethod: String, Codable, CaseIterable {
    case bluetooth = "bluetooth"
    case watchConnectivity = "watch_connectivity"
    case garminConnect = "garmin_connect"
    case fitbitApp = "fitbit_app"
    case webAPI = "web_api"

    var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .watchConnectivity: return "Watch Connectivity"
        case .garminConnect: return "Garmin Connect"
        case .fitbitApp: return "Fitbit App"
        case .webAPI: return "Web API"
        }
    }
}

struct DeviceSignature {
    let name: String
    let serviceUUIDs: [CBUUID]
    let manufacturerData: Data?
    let deviceType: WearableDeviceType
}

struct DiscoveryStats {
    let totalDevicesFound: Int
    let deviceTypeBreakdown: [WearableDeviceType: Int]
    let lastDiscoveryDate: Date?
    let bluetoothState: CBManagerState

    var isBluetoothAvailable: Bool {
        return bluetoothState == .poweredOn
    }
}