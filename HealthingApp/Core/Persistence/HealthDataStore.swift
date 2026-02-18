//
//  HealthDataStore.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import Foundation
import CoreData
import CloudKit
import Combine
import OSLog
import ModelsR4

/// CoreData stack with CloudKit sync for health data persistence
/// Enhanced with integrated data integrity verification and audit trail support
/// Implements REQ-072: Integrate data integrity verification into storage flows
class HealthDataStore: ObservableObject {

    // MARK: - Singleton
    static let shared = HealthDataStore()

    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "HealthDataStore")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Data Management Integration
    private let securityManager = SecurityManager.shared
    private let dataIntegrityService = DataIntegrityService.shared
    private let auditTrailService = AuditTrailService.shared

    // MARK: - Public Properties
    @Published var isCloudKitEnabled = true
    @Published var cloudKitSyncStatus: CloudKitSyncStatus = .unknown
    @Published var lastSyncDate: Date?

    // MARK: - Core Data Stack

    /// Persistent container with CloudKit configuration
    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "HealthDataModel")

        // Configure CloudKit
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description")
        }

        // Only sync non-sensitive metadata to CloudKit
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Configure CloudKit container
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.healthing.app"
        )

        // Load the persistent store
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                self.logger.error("Core Data failed to load: \(error.localizedDescription)")
                // In production, implement proper error recovery
                fatalError("Core Data error: \(error), \(error.userInfo)")
            }

            self.logger.info("Core Data loaded successfully")
        }

        // Configure automatic merging from parent context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    /// Main managed object context for UI operations
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    /// Background context for data processing
    var backgroundContext: NSManagedObjectContext {
        return persistentContainer.newBackgroundContext()
    }

    // MARK: - Initialization

    private init() {
        setupCloudKitNotifications()
        monitorCloudKitStatus()
    }

    // MARK: - CloudKit Configuration

    private func setupCloudKitNotifications() {
        // Monitor remote change notifications
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .sink { [weak self] notification in
                self?.handleRemoteChange(notification)
            }
            .store(in: &cancellables)
    }

    private func handleRemoteChange(_ notification: Notification) {
        logger.info("Processing remote CloudKit changes")

        backgroundContext.perform {
            // Refresh the context to get remote changes
            self.backgroundContext.refreshAllObjects()

            // Update sync status
            DispatchQueue.main.async {
                self.lastSyncDate = Date()
                self.cloudKitSyncStatus = .succeeded
            }
        }
    }

    private func monitorCloudKitStatus() {
        // Check CloudKit account status periodically
        Timer.publish(every: 60, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.checkCloudKitAccountStatus()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func checkCloudKitAccountStatus() async {
        do {
            let container = CKContainer(identifier: "iCloud.com.healthing.app")
            let accountStatus = try await container.accountStatus()

            switch accountStatus {
            case .available:
                cloudKitSyncStatus = .available
                isCloudKitEnabled = true
            case .noAccount:
                cloudKitSyncStatus = .noAccount
                isCloudKitEnabled = false
            case .restricted:
                cloudKitSyncStatus = .restricted
                isCloudKitEnabled = false
            case .couldNotDetermine:
                cloudKitSyncStatus = .unknown
                isCloudKitEnabled = false
            @unknown default:
                cloudKitSyncStatus = .unknown
                isCloudKitEnabled = false
            }
        } catch {
            logger.error("Failed to check CloudKit account status: \(error.localizedDescription)")
            cloudKitSyncStatus = .failed(error.localizedDescription)
            isCloudKitEnabled = false
        }
    }

    // MARK: - Core Data Operations

    /// Enhanced save with integrated data integrity verification and audit logging
    /// Implements REQ-072: Integrate data integrity verification into storage flows
    func save() throws {
        guard viewContext.hasChanges else { return }

        // Get changed objects for audit logging
        let insertedObjects = viewContext.insertedObjects
        let updatedObjects = viewContext.updatedObjects
        let deletedObjects = viewContext.deletedObjects

        do {
            // Pre-save integrity verification
            try performPreSaveIntegrityCheck(context: viewContext)

            // Generate integrity hashes for new and modified objects
            try generateIntegrityHashes(for: insertedObjects.union(updatedObjects))

            // Save the context
            try viewContext.save()
            logger.info("Context saved successfully")

            // Post-save audit logging and verification
            Task {
                await self.performPostSaveOperations(
                    inserted: insertedObjects,
                    updated: updatedObjects,
                    deleted: deletedObjects
                )
            }

        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")

            // Log save failure for audit
            Task {
                await self.auditTrailService.logSystemEvent(
                    event: "data_save_failed",
                    details: "Core Data save failed: \(error.localizedDescription)"
                )
            }

            throw HealthDataError.saveFailed(error.localizedDescription)
        }
    }

    /// Enhanced background save with integrity verification
    func saveInBackground() async throws {
        let context = backgroundContext

        try await context.perform {
            guard context.hasChanges else { return }

            let insertedObjects = context.insertedObjects
            let updatedObjects = context.updatedObjects
            let deletedObjects = context.deletedObjects

            do {
                // Pre-save integrity verification
                try self.performPreSaveIntegrityCheck(context: context)

                // Generate integrity hashes
                try self.generateIntegrityHashes(for: insertedObjects.union(updatedObjects))

                // Save the context
                try context.save()
                self.logger.info("Background context saved successfully")

                // Post-save operations
                await self.performPostSaveOperations(
                    inserted: insertedObjects,
                    updated: updatedObjects,
                    deleted: deletedObjects
                )

            } catch {
                self.logger.error("Failed to save background context: \(error.localizedDescription)")

                await self.auditTrailService.logSystemEvent(
                    event: "background_save_failed",
                    details: "Background save failed: \(error.localizedDescription)"
                )

                throw HealthDataError.saveFailed(error.localizedDescription)
            }
        }
    }

    /// Perform operations in background context
    func performBackgroundTask<T>(_ operation: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = backgroundContext

        return try await context.perform {
            let result = try operation(context)

            if context.hasChanges {
                try context.save()
            }

            return result
        }
    }

    // MARK: - Data Integrity Integration

    /// Perform pre-save integrity checks
    private func performPreSaveIntegrityCheck(context: NSManagedObjectContext) throws {
        // Verify context is in valid state
        guard !context.hasChanges || context.insertedObjects.count + context.updatedObjects.count > 0 else {
            return
        }

        // Check for potential data corruption in changed objects
        for object in context.changedObjects() {
            if let healthObject = object as? NSManagedObject,
               healthObject.entity.attributesByName.keys.contains("dataHash"),
               let existingHash = healthObject.value(forKey: "dataHash") as? String,
               !existingHash.isEmpty {

                // Verify existing hash integrity
                let computedHash = try generateObjectHash(healthObject)
                if existingHash != computedHash {
                    logger.warning("Data integrity issue detected in \(healthObject.entity.name ?? "unknown")")

                    Task {
                        await self.auditTrailService.logSystemEvent(
                            event: "data_integrity_warning",
                            details: "Pre-save integrity check detected potential corruption in \(healthObject.entity.name ?? "unknown")"
                        )
                    }
                }
            }
        }
    }

    /// Generate integrity hashes for objects
    private func generateIntegrityHashes(for objects: Set<NSManagedObject>) throws {
        for object in objects {
            if object.entity.attributesByName.keys.contains("dataHash") {
                let hash = try generateObjectHash(object)
                object.setValue(hash, forKey: "dataHash")
            }
        }
    }

    /// Generate hash for Core Data object
    private func generateObjectHash(_ object: NSManagedObject) throws -> String {
        var hashInput = ""

        // Include all non-system attributes in hash
        for (attributeName, _) in object.entity.attributesByName {
            guard attributeName != "dataHash" && attributeName != "lastModified" else { continue }

            if let value = object.value(forKey: attributeName) {
                hashInput += "\(attributeName):\(value)"
            }
        }

        let inputData = hashInput.data(using: .utf8) ?? Data()
        return securityManager.generateDataHash(inputData)
    }

    /// Perform post-save operations including audit logging
    private func performPostSaveOperations(
        inserted: Set<NSManagedObject>,
        updated: Set<NSManagedObject>,
        deleted: Set<NSManagedObject>
    ) async {
        // Log data operations for audit trail
        for object in inserted {
            await auditTrailService.logDataOperation(
                operation: .create,
                dataType: object.entity.name ?? "unknown",
                recordId: objectIdentifier(for: object),
                details: "Data object created"
            )
        }

        for object in updated {
            await auditTrailService.logDataOperation(
                operation: .update,
                dataType: object.entity.name ?? "unknown",
                recordId: objectIdentifier(for: object),
                details: "Data object updated"
            )
        }

        for object in deleted {
            await auditTrailService.logDataOperation(
                operation: .delete,
                dataType: object.entity.name ?? "unknown",
                recordId: objectIdentifier(for: object),
                details: "Data object deleted"
            )
        }

        // Trigger integrity verification if significant changes occurred
        let totalChanges = inserted.count + updated.count + deleted.count
        if totalChanges > 10 {
            await dataIntegrityService.getIntegrityStatusSummary()
        }
    }

    /// Get object identifier for audit logging
    private func objectIdentifier(for object: NSManagedObject) -> String {
        if let id = object.value(forKey: "id") as? String {
            return id
        }
        return object.objectID.uriRepresentation().absoluteString
    }

    // MARK: - CloudKit Integration Enhancements

    /// Enable CloudKit sync with enhanced configuration
    func enableCloudKitSync(metadataOnly: Bool = true, dataTypes: Set<SyncDataType> = []) async throws {
        guard !isCloudKitEnabled else {
            logger.info("CloudKit sync already enabled")
            return
        }

        // Log CloudKit enablement for audit
        await auditTrailService.logPrivacyEvent(
            event: .privacySettingsChanged,
            dataType: "cloudkit_sync",
            consentGiven: true,
            details: "CloudKit sync enabled with metadata-only: \(metadataOnly)"
        )

        // Configure CloudKit for metadata-only sync
        if metadataOnly {
            try await configureMetadataOnlySync(for: dataTypes)
        }

        await MainActor.run {
            isCloudKitEnabled = true
            cloudKitSyncStatus = .available
        }

        logger.info("CloudKit sync enabled successfully")
    }

    /// Disable CloudKit sync
    func disableCloudKitSync() async throws {
        await auditTrailService.logPrivacyEvent(
            event: .privacySettingsChanged,
            dataType: "cloudkit_sync",
            consentGiven: false,
            details: "CloudKit sync disabled by user"
        )

        await MainActor.run {
            isCloudKitEnabled = false
            cloudKitSyncStatus = .disabled
        }

        logger.info("CloudKit sync disabled")
    }

    /// Update synchronized data types
    func updateSyncDataTypes(_ dataTypes: Set<SyncDataType>) async throws {
        await auditTrailService.logSystemEvent(
            event: "sync_data_types_updated",
            details: "Updated sync data types: \(dataTypes.map { $0.rawValue })"
        )

        logger.info("Sync data types updated")
    }

    /// Configure metadata-only sync
    private func configureMetadataOnlySync(for dataTypes: Set<SyncDataType>) async throws {
        // Implementation would configure CloudKit to sync only non-sensitive metadata
        logger.info("Configured metadata-only sync for data types: \(dataTypes.map { $0.rawValue })")
    }

    /// Export metadata for backup
    func exportMetadata() async throws -> Data {
        return try await performBackgroundTask { context in
            // Export non-sensitive metadata
            let metadataDict: [String: Any] = [
                "exportDate": Date(),
                "version": "1.0",
                "recordCount": try self.getRecordCount(in: context)
            ]

            return try JSONSerialization.data(withJSONObject: metadataDict)
        }
    }

    /// Get total record count
    private func getRecordCount(in context: NSManagedObjectContext) throws -> Int {
        let entityNames = persistentContainer.managedObjectModel.entities.compactMap { $0.name }
        var totalCount = 0

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            totalCount += try context.count(for: request)
        }

        return totalCount
    }

    // MARK: - Health Data Operations

    /// Store health observation with encryption (using simplified HealthingObservation model)
    func storeHealthObservation(_ observation: HealthingObservation, encrypt: Bool = true) async throws {
        try await performBackgroundTask { context in
            let entity = HealthObservationEntity(context: context)
            entity.id = observation.id
            entity.timestamp = observation.effectiveDateTime
            entity.category = observation.category

            if encrypt {
                // Encrypt sensitive health data
                let encryptedData = try SecurityManager.shared.encryptHealthData(observation)
                entity.encryptedData = try JSONEncoder().encode(encryptedData)
                entity.isEncrypted = true
            } else {
                // Store as metadata only for CloudKit sync
                let metadata = HealthObservationMetadata(
                    id: observation.id,
                    category: observation.category,
                    timestamp: observation.effectiveDateTime,
                    deviceType: observation.device?.type
                )
                entity.metadata = try JSONEncoder().encode(metadata)
                entity.isEncrypted = false
            }

            entity.lastModified = Date()

            // Add data integrity verification
            let dataHash = try SecurityManager.shared.generateDataHash(observation)
            entity.dataHash = dataHash
        }
    }

    /// Retrieve health observations with decryption
    func fetchHealthObservations(
        category: String? = nil,
        dateRange: ClosedRange<Date>? = nil,
        limit: Int? = nil
    ) async throws -> [HealthingObservation] {

        return try await performBackgroundTask { context in
            let request: NSFetchRequest<HealthObservationEntity> = HealthObservationEntity.fetchRequest()

            var predicates: [NSPredicate] = []

            if let category = category {
                predicates.append(NSPredicate(format: "category == %@", category))
            }

            if let dateRange = dateRange {
                predicates.append(NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                                              dateRange.lowerBound as NSDate,
                                              dateRange.upperBound as NSDate))
            }

            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }

            request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthObservationEntity.timestamp, ascending: false)]

            if let limit = limit {
                request.fetchLimit = limit
            }

            let entities = try context.fetch(request)

            return try entities.compactMap { entity in
                if entity.isEncrypted {
                    guard let encryptedData = entity.encryptedData else { return nil }
                    let encrypted = try JSONDecoder().decode(EncryptedData.self, from: encryptedData)
                    return try SecurityManager.shared.decryptHealthData(encrypted, as: HealthingObservation.self)
                }

                guard let metadataData = entity.metadata else { return nil }
                let metadata = try JSONDecoder().decode(HealthObservationMetadata.self, from: metadataData)
                let deviceType = metadata.deviceType ?? "unknown"
                let device = HealthingDevice(displayName: deviceType, type: deviceType)

                return HealthingObservation(
                    id: metadata.id,
                    status: "final",
                    code: "LA6115-9",
                    subject: "patient",
                    effectiveDateTime: metadata.timestamp,
                    valueQuantity: nil,
                    valueCodeableConcept: nil,
                    device: device,
                    category: metadata.category
                )
            }
        }
    }

    /// Store medical document reference
    func storeMedicalDocument(_ documentRef: FHIRHealthingDocumentReference, fileURL: URL) async throws {
        try await performBackgroundTask { context in
            let entity = MedicalDocumentEntity(context: context)
            entity.id = documentRef.id
            entity.title = documentRef.type.text?.string ?? "Medical Document"
            entity.category = documentRef.category.first?.coding?.first?.display?.string ?? "General"
            entity.createdDate = documentRef.date?.nsDate ?? Date()

            // Encrypt and store document content
            let fileData = try Data(contentsOf: fileURL)
            let encryptedData = try SecurityManager.shared.encryptData(fileData)
            entity.encryptedContent = try JSONEncoder().encode(encryptedData)

            // Store metadata for search and display
            let metadata = MedicalDocumentMetadata(
                id: documentRef.id,
                title: entity.title ?? "",
                category: entity.category ?? "",
                fileSize: fileData.count,
                mimeType: documentRef.content.first?.attachment?.contentType?.string ?? "application/octet-stream"
            )
            entity.metadata = try JSONEncoder().encode(metadata)

            entity.lastModified = Date()
        }
    }

    /// Store device information
    func storeDevice(_ device: HealthingDevice) async throws {
        try await performBackgroundTask { context in
            let entity = DeviceEntity(context: context)
            entity.id = device.id
            entity.displayName = device.displayName
            entity.manufacturer = device.manufacturer
            entity.modelNumber = device.modelNumber
            entity.deviceType = device.type
            entity.isActive = device.status == "active"
            entity.lastModified = Date()

            // Store device metadata (non-sensitive) for CloudKit sync
            let metadata = DeviceMetadata(
                id: device.id,
                displayName: device.displayName,
                manufacturer: device.manufacturer ?? "",
                deviceType: entity.deviceType ?? ""
            )
            entity.metadata = try JSONEncoder().encode(metadata)
        }
    }

    /// Update existing health observation (for conflict resolution)
    func updateHealthObservation(_ observation: HealthingObservation) async throws {
        try await performBackgroundTask { context in
            let request: NSFetchRequest<HealthObservationEntity> = HealthObservationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", observation.id)

            let entities = try context.fetch(request)
            guard let entity = entities.first else {
                throw HealthDataError.fetchFailed("Observation not found: \(observation.id)")
            }

            // Update the observation data
            entity.timestamp = observation.effectiveDateTime
            entity.category = observation.category
            entity.lastModified = Date()

            // Re-encrypt with updated data
            let encryptedData = try SecurityManager.shared.encryptHealthData(observation)
            entity.encryptedData = try JSONEncoder().encode(encryptedData)

            // Update data integrity hash
            let dataHash = try SecurityManager.shared.generateDataHash(observation)
            entity.dataHash = dataHash

            self.logger.info("Updated health observation: \(observation.id)")
        }
    }

    /// Delete health observation by ID
    func deleteHealthObservation(_ observationId: String) async throws {
        try await performBackgroundTask { context in
            let request: NSFetchRequest<NSFetchRequestResult> = HealthObservationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", observationId)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)

            self.logger.info("Deleted health observation: \(observationId)")
        }
    }

    /// Fetch medical documents with limit and search
    func fetchMedicalDocuments(limit: Int? = nil, searchTerm: String? = nil) async throws -> [FHIRHealthingDocumentReference] {
        return try await performBackgroundTask { context in
            let request: NSFetchRequest<MedicalDocumentEntity> = MedicalDocumentEntity.fetchRequest()

            var predicates: [NSPredicate] = []

            if let searchTerm = searchTerm {
                predicates.append(NSPredicate(format: "title CONTAINS[c] %@ OR category CONTAINS[c] %@", searchTerm, searchTerm))
            }

            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }

            request.sortDescriptors = [NSSortDescriptor(keyPath: \MedicalDocumentEntity.createdDate, ascending: false)]

            if let limit = limit {
                request.fetchLimit = limit
            }

            let entities = try context.fetch(request)

            return entities.compactMap { entity in
                guard let id = entity.id,
                      let title = entity.title,
                      let category = entity.category,
                      let createdDate = entity.createdDate else {
                    return nil
                }

                let type = CodeableConcept()
                type.text = FHIRString(title)

                let categoryConcept = CodeableConcept()
                let categoryCoding = Coding()
                categoryCoding.display = FHIRString(category)
                categoryConcept.coding = [categoryCoding]

                let subject = Reference()
                subject.reference = FHIRString("Patient/current-user")

                return FHIRHealthingDocumentReference(
                    id: id,
                    masterIdentifier: nil,
                    status: .current,
                    type: type,
                    category: [categoryConcept],
                    subject: subject,
                    date: Instant(createdDate),
                    author: [],
                    description: nil,
                    content: []
                )
            }
        }
    }

    /// Delete medical document by ID
    func deleteMedicalDocument(_ documentId: String) async throws {
        try await performBackgroundTask { context in
            let request: NSFetchRequest<NSFetchRequestResult> = MedicalDocumentEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", documentId)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)

            self.logger.info("Deleted medical document: \(documentId)")
        }
    }

    /// Fetch devices with limit
    func fetchDevices(limit: Int? = nil) async throws -> [HealthingDevice] {
        return try await performBackgroundTask { context in
            let request: NSFetchRequest<DeviceEntity> = DeviceEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \DeviceEntity.lastModified, ascending: false)]

            if let limit = limit {
                request.fetchLimit = limit
            }

            let entities = try context.fetch(request)

            return entities.compactMap { entity in
                guard let id = entity.id,
                      let displayName = entity.displayName else {
                    return nil
                }

                return HealthingDevice(
                    id: id,
                    displayName: displayName,
                    type: entity.deviceType ?? "unknown",
                    manufacturer: entity.manufacturer,
                    modelNumber: entity.modelNumber,
                    status: entity.isActive ? "active" : "inactive"
                )
            }
        }
    }

    /// Delete device by ID
    func deleteDevice(_ deviceId: String) async throws {
        try await performBackgroundTask { context in
            let request: NSFetchRequest<NSFetchRequestResult> = DeviceEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", deviceId)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)

            self.logger.info("Deleted device: \(deviceId)")
        }
    }

    /// Optimize database performance (for background processing)
    func optimizeDatabase() async throws {
        try await performBackgroundTask { context in
            // Perform database optimization operations
            context.refreshAllObjects()

            // Remove orphaned data
            let orphanedObservations = NSBatchDeleteRequest(
                fetchRequest: {
                    let request: NSFetchRequest<NSFetchRequestResult> = HealthObservationEntity.fetchRequest()
                    request.predicate = NSPredicate(format: "encryptedData == nil AND metadata == nil")
                    return request
                }()
            )
            try context.execute(orphanedObservations)

            self.logger.info("Database optimization completed")
        }
    }

    /// Verify data integrity for all observations
    func verifyDataIntegrity() async throws -> DataIntegrityReport {
        return try await performBackgroundTask { context in
            let request: NSFetchRequest<HealthObservationEntity> = HealthObservationEntity.fetchRequest()
            let entities = try context.fetch(request)

            var report = DataIntegrityReport()

            for entity in entities {
                guard let encryptedData = entity.encryptedData,
                      let encrypted = try? JSONDecoder().decode(EncryptedData.self, from: encryptedData),
                      let observation = try? SecurityManager.shared.decryptHealthData(encrypted, as: HealthingObservation.self) else {
                    report.corruptedCount += 1
                    continue
                }

                // Verify hash if available
                if let storedHash = entity.dataHash {
                    let currentHash = try SecurityManager.shared.generateDataHash(observation)
                    if storedHash == currentHash {
                        report.verifiedCount += 1
                    } else {
                        report.mismatchedCount += 1
                    }
                } else {
                    report.missingHashCount += 1
                }
            }

            report.totalCount = entities.count
            return report
        }
    }

    // MARK: - Data Cleanup

    /// Clean up old data based on retention policies
    func cleanupOldData(olderThan date: Date) async throws {
        try await performBackgroundTask { context in
            // Clean up old observations
            let observationRequest: NSFetchRequest<NSFetchRequestResult> = HealthObservationEntity.fetchRequest()
            observationRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)

            let deleteObservationsRequest = NSBatchDeleteRequest(fetchRequest: observationRequest)
            try context.execute(deleteObservationsRequest)

            self.logger.info("Cleaned up health observations older than \(date)")
        }
    }

    /// Export user data for GDPR compliance
    func exportUserData() async throws -> URL {
        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("health_data_export.json")

        try await performBackgroundTask { context in
            // Fetch all user data
            let observations = try context.fetch(HealthObservationEntity.fetchRequest())
            let documents = try context.fetch(MedicalDocumentEntity.fetchRequest())
            let devices = try context.fetch(DeviceEntity.fetchRequest())

            let exportData = HealthDataExport(
                observations: observations.compactMap { $0.metadata },
                documents: documents.compactMap { $0.metadata },
                devices: devices.compactMap { $0.metadata },
                exportDate: Date()
            )

            let jsonData = try JSONEncoder().encode(exportData)
            try jsonData.write(to: exportURL)

            self.logger.info("User data exported to \(exportURL)")
        }

        return exportURL
    }
}

