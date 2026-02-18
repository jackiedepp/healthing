# Wearable Integration Test Plan (Apple Watch + Garmin)

**Last Updated:** January 27, 2026  
**Scope:** Validates Apple Watch (HealthKit + WatchConnectivity), Garmin Connect integration, device discovery, and multi‑device data consolidation.

## Prerequisites
- macOS with Xcode 15+ and iOS 17+ simulator support
- Apple Watch paired to an iPhone (for real-device tests)
- Garmin Connect app installed (for Garmin auth flow)
- HealthKit permissions granted in iOS Settings for Healthing

## Automated Tests (Xcode / SwiftPM)
> Run these on macOS (not available in this Linux container).

### SwiftPM (package-based)
```bash
swift test
```

### Xcodebuild (iOS Simulator)
```bash
xcodebuild -scheme HealthingApp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  build
```

## Manual Verification (Recommended)

### 1) Apple Watch Connectivity
1. Launch Healthing on iPhone.
2. Go to **Devices → Add Device → Apple Watch**.
3. Approve HealthKit permissions.
4. Confirm:
   - Status shows **Connected**.
   - Battery level updates after sync.
   - “Last sync” updates after manual sync.

### 2) Apple Watch Health Data Ingestion
1. Record a heart rate reading in the Watch.
2. Trigger **Sync Now** in Devices.
3. Confirm new data appears in **Health Data** for heart rate.
4. Confirm no duplicate entries from HealthKit + Apple Watch sources.

### 3) Garmin Authentication + Sync (DEBUG)
1. Go to **Devices → Add Device → Garmin Device**.
2. Complete Garmin auth (mock in DEBUG).
3. Confirm Garmin device appears in **Connected Devices**.
4. Tap **Sync Now** and confirm:
   - Last sync updates.
   - Sample data appears in **Health Data**.

### 4) Device Discovery
1. Tap refresh icon in **Devices**.
2. Confirm **Available Devices** shows mock Garmin/Fitbit in DEBUG.
3. Confirm Apple Watch appears if WatchConnectivity is supported.

### 5) Multi‑device Deduplication + Conflict Resolution
1. Create overlapping heart-rate samples (manual entry + Garmin/Watch).
2. Trigger sync.
3. Confirm consolidation selects higher‑priority source in logs.

## Expected Results
- Apple Watch samples only ingested once (no duplicate HealthKit ingestion).
- Garmin devices connect via discovery flow (DEBUG adds mock device if needed).
- Device list reflects connection/battery/sync status accurately.
- Deduplication and conflict resolution keep data consistent.

## Known Limitations
- Full Garmin Connect SDK flow requires production credentials and SDK.
- Apple Watch requires real hardware; simulator cannot emulate WatchConnectivity.
