# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Healthing is a privacy-first iOS health management app built with Stanford Spezi Framework. It tracks health data, manages medical records, and provides AI-powered insights while keeping sensitive data local.

**Tech Stack**: Swift 5.9+, SwiftUI, iOS 17.0+, Stanford Spezi Framework, CoreData + CloudKit, HealthKit

## Build Commands

```bash
# Build the project
swift build

# Run tests
swift test

# Build for release
swift build -c release

# Open in Xcode (recommended for iOS development)
open HealthingApp.xcodeproj
```

The project uses Swift Package Manager. Dependencies resolve automatically when opening in Xcode or running `swift build`.

## Architecture

### Service Layer (Singleton Pattern)
All core services use the singleton pattern with `@ObservableObject` for SwiftUI integration:

- **SecurityManager** (`Core/Security/`) - AES-256 encryption, biometric auth, Secure Enclave
- **HealthDataStore** (`Core/Persistence/`) - CoreData + CloudKit stack
- **HealthKitSyncService** (`Core/Services/`) - Real-time Apple Health sync
- **AppleWatchService** (`Core/Wearables/`) - WatchConnectivity integration
- **DeviceManagerService** (`Core/Wearables/`) - Multi-device coordination
- **WearableDataProcessor** (`Core/Wearables/`) - Cross-device data consolidation
- **OCRService** (`Core/Services/`) - Vision-based document processing
- **LocalizationManager** (`Core/Services/`) - Dynamic language switching
- **GDPRComplianceManager** (`Core/Privacy/`) - Data deletion and audit trails

Services are initialized in `AppDelegate.swift` and passed to views via `@EnvironmentObject`.

### Data Flow
```
HealthKit/Wearables → Sync Services → WearableDataProcessor
→ ConflictResolutionService → HealthDataStore (CoreData)
→ Encrypted Local Storage + Optional CloudKit Metadata Sync
```

### FHIR Compliance
The app uses Apple's `ModelsR4` package. Health data converts to FHIR format via models in `Core/DataModels/FHIRHealthModels.swift`. LOINC codes map to health observations.

## Key Patterns

### Async/Await with MainActor
Most services are marked `@MainActor`. Use `Task { }` for background operations:
```swift
Task {
    await someAsyncOperation()
}
```

### Localization
Use key-based localization. Supports English, Simplified Chinese, Traditional Chinese:
```swift
Text("dashboard".localized)
```

### Requirement Tracking
Code comments reference requirements (e.g., `// REQ-023`). See `REQUIREMENTS.md` for full list.

## Project Structure

```
HealthingApp/
├── AppDelegate.swift          # Spezi config, service initialization
├── Core/
│   ├── DataModels/           # FHIR models, internal models
│   ├── Security/             # Encryption, cert pinning
│   ├── Services/             # HealthKit, OCR, localization
│   ├── Wearables/            # Apple Watch, Garmin, device manager
│   ├── Persistence/          # CoreData stack
│   └── Privacy/              # GDPR compliance
├── Views/                    # SwiftUI views by feature
├── Resources/Localizations/  # en, zh-Hans, zh-Hant strings
└── HealthingApp Watch App/   # Companion Watch app
```

## Critical Constraints

- **Privacy-first**: Sensitive health data stays local. Only metadata syncs to CloudKit.
- **All encryption uses AES-256-GCM** via CryptoKit
- **OCR processing is local-only** via Vision framework
- **Biometric auth required** for app access

## Background Tasks

Registered in `AppDelegate.swift`:
- Health sync (BGAppRefreshTask)
- Data cleanup (BGProcessingTask)
- AI processing (BGProcessingTask)
- Device sync (BGAppRefreshTask)
