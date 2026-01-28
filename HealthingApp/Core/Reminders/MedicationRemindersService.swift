//
//  MedicationRemindersService.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import Combine
import UserNotifications
import OSLog

/// Medication reminder management service
/// Implements REQ-079: Medication reminders with intelligent scheduling
/// Supports REQ-050: Accessibility features for medication management
@MainActor
final class MedicationRemindersService: ObservableObject {

    // MARK: - Singleton
    static let shared = MedicationRemindersService()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "MedicationRemindersService")
    private let notificationService = NotificationService.shared
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    @Published var medications: [Medication] = []
    @Published var adherenceHistory: [MedicationAdherence] = []
    @Published var upcomingReminders: [MedicationReminder] = []

    // MARK: - Keys
    private let medicationsKey = "stored_medications"
    private let adherenceHistoryKey = "medication_adherence_history"

    // MARK: - Initialization
    private init() {
        loadStoredData()
        setupNotificationObservers()
        refreshUpcomingReminders()
    }

    // MARK: - Data Loading & Persistence

    private func loadStoredData() {
        // Load medications
        if let medicationsData = userDefaults.data(forKey: medicationsKey),
           let decodedMedications = try? JSONDecoder().decode([Medication].self, from: medicationsData) {
            medications = decodedMedications
        }

        // Load adherence history
        if let adherenceData = userDefaults.data(forKey: adherenceHistoryKey),
           let decodedAdherence = try? JSONDecoder().decode([MedicationAdherence].self, from: adherenceData) {
            adherenceHistory = decodedAdherence
        }

        logger.info("Loaded \(medications.count) medications and \(adherenceHistory.count) adherence records")
    }

    private func saveStoredData() {
        // Save medications
        if let medicationsData = try? JSONEncoder().encode(medications) {
            userDefaults.set(medicationsData, forKey: medicationsKey)
        }

        // Save adherence history
        if let adherenceData = try? JSONEncoder().encode(adherenceHistory) {
            userDefaults.set(adherenceData, forKey: adherenceHistoryKey)
        }

        logger.info("Saved medication data to UserDefaults")
    }

    // MARK: - Notification Observer Setup

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .medicationTaken)
            .sink { [weak self] notification in
                Task { await self?.handleMedicationTaken(notification) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .medicationSkipped)
            .sink { [weak self] notification in
                Task { await self?.handleMedicationSkipped(notification) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Medication Management

    /// Add a new medication with reminder schedule
    func addMedication(_ medication: Medication) async -> Bool {
        // Validate medication data
        guard !medication.name.isEmpty,
              !medication.schedule.isEmpty else {
            logger.error("Invalid medication data provided")
            return false
        }

        // Check for duplicate medications
        if medications.contains(where: { $0.name.lowercased() == medication.name.lowercased() }) {
            logger.warning("Medication with same name already exists: \(medication.name)")
            return false
        }

        medications.append(medication)
        saveStoredData()

        // Schedule all reminders for this medication
        let success = await scheduleRemindersForMedication(medication)

        if success {
            logger.info("Added medication: \(medication.name) with \(medication.schedule.count) reminders")
            refreshUpcomingReminders()
        } else {
            // Remove medication if scheduling failed
            medications.removeAll { $0.id == medication.id }
            saveStoredData()
        }

        return success
    }

    /// Update existing medication
    func updateMedication(_ medication: Medication) async -> Bool {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else {
            logger.error("Medication not found for update: \(medication.id)")
            return false
        }

        // Cancel existing reminders
        await cancelRemindersForMedication(medication.id)

        // Update medication
        medications[index] = medication
        saveStoredData()

        // Schedule new reminders
        let success = await scheduleRemindersForMedication(medication)

        if success {
            logger.info("Updated medication: \(medication.name)")
            refreshUpcomingReminders()
        }

        return success
    }

    /// Remove medication and cancel all reminders
    func removeMedication(_ medicationId: String) async {
        await cancelRemindersForMedication(medicationId)

        medications.removeAll { $0.id == medicationId }
        adherenceHistory.removeAll { $0.medicationId == medicationId }

        saveStoredData()
        refreshUpcomingReminders()

        logger.info("Removed medication: \(medicationId)")
    }

    /// Toggle medication active status
    func toggleMedicationStatus(_ medicationId: String) async -> Bool {
        guard let index = medications.firstIndex(where: { $0.id == medicationId }) else {
            return false
        }

        let medication = medications[index]
        let updatedMedication = Medication(
            id: medication.id,
            name: medication.name,
            dosage: medication.dosage,
            instructions: medication.instructions,
            schedule: medication.schedule,
            isActive: !medication.isActive,
            startDate: medication.startDate,
            endDate: medication.endDate,
            reminderSettings: medication.reminderSettings
        )

        return await updateMedication(updatedMedication)
    }

    // MARK: - Reminder Scheduling

    private func scheduleRemindersForMedication(_ medication: Medication) async -> Bool {
        guard medication.isActive else {
            logger.info("Skipping reminders for inactive medication: \(medication.name)")
            return true
        }

        var scheduleSuccess = true

        for scheduleItem in medication.schedule {
            let success = await scheduleReminderForTime(
                medication: medication,
                scheduleTime: scheduleItem
            )

            if !success {
                scheduleSuccess = false
                logger.error("Failed to schedule reminder for \(medication.name) at \(scheduleItem.time)")
            }
        }

        return scheduleSuccess
    }

    private func scheduleReminderForTime(
        medication: Medication,
        scheduleTime: MedicationScheduleTime
    ) async -> Bool {
        let notificationId = "\(medication.id)_\(scheduleTime.time)"

        // Create date components for the scheduled time
        let components = createDateComponents(from: scheduleTime.time)

        let title = NSLocalizedString(
            "notification.medication.title",
            comment: "Medication Reminder"
        )

        let body = String.localizedStringWithFormat(
            NSLocalizedString("notification.medication.body", comment: "Time to take %@ (%@)"),
            medication.name,
            medication.dosage
        )

        let accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("notification.medication.accessibility", comment: "Medication reminder for %@ %@"),
            medication.name,
            medication.dosage
        )

        let request = NotificationRequest(
            id: notificationId,
            title: title,
            body: body,
            category: .medication,
            trigger: .calendar(components, repeats: true),
            userInfo: [
                "medicationId": medication.id,
                "medicationName": medication.name,
                "dosage": medication.dosage,
                "scheduleTime": scheduleTime.time
            ],
            isCritical: medication.reminderSettings.isCritical,
            isHighPriority: medication.reminderSettings.isHighPriority,
            accessibilityLabel: accessibilityLabel
        )

        return await notificationService.scheduleNotification(request)
    }

    private func createDateComponents(from timeString: String) -> DateComponents {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        guard let date = formatter.date(from: timeString) else {
            logger.error("Invalid time format: \(timeString)")
            return DateComponents()
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)

        return DateComponents(hour: components.hour, minute: components.minute)
    }

    private func cancelRemindersForMedication(_ medicationId: String) async {
        let medication = medications.first { $0.id == medicationId }
        guard let med = medication else { return }

        let reminderIds = med.schedule.map { "\(medicationId)_\($0.time)" }
        await notificationService.cancelNotifications(withIds: reminderIds)

        logger.info("Cancelled \(reminderIds.count) reminders for medication: \(medicationId)")
    }

    // MARK: - Adherence Tracking

    private func handleMedicationTaken(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let medicationId = userInfo["medicationId"] as? String,
              let timestamp = userInfo["timestamp"] as? Date else {
            return
        }

        let adherence = MedicationAdherence(
            medicationId: medicationId,
            timestamp: timestamp,
            status: .taken,
            scheduledTime: extractScheduledTime(from: userInfo)
        )

        adherenceHistory.append(adherence)
        saveStoredData()

        logger.info("Recorded medication taken: \(medicationId)")

        // Update upcoming reminders
        refreshUpcomingReminders()

        // Check for adherence milestones
        await checkAdherenceMilestones(medicationId: medicationId)
    }

    private func handleMedicationSkipped(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let medicationId = userInfo["medicationId"] as? String,
              let timestamp = userInfo["timestamp"] as? Date else {
            return
        }

        let adherence = MedicationAdherence(
            medicationId: medicationId,
            timestamp: timestamp,
            status: .skipped,
            scheduledTime: extractScheduledTime(from: userInfo)
        )

        adherenceHistory.append(adherence)
        saveStoredData()

        logger.warning("Recorded medication skipped: \(medicationId)")

        // Check if we should suggest adherence support
        await checkAdherencePatterns(medicationId: medicationId)
    }

    private func extractScheduledTime(from userInfo: [AnyHashable: Any]) -> String? {
        return userInfo["scheduleTime"] as? String
    }

    private func checkAdherenceMilestones(medicationId: String) async {
        let recentAdherence = adherenceHistory
            .filter { $0.medicationId == medicationId && $0.status == .taken }
            .suffix(30) // Last 30 doses

        if recentAdherence.count == 30 {
            // 30-day adherence milestone
            await notifyAdherenceMilestone(medicationId: medicationId, days: 30)
        } else if recentAdherence.count == 7 {
            // 1-week adherence milestone
            await notifyAdherenceMilestone(medicationId: medicationId, days: 7)
        }
    }

    private func notifyAdherenceMilestone(medicationId: String, days: Int) async {
        guard let medication = medications.first(where: { $0.id == medicationId }) else { return }

        let title = NSLocalizedString("notification.adherence.milestone.title", comment: "Great Job!")
        let body = String.localizedStringWithFormat(
            NSLocalizedString("notification.adherence.milestone.body", comment: "You've taken %@ consistently for %d days!"),
            medication.name,
            days
        )

        let request = NotificationRequest(
            id: "adherence_milestone_\(medicationId)_\(days)",
            title: title,
            body: body,
            category: .achievement,
            trigger: .immediate,
            userInfo: [
                "type": "adherence_milestone",
                "medicationId": medicationId,
                "days": "\(days)"
            ]
        )

        await notificationService.scheduleNotification(request)
    }

    private func checkAdherencePatterns(medicationId: String) async {
        let recentAdherence = adherenceHistory
            .filter { $0.medicationId == medicationId }
            .suffix(14) // Last 2 weeks

        let skippedCount = recentAdherence.filter { $0.status == .skipped }.count

        // If more than 3 skipped doses in 2 weeks, offer support
        if skippedCount >= 3 {
            await offerAdherenceSupport(medicationId: medicationId)
        }
    }

    private func offerAdherenceSupport(medicationId: String) async {
        guard let medication = medications.first(where: { $0.id == medicationId }) else { return }

        let title = NSLocalizedString("notification.adherence.support.title", comment: "Need Help?")
        let body = String.localizedStringWithFormat(
            NSLocalizedString("notification.adherence.support.body", comment: "We noticed you've missed some doses of %@. Would you like to adjust your reminder settings?"),
            medication.name
        )

        let request = NotificationRequest(
            id: "adherence_support_\(medicationId)",
            title: title,
            body: body,
            category: .medication,
            trigger: .immediate,
            userInfo: [
                "type": "adherence_support",
                "medicationId": medicationId
            ]
        )

        await notificationService.scheduleNotification(request)
    }

    // MARK: - Analytics and Reporting

    /// Calculate adherence rate for a medication over a period
    func getAdherenceRate(for medicationId: String, days: Int = 30) -> Double {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let adherenceInPeriod = adherenceHistory.filter {
            $0.medicationId == medicationId && $0.timestamp >= startDate
        }

        let takenCount = adherenceInPeriod.filter { $0.status == .taken }.count
        let totalCount = adherenceInPeriod.count

        guard totalCount > 0 else { return 0.0 }

        return Double(takenCount) / Double(totalCount) * 100.0
    }

    /// Get adherence summary for all active medications
    func getAdherenceSummary() -> [MedicationAdherenceSummary] {
        return medications.filter { $0.isActive }.map { medication in
            let rate = getAdherenceRate(for: medication.id)
            let lastTaken = adherenceHistory
                .filter { $0.medicationId == medication.id && $0.status == .taken }
                .sorted { $0.timestamp > $1.timestamp }
                .first?.timestamp

            return MedicationAdherenceSummary(
                medication: medication,
                adherenceRate: rate,
                lastTaken: lastTaken,
                nextDose: getNextScheduledDose(for: medication)
            )
        }
    }

    private func getNextScheduledDose(for medication: Medication) -> Date? {
        let today = Calendar.current.startOfDay(for: Date())

        for scheduleTime in medication.schedule {
            if let nextDate = getNextOccurrence(of: scheduleTime.time, after: Date()) {
                return nextDate
            }
        }

        return nil
    }

    private func getNextOccurrence(of timeString: String, after date: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        guard let scheduledTime = formatter.date(from: timeString) else { return nil }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)

        // Try today first
        var nextDate = calendar.nextDate(
            after: date,
            matching: timeComponents,
            matchingPolicy: .nextTime
        )

        return nextDate
    }

    // MARK: - Upcoming Reminders

    private func refreshUpcomingReminders() {
        let now = Date()
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        var reminders: [MedicationReminder] = []

        for medication in medications.filter({ $0.isActive }) {
            for scheduleTime in medication.schedule {
                if let nextTime = getNextOccurrence(of: scheduleTime.time, after: now),
                   nextTime <= endOfToday {

                    let reminder = MedicationReminder(
                        id: "\(medication.id)_\(scheduleTime.time)",
                        medicationId: medication.id,
                        medicationName: medication.name,
                        dosage: medication.dosage,
                        scheduledTime: nextTime,
                        instructions: medication.instructions
                    )

                    reminders.append(reminder)
                }
            }
        }

        upcomingReminders = reminders.sorted { $0.scheduledTime < $1.scheduledTime }
    }
}

