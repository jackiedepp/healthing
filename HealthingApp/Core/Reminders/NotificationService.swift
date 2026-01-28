//
//  NotificationService.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import UserNotifications
import UIKit
import OSLog

/// Core notification management service for health-related reminders
/// Implements REQ-079: Medication and appointment reminders
/// Supports REQ-050: Accessibility features for notification management
@MainActor
final class NotificationService: ObservableObject {

    // MARK: - Singleton
    static let shared = NotificationService()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "NotificationService")
    private let notificationCenter = UNUserNotificationCenter.current()

    @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingNotifications: [NotificationRequest] = []

    // MARK: - Notification Categories
    private let medicationCategoryId = "MEDICATION_REMINDER"
    private let appointmentCategoryId = "APPOINTMENT_REMINDER"
    private let healthGoalCategoryId = "HEALTH_GOAL_REMINDER"
    private let achievementCategoryId = "ACHIEVEMENT_NOTIFICATION"

    // MARK: - Initialization
    private init() {
        setupNotificationCategories()
        checkNotificationPermission()
    }

    // MARK: - Permission Management

    /// Request notification permissions from user
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )

            await MainActor.run {
                notificationPermissionStatus = granted ? .authorized : .denied
            }

            if granted {
                logger.info("Notification permissions granted")
            } else {
                logger.warning("Notification permissions denied")
            }

            return granted
        } catch {
            logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            await MainActor.run {
                notificationPermissionStatus = .denied
            }
            return false
        }
    }

    /// Check current notification permission status
    private func checkNotificationPermission() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                notificationPermissionStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Notification Categories Setup

    private func setupNotificationCategories() {
        let categories: Set<UNNotificationCategory> = [
            createMedicationCategory(),
            createAppointmentCategory(),
            createHealthGoalCategory(),
            createAchievementCategory()
        ]

        notificationCenter.setNotificationCategories(categories)
    }

    private func createMedicationCategory() -> UNNotificationCategory {
        let takenAction = UNNotificationAction(
            identifier: "MEDICATION_TAKEN",
            title: NSLocalizedString("notification.medication.action.taken", comment: "Taken"),
            options: [.foreground]
        )

        let skipAction = UNNotificationAction(
            identifier: "MEDICATION_SKIP",
            title: NSLocalizedString("notification.medication.action.skip", comment: "Skip"),
            options: [.destructive]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "MEDICATION_SNOOZE",
            title: NSLocalizedString("notification.medication.action.snooze", comment: "Remind in 15 min"),
            options: []
        )

        return UNNotificationCategory(
            identifier: medicationCategoryId,
            actions: [takenAction, snoozeAction, skipAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: NSLocalizedString("notification.medication.hidden.placeholder", comment: "Medication reminder"),
            options: [.customDismissAction]
        )
    }

    private func createAppointmentCategory() -> UNNotificationCategory {
        let confirmAction = UNNotificationAction(
            identifier: "APPOINTMENT_CONFIRM",
            title: NSLocalizedString("notification.appointment.action.confirm", comment: "Confirm"),
            options: [.foreground]
        )

        let rescheduleAction = UNNotificationAction(
            identifier: "APPOINTMENT_RESCHEDULE",
            title: NSLocalizedString("notification.appointment.action.reschedule", comment: "Reschedule"),
            options: [.foreground]
        )

        return UNNotificationCategory(
            identifier: appointmentCategoryId,
            actions: [confirmAction, rescheduleAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: NSLocalizedString("notification.appointment.hidden.placeholder", comment: "Appointment reminder"),
            options: [.customDismissAction]
        )
    }

    private func createHealthGoalCategory() -> UNNotificationCategory {
        let viewProgressAction = UNNotificationAction(
            identifier: "HEALTH_GOAL_VIEW",
            title: NSLocalizedString("notification.healthgoal.action.view", comment: "View Progress"),
            options: [.foreground]
        )

        let updateGoalAction = UNNotificationAction(
            identifier: "HEALTH_GOAL_UPDATE",
            title: NSLocalizedString("notification.healthgoal.action.update", comment: "Update Goal"),
            options: [.foreground]
        )

        return UNNotificationCategory(
            identifier: healthGoalCategoryId,
            actions: [viewProgressAction, updateGoalAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: NSLocalizedString("notification.healthgoal.hidden.placeholder", comment: "Health goal reminder"),
            options: [.customDismissAction]
        )
    }

    private func createAchievementCategory() -> UNNotificationCategory {
        let viewAchievementAction = UNNotificationAction(
            identifier: "ACHIEVEMENT_VIEW",
            title: NSLocalizedString("notification.achievement.action.view", comment: "View Achievement"),
            options: [.foreground]
        )

        let shareAction = UNNotificationAction(
            identifier: "ACHIEVEMENT_SHARE",
            title: NSLocalizedString("notification.achievement.action.share", comment: "Share"),
            options: [.foreground]
        )

        return UNNotificationCategory(
            identifier: achievementCategoryId,
            actions: [viewAchievementAction, shareAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: NSLocalizedString("notification.achievement.hidden.placeholder", comment: "New achievement unlocked!"),
            options: [.customDismissAction]
        )
    }

    // MARK: - Notification Scheduling

    /// Schedule a notification with comprehensive customization options
    func scheduleNotification(_ request: NotificationRequest) async -> Bool {
        guard notificationPermissionStatus == .authorized else {
            logger.warning("Attempted to schedule notification without permission")
            return false
        }

        let content = createNotificationContent(from: request)
        let trigger = createNotificationTrigger(from: request)

        let notificationRequest = UNNotificationRequest(
            identifier: request.id,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(notificationRequest)
            logger.info("Scheduled notification: \(request.id)")

            await MainActor.run {
                pendingNotifications.append(request)
            }

            return true
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
            return false
        }
    }

    /// Schedule multiple notifications in batch
    func scheduleNotifications(_ requests: [NotificationRequest]) async -> Int {
        var successCount = 0

        for request in requests {
            if await scheduleNotification(request) {
                successCount += 1
            }
        }

        logger.info("Scheduled \(successCount)/\(requests.count) notifications")
        return successCount
    }

    // MARK: - Notification Content Creation

    private func createNotificationContent(from request: NotificationRequest) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        content.title = request.title
        content.body = request.body
        content.categoryIdentifier = request.category.rawValue
        content.userInfo = request.userInfo

        // Badge configuration
        if let badge = request.badge {
            content.badge = NSNumber(value: badge)
        }

        // Sound configuration
        if request.isCritical {
            content.sound = .defaultCritical
            content.interruptionLevel = .critical
        } else if request.isHighPriority {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        } else {
            content.sound = .default
            content.interruptionLevel = .active
        }

        // Accessibility support
        if let accessibilityLabel = request.accessibilityLabel {
            content.userInfo["accessibilityLabel"] = accessibilityLabel
        }

        return content
    }

    private func createNotificationTrigger(from request: NotificationRequest) -> UNNotificationTrigger? {
        switch request.trigger {
        case .timeInterval(let seconds):
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)

        case .calendar(let dateComponents, let repeats):
            return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)

        case .immediate:
            return nil // Immediate delivery
        }
    }

    // MARK: - Notification Management

    /// Cancel specific notification by ID
    func cancelNotification(withId id: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])

        await MainActor.run {
            pendingNotifications.removeAll { $0.id == id }
        }

        logger.info("Cancelled notification: \(id)")
    }

    /// Cancel multiple notifications by IDs
    func cancelNotifications(withIds ids: [String]) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)

        await MainActor.run {
            pendingNotifications.removeAll { ids.contains($0.id) }
        }

        logger.info("Cancelled \(ids.count) notifications")
    }

    /// Cancel all notifications of specific category
    func cancelNotifications(ofCategory category: NotificationCategory) async {
        let settings = await notificationCenter.notificationSettings()
        let pendingRequests = await notificationCenter.pendingNotificationRequests()

        let idsToCancel = pendingRequests
            .filter { $0.content.categoryIdentifier == category.rawValue }
            .map { $0.identifier }

        await cancelNotifications(withIds: idsToCancel)
    }

    /// Get all pending notifications
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    /// Update notification badge count
    func updateBadgeCount(_ count: Int) async {
        guard let application = await UIApplication.shared else { return }

        await MainActor.run {
            application.applicationIconBadgeNumber = count
        }
    }

    /// Clear all delivered notifications
    func clearDeliveredNotifications() async {
        notificationCenter.removeAllDeliveredNotifications()
        await updateBadgeCount(0)
        logger.info("Cleared all delivered notifications")
    }

    // MARK: - Notification Response Handling

    /// Handle notification action responses
    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        let identifier = response.actionIdentifier
        let notificationId = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        logger.info("Handling notification action: \(identifier) for notification: \(notificationId)")

        switch identifier {
        case "MEDICATION_TAKEN":
            await handleMedicationTaken(notificationId: notificationId, userInfo: userInfo)

        case "MEDICATION_SKIP":
            await handleMedicationSkipped(notificationId: notificationId, userInfo: userInfo)

        case "MEDICATION_SNOOZE":
            await handleMedicationSnoozed(notificationId: notificationId, userInfo: userInfo)

        case "APPOINTMENT_CONFIRM":
            await handleAppointmentConfirmed(notificationId: notificationId, userInfo: userInfo)

        case "APPOINTMENT_RESCHEDULE":
            await handleAppointmentReschedule(notificationId: notificationId, userInfo: userInfo)

        case "HEALTH_GOAL_VIEW", "ACHIEVEMENT_VIEW":
            await handleViewAction(notificationId: notificationId, userInfo: userInfo)

        case "ACHIEVEMENT_SHARE":
            await handleShareAchievement(notificationId: notificationId, userInfo: userInfo)

        default:
            logger.info("Unhandled notification action: \(identifier)")
        }
    }

    // MARK: - Action Handlers

    private func handleMedicationTaken(notificationId: String, userInfo: [AnyHashable: Any]) async {
        if let medicationId = userInfo["medicationId"] as? String {
            // This will be handled by MedicationRemindersService
            NotificationCenter.default.post(
                name: .medicationTaken,
                object: nil,
                userInfo: ["medicationId": medicationId, "timestamp": Date()]
            )
        }
    }

    private func handleMedicationSkipped(notificationId: String, userInfo: [AnyHashable: Any]) async {
        if let medicationId = userInfo["medicationId"] as? String {
            NotificationCenter.default.post(
                name: .medicationSkipped,
                object: nil,
                userInfo: ["medicationId": medicationId, "timestamp": Date()]
            )
        }
    }

    private func handleMedicationSnoozed(notificationId: String, userInfo: [AnyHashable: Any]) async {
        if let medicationId = userInfo["medicationId"] as? String {
            // Schedule snooze reminder
            let snoozeRequest = NotificationRequest(
                id: "\(medicationId)_snooze_\(Date().timeIntervalSince1970)",
                title: NSLocalizedString("notification.medication.snooze.title", comment: "Medication Reminder"),
                body: NSLocalizedString("notification.medication.snooze.body", comment: "Don't forget your medication"),
                category: .medication,
                trigger: .timeInterval(15 * 60), // 15 minutes
                userInfo: userInfo
            )

            await scheduleNotification(snoozeRequest)
        }
    }

    private func handleAppointmentConfirmed(notificationId: String, userInfo: [AnyHashable: Any]) async {
        if let appointmentId = userInfo["appointmentId"] as? String {
            NotificationCenter.default.post(
                name: .appointmentConfirmed,
                object: nil,
                userInfo: ["appointmentId": appointmentId]
            )
        }
    }

    private func handleAppointmentReschedule(notificationId: String, userInfo: [AnyHashable: Any]) async {
        if let appointmentId = userInfo["appointmentId"] as? String {
            NotificationCenter.default.post(
                name: .appointmentRescheduleRequested,
                object: nil,
                userInfo: ["appointmentId": appointmentId]
            )
        }
    }

    private func handleViewAction(notificationId: String, userInfo: [AnyHashable: Any]) async {
        // Deep link to appropriate view
        NotificationCenter.default.post(
            name: .notificationViewRequested,
            object: nil,
            userInfo: userInfo
        )
    }

    private func handleShareAchievement(notificationId: String, userInfo: [AnyHashable: Any]) async {
        if let achievementId = userInfo["achievementId"] as? String {
            NotificationCenter.default.post(
                name: .achievementShareRequested,
                object: nil,
                userInfo: ["achievementId": achievementId]
            )
        }
    }
}