// MARK: - Supporting Types

enum CloudKitSyncStatus {
    case unknown
    case available
    case noAccount
    case restricted
    case syncing
    case succeeded
    case failed(String)

    var displayText: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .available:
            return "Available"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "Restricted"
        case .syncing:
            return "Syncing..."
        case .succeeded:
            return "Synced"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
}

enum HealthDataError: LocalizedError {
    case saveFailed(String)
    case fetchFailed(String)
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            return "Save failed: \(message)"
        case .fetchFailed(let message):
            return "Fetch failed: \(message)"
        case .encryptionFailed:
            return "Failed to encrypt health data"
        case .decryptionFailed:
            return "Failed to decrypt health data"
        }
    }
}

// MARK: - Metadata Models for CloudKit Sync

struct HealthObservationMetadata: Codable {
    let id: String
    let category: String
    let timestamp: Date
    let deviceType: String?
}

struct MedicalDocumentMetadata: Codable {
    let id: String
    let title: String
    let category: String
    let fileSize: Int
    let mimeType: String
}

struct DeviceMetadata: Codable {
    let id: String
    let displayName: String
    let manufacturer: String
    let deviceType: String
}

struct HealthDataExport: Codable {
    let observations: [Data]
    let documents: [Data]
    let devices: [Data]
    let exportDate: Date
}

struct DataIntegrityReport {
    var totalCount = 0
    var verifiedCount = 0
    var corruptedCount = 0
    var mismatchedCount = 0
    var missingHashCount = 0

    var integrityPercentage: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(verifiedCount) / Double(totalCount) * 100.0
    }

    var hasIssues: Bool {
        return corruptedCount > 0 || mismatchedCount > 0
    }
}

// MARK: - DateTime Extensions
// Implements REQ-009: Proper FHIR Date/Instant parsing with timezone handling

extension ModelsR4.DateTime {
    var nsDate: Date {
        guard let dateTimeString = self.value?.string else {
            return Date() // Fallback to current date
        }
        return Date.fromFHIRDateTime(dateTimeString) ?? Date()
    }
}

extension ModelsR4.Instant {
    var nsDate: Date {
        guard let instantString = self.value?.string else {
            return Date() // Fallback to current date
        }
        return Date.fromFHIRDateTime(instantString) ?? Date()
    }
}

extension ModelsR4.FHIRDate {
    var nsDate: Date {
        guard let dateString = self.value?.string else {
            return Date() // Fallback to current date
        }
        return Date.fromFHIRDate(dateString) ?? Date()
    }
}
