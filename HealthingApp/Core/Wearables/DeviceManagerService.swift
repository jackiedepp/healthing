import Foundation
import SwiftUI
import Combine

/// Central device management coordinator for all wearable devices
/// Implements REQ-064: Automatic device discovery and pairing
/// Implements REQ-065: Real-time data synchronization from connected devices
/// Implements REQ-066: Battery level monitoring for connected devices
/// Implements REQ-067: Device-specific data source identification
@MainActor
class DeviceManagerService: ObservableObject {
    static let shared = DeviceManagerService()

    @Published var connectedDevices: [ConnectedWearableDevice] = []
    @Published var availableDevices: [DiscoveredWearableDevice] = []
    @Published var deviceSyncStatus: [String: DeviceSyncStatus] = [:]
    @Published var lastDiscoveryDate: Date?
    @Published var isDiscovering = false

    // Device Services
    private let appleWatchService = AppleWatchService.shared
    private let garminService = GarminConnectService.shared
    private let discoveryService = DeviceDiscoveryService.shared
    private let dataProcessor = WearableDataProcessor.shared

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupDeviceMonitoring()
        startPeriodicDiscovery()
    }

    // MARK: - Device Monitoring Setup

    private func setupDeviceMonitoring() {
        print("📱 DeviceManagerService: Setting up device monitoring...")

        // Monitor Apple Watch connection
        appleWatchService.$isWatchConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.updateAppleWatchConnection(isConnected)
            }
            .store(in: &cancellables)

        // Monitor Garmin device connections
        garminService.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] garminDevices in
                self?.updateGarminDevices(garminDevices)
            }
            .store(in: &cancellables)

        // Monitor device discovery updates
        discoveryService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discoveredDevices in
                self?.updateAvailableDevices(discoveredDevices)
            }
            .store(in: &cancellables)

        print("✅ DeviceManagerService: Device monitoring setup completed")
    }

    // MARK: - Device Connection Management

    /// Update Apple Watch connection status
    private func updateAppleWatchConnection(_ isConnected: Bool) {
        if isConnected {
            let watchStatus = appleWatchService.getWatchDeviceStatus()
            let connectedWatch = ConnectedWearableDevice(
                id: "apple-watch-main",
                name: "Apple Watch",
                type: .appleWatch,
                manufacturer: "Apple",
                modelName: "Apple Watch",
                batteryLevel: watchStatus.batteryLevel,
                connectionStrength: watchStatus.reachable ? .strong : .weak,
                lastSyncDate: watchStatus.lastSyncDate,
                isRealTimeSync: true,
                capabilities: AppleWatchCapabilities.allCapabilities()
            )

            // Update or add Apple Watch
            if let existingIndex = connectedDevices.firstIndex(where: { $0.type == .appleWatch }) {
                connectedDevices[existingIndex] = connectedWatch
            } else {
                connectedDevices.append(connectedWatch)
            }

            deviceSyncStatus["apple-watch-main"] = .syncing
        } else {
            // Remove Apple Watch from connected devices
            connectedDevices.removeAll { $0.type == .appleWatch }
            deviceSyncStatus.removeValue(forKey: "apple-watch-main")
        }

        print("⌚ DeviceManagerService: Apple Watch connection updated: \(isConnected)")
    }

    /// Update Garmin device connections
    private func updateGarminDevices(_ garminDevices: [GarminDevice]) {
        // Remove existing Garmin devices
        connectedDevices.removeAll { $0.type == .garmin }

        // Add updated Garmin devices
        for garminDevice in garminDevices {
            let connectedDevice = ConnectedWearableDevice(
                id: garminDevice.id,
                name: garminDevice.displayName,
                type: .garmin,
                manufacturer: "Garmin",
                modelName: garminDevice.modelName,
                batteryLevel: garminDevice.batteryLevel / 100.0,
                connectionStrength: garminDevice.isConnected ? .strong : .weak,
                lastSyncDate: garminDevice.lastSyncDate,
                isRealTimeSync: garminDevice.supportsRealTimeSync,
                capabilities: GarminCapabilities.getCapabilities(for: garminDevice.modelName)
            )

            connectedDevices.append(connectedDevice)
            deviceSyncStatus[garminDevice.id] = garminDevice.isConnected ? .connected : .disconnected
        }

        print("🏃‍♂️ DeviceManagerService: Updated \(garminDevices.count) Garmin devices")
    }

    /// Update available devices from discovery
    private func updateAvailableDevices(_ discoveredDevices: [DiscoveredWearableDevice]) {
        availableDevices = discoveredDevices.filter { discovered in
            // Only show devices that aren't already connected
            !connectedDevices.contains { connected in
                connected.id == discovered.id ||
                (connected.type == discovered.type && connected.name == discovered.name)
            }
        }

        print("🔍 DeviceManagerService: Updated available devices: \(availableDevices.count)")
    }

    // MARK: - Device Discovery

    /// Start periodic device discovery
    private func startPeriodicDiscovery() {
        Timer.publish(every: 300, on: .main, in: .default) // Every 5 minutes
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.performDeviceDiscovery()
                }
            }
            .store(in: &cancellables)

        // Perform initial discovery
        Task {
            await performDeviceDiscovery()
        }
    }

    /// Perform device discovery across all supported types
    func performDeviceDiscovery() async {
        isDiscovering = true
        print("🔍 DeviceManagerService: Starting device discovery...")

        do {
            // Discover devices using the discovery service
            await discoveryService.discoverDevices()
            lastDiscoveryDate = Date()
            print("✅ Device discovery completed")
        } catch {
            print("❌ Device discovery failed: \(error)")
        }

        isDiscovering = false
    }

    /// Connect to a discovered device
    func connectToDevice(_ deviceId: String) async throws {
        guard let availableDevice = availableDevices.first(where: { $0.id == deviceId }) else {
            throw DeviceManagerError.deviceNotFound
        }

        print("🔗 DeviceManagerService: Attempting to connect to \(availableDevice.name)...")

        switch availableDevice.type {
        case .appleWatch:
            // Apple Watch connection is automatic through WatchConnectivity
            try await connectAppleWatch()

        case .garmin:
            try await garminService.connectDiscoveredDevice(availableDevice)

        case .fitbit:
            // Fitbit connection would be implemented here
            throw DeviceManagerError.unsupportedDeviceType

        case .unknown:
            throw DeviceManagerError.unsupportedDeviceType
        }

        // Remove from available devices once connected
        availableDevices.removeAll { $0.id == deviceId }

        print("✅ DeviceManagerService: Successfully connected to \(availableDevice.name)")
    }

    /// Connect Apple Watch through WatchConnectivity
    private func connectAppleWatch() async throws {
        // Apple Watch connection is handled automatically
        // Just ensure the watch service is properly initialized
        await appleWatchService.manualSync()
    }

    /// Disconnect from a connected device
    func disconnectFromDevice(_ deviceId: String) async throws {
        guard let connectedDevice = connectedDevices.first(where: { $0.id == deviceId }) else {
            throw DeviceManagerError.deviceNotFound
        }

        print("🔌 DeviceManagerService: Disconnecting from \(connectedDevice.name)...")

        switch connectedDevice.type {
        case .appleWatch:
            // Apple Watch disconnection is handled by the system
            break

        case .garmin:
            try await garminService.disconnectFromDevice(deviceId)

        case .fitbit:
            throw DeviceManagerError.unsupportedDeviceType

        case .unknown:
            throw DeviceManagerError.unsupportedDeviceType
        }

        // Remove from connected devices
        connectedDevices.removeAll { $0.id == deviceId }
        deviceSyncStatus.removeValue(forKey: deviceId)

        print("✅ DeviceManagerService: Disconnected from \(connectedDevice.name)")
    }

    // MARK: - Data Synchronization

    /// Sync data from all connected devices
    func syncAllDevices() async {
        print("🔄 DeviceManagerService: Starting sync for all connected devices...")

        let syncTasks = connectedDevices.map { device in
            Task {
                await syncDevice(device.id)
            }
        }

        // Wait for all sync tasks to complete
        for task in syncTasks {
            await task.value
        }

        print("✅ DeviceManagerService: All device sync completed")
    }

    /// Sync data from a specific device
    func syncDevice(_ deviceId: String) async {
        guard let device = connectedDevices.first(where: { $0.id == deviceId }) else {
            print("❌ DeviceManagerService: Device not found for sync: \(deviceId)")
            return
        }

        deviceSyncStatus[deviceId] = .syncing

        do {
            switch device.type {
            case .appleWatch:
                await appleWatchService.manualSync()

            case .garmin:
                try await garminService.syncDevice(deviceId)

            case .fitbit:
                // Fitbit sync would be implemented here
                throw DeviceManagerError.unsupportedDeviceType

            case .unknown:
                throw DeviceManagerError.unsupportedDeviceType
            }

            deviceSyncStatus[deviceId] = .connected

            // Update last sync date
            if let deviceIndex = connectedDevices.firstIndex(where: { $0.id == deviceId }) {
                connectedDevices[deviceIndex].lastSyncDate = Date()
            }

            print("✅ DeviceManagerService: Sync completed for \(device.name)")

        } catch {
            deviceSyncStatus[deviceId] = .error("Sync failed: \(error.localizedDescription)")
            print("❌ DeviceManagerService: Sync failed for \(device.name): \(error)")
        }
    }

    /// Get device sync statistics
    func getDeviceSyncStats() -> DeviceSyncStats {
        let totalDevices = connectedDevices.count
        let syncingDevices = deviceSyncStatus.values.filter {
            if case .syncing = $0 { return true }
            return false
        }.count

        let errorDevices = deviceSyncStatus.values.filter {
            if case .error = $0 { return true }
            return false
        }.count

        let connectedDevicesCount = deviceSyncStatus.values.filter {
            if case .connected = $0 { return true }
            return false
        }.count

        return DeviceSyncStats(
            totalDevices: totalDevices,
            connectedDevices: connectedDevicesCount,
            syncingDevices: syncingDevices,
            errorDevices: errorDevices,
            lastDiscoveryDate: lastDiscoveryDate
        )
    }

    // MARK: - Battery Monitoring

    /// Update battery levels for all connected devices
    func updateBatteryLevels() async {
        print("🔋 DeviceManagerService: Updating battery levels for all devices...")

        for device in connectedDevices {
            switch device.type {
            case .appleWatch:
                appleWatchService.requestWatchBatteryLevel()

            case .garmin:
                try? await garminService.updateBatteryLevel(device.id)

            case .fitbit:
                // Fitbit battery monitoring would be implemented here
                break

            case .unknown:
                break
            }
        }
    }

    /// Get devices with low battery
    func getDevicesWithLowBattery(threshold: Float = 0.20) -> [ConnectedWearableDevice] {
        return connectedDevices.filter { $0.batteryLevel < threshold }
    }

    // MARK: - Device Information

    /// Get detailed device information
    func getDeviceInfo(_ deviceId: String) -> DetailedDeviceInfo? {
        guard let device = connectedDevices.first(where: { $0.id == deviceId }) else {
            return nil
        }

        let syncStatus = deviceSyncStatus[deviceId] ?? .disconnected
        let batteryStatus = getBatteryStatus(for: device.batteryLevel)

        return DetailedDeviceInfo(
            device: device,
            syncStatus: syncStatus,
            batteryStatus: batteryStatus,
            dataTypesSupported: device.capabilities.supportedDataTypes,
            lastDataReceived: getLastDataReceivedDate(for: deviceId)
        )
    }

    /// Get battery status description
    private func getBatteryStatus(for level: Float) -> BatteryStatus {
        switch level {
        case 0.8...1.0:
            return .high
        case 0.5..<0.8:
            return .medium
        case 0.2..<0.5:
            return .low
        case 0.0..<0.2:
            return .critical
        default:
            return .unknown
        }
    }

    /// Get last data received date for a device
    private func getLastDataReceivedDate(for deviceId: String) -> Date? {
        // This would query the HealthDataStore for the most recent data from this device
        // For now, return the last sync date
        return connectedDevices.first(where: { $0.id == deviceId })?.lastSyncDate
    }

    /// Check if device supports real-time sync
    func supportsRealTimeSync(_ deviceId: String) -> Bool {
        return connectedDevices.first(where: { $0.id == deviceId })?.isRealTimeSync ?? false
    }

    /// Get device capabilities
    func getDeviceCapabilities(_ deviceId: String) -> WearableDeviceCapabilities? {
        return connectedDevices.first(where: { $0.id == deviceId })?.capabilities
    }
}