// MARK: - Supporting Models

/// Notification request data model
struct NotificationRequest: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let category: NotificationCategory
    let trigger: NotificationTrigger
    let userInfo: [String: String]
    let badge: Int?
    let isCritical: Bool
    let isHighPriority: Bool
    let accessibilityLabel: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        category: NotificationCategory,
        trigger: NotificationTrigger,
        userInfo: [String: String] = [:],
        badge: Int? = nil,
        isCritical: Bool = false,
        isHighPriority: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.trigger = trigger
        self.userInfo = userInfo
        self.badge = badge
        self.isCritical = isCritical
        self.isHighPriority = isHighPriority
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Notification categories for different reminder types
enum NotificationCategory: String, CaseIterable, Codable {
    case medication = "MEDICATION_REMINDER"
    case appointment = "APPOINTMENT_REMINDER"
    case healthGoal = "HEALTH_GOAL_REMINDER"
    case achievement = "ACHIEVEMENT_NOTIFICATION"
}

/// Notification trigger types
enum NotificationTrigger: Codable {
    case immediate
    case timeInterval(TimeInterval)
    case calendar(DateComponents, repeats: Bool)
}

// MARK: - NotificationCenter Extensions

extension Notification.Name {
    static let medicationTaken = Notification.Name("medicationTaken")
    static let medicationSkipped = Notification.Name("medicationSkipped")
    static let appointmentConfirmed = Notification.Name("appointmentConfirmed")
    static let appointmentRescheduleRequested = Notification.Name("appointmentRescheduleRequested")
    static let notificationViewRequested = Notification.Name("notificationViewRequested")
    static let achievementShareRequested = Notification.Name("achievementShareRequested")
}