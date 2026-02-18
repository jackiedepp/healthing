//
//  DevicesView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import HealthKit

struct DevicesView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @StateObject private var deviceManager = DeviceManagerService.shared
    @StateObject private var discoveryService = DeviceDiscoveryService.shared
    @StateObject private var appleWatchService = AppleWatchService.shared
    @StateObject private var garminService = GarminConnectService.shared

    @State private var isLoading = false
    @State private var showingDeviceSetup = false
    @State private var selectedDeviceType: WearableDeviceType?
    @State private var showingDeviceDetails: ConnectedWearableDevice?
    @State private var syncingDeviceId: String?

    var body: some View {
        NavigationView {
            List {
                // Sync status section
                if isLoading || discoveryService.isDiscovering {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(isLoading ? "Loading devices..." : "Discovering devices...")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Connected devices section
                if !deviceManager.connectedDevices.isEmpty {
                    Section("Connected Devices") {
                        ForEach(deviceManager.connectedDevices) { device in
                            RealConnectedDeviceRow(
                                device: device,
                                syncStatus: deviceManager.deviceSyncStatus[device.id],
                                isSyncing: syncingDeviceId == device.id
                            ) {
                                showingDeviceDetails = device
                            } syncAction: {
                                await syncDevice(device.id)
                            }
                        }
                    }
                }

                // Available devices section
                if !discoveryService.discoveredDevices.isEmpty {
                    Section("Available Devices") {
                        ForEach(discoveryService.discoveredDevices) { device in
                            RealAvailableDeviceRow(device: device) {
                                await connectToDevice(device)
                            }
                        }
                    }
                }

                // Health data sources section
                Section("Data Sources") {
                    HealthKitSourceRow(syncService: appleWatchService)
                    ManualEntryRow()
                }

                // Device sync section
                Section("Sync Settings") {
                    SyncSettingsRow(deviceManager: deviceManager)
                }

                // Device statistics section
                Section("Statistics") {
                    DeviceStatsRow(deviceManager: deviceManager)
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task { await performDeviceDiscovery() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(discoveryService.isDiscovering)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Device") {
                        showingDeviceSetup = true
                    }
                }
            }
            .sheet(isPresented: $showingDeviceSetup) {
                RealDeviceSetupView()
            }
            .sheet(item: $showingDeviceDetails) { device in
                DeviceDetailsView(device: device)
            }
            .refreshable {
                await refreshDevices()
            }
        }
        .onAppear {
            Task {
                await loadDevices()
            }
        }
    }

    private func loadDevices() async {
        isLoading = true

        // Perform device discovery to find available devices
        await performDeviceDiscovery()

        // Update battery levels for connected devices
        await deviceManager.updateBatteryLevels()

        isLoading = false
    }

    private func refreshDevices() async {
        await loadDevices()
    }

    private func performDeviceDiscovery() async {
        await discoveryService.discoverDevices()
    }

    private func connectToDevice(_ device: DiscoveredWearableDevice) async {
        do {
            try await deviceManager.connectToDevice(device.id)
            print("✅ Connected to \(device.name)")
        } catch {
            print("❌ Failed to connect to \(device.name): \(error)")
            // Show error alert in real implementation
        }
    }

    private func syncDevice(_ deviceId: String) async {
        syncingDeviceId = deviceId
        await deviceManager.syncDevice(deviceId)
        syncingDeviceId = nil
    }
}

// MARK: - Real Connected Device Row

struct RealConnectedDeviceRow: View {
    let device: ConnectedWearableDevice
    let syncStatus: DeviceSyncStatus?
    let isSyncing: Bool
    let detailsAction: () -> Void
    let syncAction: () async -> Void