// MARK: - Supporting Types

struct ConnectedWearableDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let type: WearableDeviceType
    let manufacturer: String
    let modelName: String
    var batteryLevel: Float
    let connectionStrength: ConnectionStrength
    var lastSyncDate: Date?
    let isRealTimeSync: Bool
    let capabilities: WearableDeviceCapabilities

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ConnectedWearableDevice, rhs: ConnectedWearableDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

enum WearableDeviceType: String, CaseIterable {
    case appleWatch = "apple_watch"
    case garmin = "garmin"
    case fitbit = "fitbit"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .garmin: return "Garmin"
        case .fitbit: return "Fitbit"
        case .unknown: return "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .garmin: return "figure.run"
        case .fitbit: return "heart.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum ConnectionStrength: String, CaseIterable {
    case strong = "strong"
    case medium = "medium"
    case weak = "weak"
    case none = "none"

    var displayName: String {
        switch self {
        case .strong: return "Strong"
        case .medium: return "Medium"
        case .weak: return "Weak"
        case .none: return "No Connection"
        }
    }

    var iconName: String {
        switch self {
        case .strong: return "wifi"
        case .medium: return "wifi.exclamationmark"
        case .weak: return "wifi.slash"
        case .none: return "wifi.slash"
        }
    }
}

enum DeviceSyncStatus {
    case connected
    case syncing
    case disconnected
    case error(String)

    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .syncing: return "Syncing..."
        case .disconnected: return "Disconnected"
        case .error(let message): return "Error: \(message)"
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

enum BatteryStatus {
    case high, medium, low, critical, unknown

    var displayText: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}

struct DetailedDeviceInfo {
    let device: ConnectedWearableDevice
    let syncStatus: DeviceSyncStatus
    let batteryStatus: BatteryStatus
    let dataTypesSupported: [String]
    let lastDataReceived: Date?
}

struct DeviceSyncStats {
    let totalDevices: Int
    let connectedDevices: Int
    let syncingDevices: Int
    let errorDevices: Int
    let lastDiscoveryDate: Date?

    var healthyDevicesPercentage: Double {
        guard totalDevices > 0 else { return 0.0 }
        return Double(connectedDevices) / Double(totalDevices) * 100.0
    }

    var hasIssues: Bool {
        return errorDevices > 0
    }
}

enum DeviceManagerError: LocalizedError {
    case deviceNotFound
    case connectionFailed(String)
    case unsupportedDeviceType
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Device not found"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .unsupportedDeviceType:
            return "Unsupported device type"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}
