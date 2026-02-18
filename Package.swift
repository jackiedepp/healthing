// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HealthingApp",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "HealthingApp",
            targets: ["HealthingApp"]
        )
    ],
    dependencies: [
        // Stanford Spezi Framework - Foundation for health applications
        .package(url: "https://github.com/StanfordSpezi/Spezi", from: "1.8.2"),
        .package(url: "https://github.com/StanfordSpezi/SpeziHealthKit", from: "1.2.0"),
        .package(url: "https://github.com/StanfordSpezi/SpeziAccount", .upToNextMinor(from: "2.1.1")),
        .package(url: "https://github.com/StanfordSpezi/SpeziFirebase", .upToNextMinor(from: "2.0.1")),
        .package(url: "https://github.com/StanfordSpezi/SpeziOnboarding", from: "2.0.4"),

        // FHIR Models for data interoperability
        .package(url: "https://github.com/apple/FHIRModels", from: "0.5.0"),

        // CareKit for health UI components
        .package(url: "https://github.com/carekit-apple/CareKit", from: "2.0.2"),

        // Networking and utilities
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),

        // Crypto for enhanced security
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),

        // Logging for debugging and monitoring
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),

        // Core ML and Vision for document processing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),

        // Firebase for authentication and optional cloud features
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0"),

        // Garmin Connect SDK (placeholder - would be actual Garmin SDK)
        // .package(url: "https://github.com/garmin/connectsdk-ios", branch: "main"),
    ],
    targets: [
        .target(
            name: "HealthingApp",
            dependencies: [
                // Spezi Framework
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziHealthKit", package: "SpeziHealthKit"),
                .product(name: "SpeziAccount", package: "SpeziAccount"),
                .product(name: "SpeziFirebaseAccount", package: "SpeziFirebase"),
                .product(name: "SpeziFirestore", package: "SpeziFirebase"),
                .product(name: "SpeziOnboarding", package: "SpeziOnboarding"),

                // FHIR Models
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "ModelsBuild", package: "FHIRModels"),

                // CareKit
                .product(name: "CareKit", package: "CareKit"),
                .product(name: "CareKitUI", package: "CareKit"),

                // Networking
                .product(name: "Alamofire", package: "Alamofire"),

                // Security
                .product(name: "Crypto", package: "swift-crypto"),

                // Logging
                .product(name: "Logging", package: "swift-log"),

                // Firebase
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),

                // Arguments (for utilities)
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "HealthingApp",
            resources: [
                .process("Core/Persistence/HealthDataModel.xcdatamodeld"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HealthingAppTests",
            dependencies: ["HealthingApp"]
        )
    ]
)

// MARK: - Compiler Settings

// Configure Swift settings for optimal performance and security
extension Package {
    static let swiftSettings: [SwiftSetting] = [
        .enableExperimentalFeature("StrictConcurrency"),
        .enableUpcomingFeature("BareSlashRegexLiterals"),
        .enableUpcomingFeature("ConciseMagicFile"),
        .enableUpcomingFeature("ForwardTrailingClosures"),
        .enableUpcomingFeature("ImportObjcForwardDeclarations"),
        .enableUpcomingFeature("DisableOutwardActorInference"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("GlobalConcurrency"),
        .enableUpcomingFeature("IsolatedDefaultValues"),
    ]
}