    var body: some View {
        HStack {
            WearableDeviceIcon(type: device.type, connectionStrength: device.connectionStrength)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    RealConnectionStatusBadge(
                        status: syncStatus ?? .disconnected,
                        isSyncing: isSyncing
                    )

                    if let lastSync = device.lastSyncDate {
                        Text("Last sync: \(lastSync, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Device capabilities summary
                Text(device.capabilities.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                BatteryIndicator(level: Int(device.batteryLevel * 100))

                HStack(spacing: 8) {
                    Button(action: {
                        Task { await syncAction() }
                    }) {
                        Image(systemName: isSyncing ? "arrow.clockwise" : "arrow.triangle.2.circlepath")
                            .foregroundColor(.blue)
                    }
                    .disabled(isSyncing)

                    Button("Details") {
                        detailsAction()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

}

// MARK: - Real Available Device Row

struct RealAvailableDeviceRow: View {
    let device: DiscoveredWearableDevice
    let connectAction: () async -> Void

    var body: some View {
        HStack {
            WearableDeviceIcon(type: device.type, connectionStrength: .medium)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name)
                        .fontWeight(.medium)

                    Spacer()

                    Text(device.signalStrengthDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("\(device.manufacturer) • \(device.modelName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Device capabilities
                Text(device.capabilities.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if device.requiresApp {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("Requires companion app")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if device.isConnectable {
                Button("Connect") {
                    Task { await connectAction() }
                }
                .buttonStyle(.bordered)
            } else {
                Text("Not Supported")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .opacity(device.isConnectable ? 1.0 : 0.6)
    }
}

// MARK: - Connected Device Row (Legacy)

struct ConnectedDeviceRow: View {
    let device: ConnectedDevice

    var body: some View {
        HStack {
            DeviceIcon(type: device.type)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    ConnectionStatusBadge(status: device.connectionStatus)

                    if let lastSync = device.lastSync {
                        Text("Last sync: \(lastSync, formatter: relativeDateFormatter)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(device.dataTypes.joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let batteryLevel = device.batteryLevel {
                    BatteryIndicator(level: batteryLevel)
                }

                Button("Settings") {
                    // Open device settings
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var relativeDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Available Device Row

struct AvailableDeviceRow: View {
    let device: AvailableDevice
    let connectAction: () -> Void

    var body: some View {
        HStack {
            DeviceIcon(type: device.type)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .fontWeight(.medium)

                Text(device.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !device.isSupported {
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if device.isSupported {
                Button("Connect") {
                    connectAction()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .opacity(device.isSupported ? 1.0 : 0.6)
    }
}

// MARK: - Wearable Device Icon

struct WearableDeviceIcon: View {
    let type: WearableDeviceType
    let connectionStrength: ConnectionStrength

    var body: some View {
        ZStack {
            Image(systemName: type.iconName)
                .font(.title2)
                .foregroundColor(type == .appleWatch ? .black : .blue)
                .frame(width: 30, height: 30)

            // Connection strength indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(connectionStrength == .strong ? .green :
                              connectionStrength == .medium ? .orange : .red)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: 4)
                }
            }
        }
    }
}

// MARK: - Device Icon (Legacy)

struct DeviceIcon: View {
    let type: DeviceType

    var body: some View {
        Image(systemName: type.iconName)
            .font(.title2)
            .foregroundColor(type.color)
            .frame(width: 30, height: 30)
    }
}

// MARK: - Real Connection Status Badge

struct RealConnectionStatusBadge: View {
    let status: DeviceSyncStatus
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(status.isError ? .red :
                          status == .connected ? .green :
                          status == .syncing ? .orange : .gray)
                    .frame(width: 8, height: 8)
            }

            Text(isSyncing ? "Syncing..." : status.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Connection Status Badge (Legacy)

struct ConnectionStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Text(status.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Battery Indicator

struct BatteryIndicator: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .foregroundColor(batteryColor)
                .font(.caption)

            Text("\(level)%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var batteryIcon: String {
        switch level {
        case 0...20:
            return "battery.0"
        case 21...50:
            return "battery.25"
        case 51...75:
            return "battery.50"
        case 76...90:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private var batteryColor: Color {
        switch level {
        case 0...20:
            return .red
        case 21...50:
            return .orange
        default:
            return .green
        }
    }
}

// MARK: - Enhanced Special Rows

struct HealthKitSourceRow: View {
    @ObservedObject var syncService: HealthKitSyncService

    var body: some View {
        HStack {
            Image(systemName: "heart.circle.fill")
                .font(.title2)
                .foregroundColor(.red)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Health")
                    .fontWeight(.medium)

                Text("iPhone health data and connected apps")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let lastSync = syncService.lastSyncDate {
                    Text("Last sync: \(lastSync, formatter: RelativeDateTimeFormatter())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                RealConnectionStatusBadge(
                    status: syncService.isAuthorized ? .connected : .disconnected,
                    isSyncing: syncService.syncStatus == .syncing
                )

                if syncService.isAuthorized {
                    Button("Sync Now") {
                        Task {
                            await syncService.manualSync()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ManualEntryRow: View {
    var body: some View {
        HStack {
            Image(systemName: "pencil.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Entry")
                    .fontWeight(.medium)

                Text("Add measurements manually")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Add Data") {
                // Open manual entry
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct SyncSettingsRow: View {
    @ObservedObject var deviceManager: DeviceManagerService
    @State private var autoSyncEnabled = true
    @State private var syncFrequency: SyncFrequency = .realTime

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Auto Sync")
                    .fontWeight(.medium)

                Spacer()

                Toggle("", isOn: $autoSyncEnabled)
            }

            if autoSyncEnabled {
                HStack {
                    Text("Frequency")
                        .foregroundColor(.secondary)

                    Spacer()

                    Picker("Sync Frequency", selection: $syncFrequency) {
                        ForEach(SyncFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            // Background sync status
            HStack {
                Text("Background Sync")
                    .foregroundColor(.secondary)

                Spacer()

                let backgroundService = BackgroundProcessingService.shared
                Text(backgroundService.isBackgroundRefreshEnabled ? "Enabled" : "Disabled")
                    .foregroundColor(backgroundService.isBackgroundRefreshEnabled ? .green : .orange)
            }

            // Sync all devices button
            if !deviceManager.connectedDevices.isEmpty {
                Button("Sync All Devices") {
                    Task {
                        await deviceManager.syncAllDevices()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Device Statistics Row

struct DeviceStatsRow: View {
    @ObservedObject var deviceManager: DeviceManagerService

    var body: some View {
        let stats = deviceManager.getDeviceSyncStats()

        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(stats.connectedDevices)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .center) {
                    Text("\(Int(stats.healthyDevicesPercentage))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(stats.hasIssues ? .orange : .green)
                    Text("Healthy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("\(stats.syncingDevices)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Syncing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let lastDiscovery = stats.lastDiscoveryDate {
                Text("Last discovery: \(lastDiscovery, formatter: RelativeDateTimeFormatter())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Real Device Setup View

struct RealDeviceSetupView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var appleWatchService = AppleWatchService.shared
    @StateObject private var garminService = GarminConnectService.shared
    @StateObject private var healthKitService = HealthKitSyncService.shared

    @State private var isSettingUpAppleWatch = false
    @State private var isSettingUpGarmin = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                VStack(spacing: 16) {
                    Text("Connect Your Device")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Follow the instructions to connect your wearable device and start tracking your health data automatically.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    RealDeviceSetupOption(
                        icon: "applewatch",
                        title: "Apple Watch",
                        subtitle: "Connect via Watch app and Apple Health",
                        isAvailable: true,
                        isLoading: isSettingUpAppleWatch,
                        connectionStatus: appleWatchService.isWatchConnected ? "Connected" : "Not Connected"
                    ) {
                        await setupAppleWatch()
                    }

                    RealDeviceSetupOption(
                        icon: "figure.run",
                        title: "Garmin Device",
                        subtitle: "Connect via Garmin Connect app",
                        isAvailable: true,
                        isLoading: isSettingUpGarmin,
                        connectionStatus: garminService.authenticationStatus.displayText
                    ) {
                        await setupGarminDevice()
                    }

                    RealDeviceSetupOption(
                        icon: "heart.circle",
                        title: "Fitbit Device",
                        subtitle: "Support coming soon",
                        isAvailable: false,
                        isLoading: false,
                        connectionStatus: nil
                    ) {
                        // Future Fitbit support
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Device Setup", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func setupAppleWatch() async {
        isSettingUpAppleWatch = true

        do {
            // Request HealthKit permissions first
            try await healthKitService.requestPermissions()

            // Perform Apple Watch sync
            await appleWatchService.manualSync()

            alertMessage = "Apple Watch setup completed successfully! Your health data will now sync automatically."
            showingAlert = true

        } catch {
            alertMessage = "Apple Watch setup failed: \(error.localizedDescription). Please ensure the Watch app is installed and your Apple Watch is paired."
            showingAlert = true
        }

        isSettingUpAppleWatch = false
    }

    private func setupGarminDevice() async {
        isSettingUpGarmin = true

        do {
            try await garminService.authenticateWithGarmin()

            alertMessage = "Garmin device setup completed successfully! Your Garmin data will now sync with the app."
            showingAlert = true

        } catch {
            alertMessage = "Garmin setup failed: \(error.localizedDescription). Please ensure the Garmin Connect app is installed and you have a valid Garmin account."
            showingAlert = true
        }

        isSettingUpGarmin = false
    }
}

// MARK: - Device Setup View (Legacy)

struct DeviceSetupView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                VStack(spacing: 16) {
                    Text("Connect Your Device")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Follow the instructions to connect your wearable device and start tracking your health data automatically.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    DeviceSetupOption(
                        icon: "applewatch",
                        title: "Apple Watch",
                        subtitle: "Connect via Apple Health",
                        isAvailable: true
                    ) {
                        // Setup Apple Watch
                    }

                    DeviceSetupOption(
                        icon: "figure.run",
                        title: "Garmin Device",
                        subtitle: "Connect via Garmin Connect",
                        isAvailable: true
                    ) {
                        // Setup Garmin device
                    }

                    DeviceSetupOption(
                        icon: "heart.circle",
                        title: "Other Fitness Trackers",
                        subtitle: "Support coming soon",
                        isAvailable: false
                    ) {
                        // Future device support
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct RealDeviceSetupOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let isAvailable: Bool
    let isLoading: Bool
    let connectionStatus: String?
    let action: () async -> Void

    var body: some View {
        Button(action: {
            if isAvailable && !isLoading {
                Task { await action() }
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let status = connectionStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("Connected") ? .green :
                                           status.contains("Failed") || status.contains("Error") ? .red : .orange)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isAvailable {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Text("Soon")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!isAvailable || isLoading)
        .buttonStyle(PlainButtonStyle())
    }
}

struct DeviceSetupOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: isAvailable ? action : {}) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isAvailable {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Text("Soon")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!isAvailable)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Device Details View

struct DeviceDetailsView: View {
    let device: ConnectedWearableDevice
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var deviceManager = DeviceManagerService.shared

    var body: some View {
        NavigationView {
            List {
                // Device overview section
                Section {
                    VStack(spacing: 16) {
                        WearableDeviceIcon(type: device.type, connectionStrength: device.connectionStrength)
                            .scaleEffect(2.0)
                            .padding()

                        VStack(spacing: 4) {
                            Text(device.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("\(device.manufacturer) • \(device.modelName)")
                                .foregroundColor(.secondary)
                        }

                        // Connection status
                        HStack(spacing: 16) {
                            VStack {
                                Text("Connection")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(device.connectionStrength.displayName)
                                    .fontWeight(.medium)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack {
                                Text("Battery")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(Int(device.batteryLevel * 100))%")
                                    .fontWeight(.medium)
                            }

                            if device.isRealTimeSync {
                                Divider()
                                    .frame(height: 40)

                                VStack {
                                    Text("Sync")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Real-time")
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }

                // Capabilities section
                Section("Capabilities") {
                    ForEach(device.capabilities.detailedDescription, id: \.self) { capability in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)

                            Text(capability)
                                .font(.subheadline)

                            Spacer()
                        }
                    }
                }

                // Supported health metrics
                Section("Health Metrics") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(device.capabilities.healthMetrics, id: \.self) { metric in
                            Text(metric.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }

                // Sync information
                Section("Sync Information") {
                    if let lastSync = device.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(lastSync, formatter: RelativeDateTimeFormatter())
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Battery Life")
                        Spacer()
                        Text("\(device.capabilities.maxBatteryLifeDays) day\(device.capabilities.maxBatteryLifeDays == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                    }

                    if device.capabilities.waterResistant {
                        HStack {
                            Text("Water Resistance")
                            Spacer()
                            Image(systemName: "drop.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Actions section
                Section("Actions") {
                    Button("Sync Now") {
                        Task {
                            await deviceManager.syncDevice(device.id)
                        }
                    }

                    Button("Disconnect", role: .destructive) {
                        Task {
                            try? await deviceManager.disconnectFromDevice(device.id)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct ConnectedDevice: Identifiable {
    let id: String
    let name: String
    let type: DeviceType
    let connectionStatus: ConnectionStatus
    let lastSync: Date?
    let batteryLevel: Int?
    let dataTypes: [String]
}

struct AvailableDevice: Identifiable {
    let id: String
    let name: String
    let type: DeviceType
    let description: String
    let isSupported: Bool
}

enum DeviceType {
    case appleWatch
    case garmin
    case fitbit
    case polar
    case manual

    var iconName: String {
        switch self {
        case .appleWatch:
            return "applewatch"
        case .garmin, .fitbit, .polar:
            return "figure.run.circle.fill"
        case .manual:
            return "pencil.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .appleWatch:
            return .black
        case .garmin:
            return .blue
        case .fitbit:
            return .green
        case .polar:
            return .orange
        case .manual:
            return .gray
        }
    }

    // Convert to WearableDeviceType
    var wearableDeviceType: WearableDeviceType {
        switch self {
        case .appleWatch:
            return .appleWatch
        case .garmin:
            return .garmin
        case .fitbit:
            return .fitbit
        case .polar, .manual:
            return .unknown
        }
    }
}

enum ConnectionStatus {
    case connected
    case connecting
    case disconnected
    case error

    var displayText: String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    var color: Color {
        switch self {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}

enum SyncFrequency: CaseIterable {
    case realTime
    case hourly
    case daily

    var displayName: String {
        switch self {
        case .realTime:
            return "Real-time"
        case .hourly:
            return "Every hour"
        case .daily:
            return "Once daily"
        }
    }
}

#Preview {
    DevicesView()
        .environmentObject(HealthDataStore.shared)
}