// MARK: - Supporting Models

/// Medication data model
struct Medication: Codable, Identifiable {
    let id: String
    let name: String
    let dosage: String
    let instructions: String
    let schedule: [MedicationScheduleTime]
    let isActive: Bool
    let startDate: Date
    let endDate: Date?
    let reminderSettings: MedicationReminderSettings

    init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String,
        instructions: String = "",
        schedule: [MedicationScheduleTime],
        isActive: Bool = true,
        startDate: Date = Date(),
        endDate: Date? = nil,
        reminderSettings: MedicationReminderSettings = MedicationReminderSettings()
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.instructions = instructions
        self.schedule = schedule
        self.isActive = isActive
        self.startDate = startDate
        self.endDate = endDate
        self.reminderSettings = reminderSettings
    }
}

/// Medication schedule time
struct MedicationScheduleTime: Codable {
    let time: String // Format: "HH:mm"
    let label: String? // e.g., "Morning", "With breakfast"

    init(time: String, label: String? = nil) {
        self.time = time
        self.label = label
    }
}

/// Medication reminder settings
struct MedicationReminderSettings: Codable {
    let isCritical: Bool
    let isHighPriority: Bool
    let soundEnabled: Bool
    let advanceReminder: Int // Minutes before scheduled time

    init(
        isCritical: Bool = false,
        isHighPriority: Bool = true,
        soundEnabled: Bool = true,
        advanceReminder: Int = 0
    ) {
        self.isCritical = isCritical
        self.isHighPriority = isHighPriority
        self.soundEnabled = soundEnabled
        self.advanceReminder = advanceReminder
    }
}

/// Medication adherence record
struct MedicationAdherence: Codable, Identifiable {
    let id: String
    let medicationId: String
    let timestamp: Date
    let status: AdherenceStatus
    let scheduledTime: String?

    init(
        id: String = UUID().uuidString,
        medicationId: String,
        timestamp: Date,
        status: AdherenceStatus,
        scheduledTime: String? = nil
    ) {
        self.id = id
        self.medicationId = medicationId
        self.timestamp = timestamp
        self.status = status
        self.scheduledTime = scheduledTime
    }
}

/// Adherence status
enum AdherenceStatus: String, Codable, CaseIterable {
    case taken = "taken"
    case skipped = "skipped"
    case late = "late"
}

/// Upcoming medication reminder
struct MedicationReminder: Identifiable {
    let id: String
    let medicationId: String
    let medicationName: String
    let dosage: String
    let scheduledTime: Date
    let instructions: String
}

/// Medication adherence summary
struct MedicationAdherenceSummary: Identifiable {
    var id: String { medication.id }
    let medication: Medication
    let adherenceRate: Double
    let lastTaken: Date?
    let nextDose: Date?
}