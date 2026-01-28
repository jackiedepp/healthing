//
//  AppointmentRemindersService.swift
//  HealthingApp
//
//  Created by Claude on 2026-01-28.
//

import Foundation
import Combine
import UserNotifications
import EventKit
import OSLog

/// Healthcare appointment reminder management service
/// Implements REQ-079: Appointment reminders with calendar integration
/// Implements REQ-080: Pre-visit health summaries preparation
/// Supports REQ-050: Accessibility features for appointment management
@MainActor
final class AppointmentRemindersService: ObservableObject {

    // MARK: - Singleton
    static let shared = AppointmentRemindersService()

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.healthing.app", category: "AppointmentRemindersService")
    private let notificationService = NotificationService.shared
    private let eventStore = EKEventStore()
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    @Published var appointments: [HealthAppointment] = []
    @Published var upcomingAppointments: [HealthAppointment] = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Keys
    private let appointmentsKey = "stored_appointments"

    // MARK: - Initialization
    private init() {
        loadStoredData()
        setupNotificationObservers()
        checkCalendarAuthorizationStatus()
        refreshUpcomingAppointments()
    }

    // MARK: - Data Loading & Persistence

    private func loadStoredData() {
        if let appointmentsData = userDefaults.data(forKey: appointmentsKey),
           let decodedAppointments = try? JSONDecoder().decode([HealthAppointment].self, from: appointmentsData) {
            appointments = decodedAppointments
        }

        logger.info("Loaded \(appointments.count) appointments")
    }

    private func saveStoredData() {
        if let appointmentsData = try? JSONEncoder().encode(appointments) {
            userDefaults.set(appointmentsData, forKey: appointmentsKey)
        }

        logger.info("Saved \(appointments.count) appointments to UserDefaults")
    }

    // MARK: - Calendar Authorization

    /// Request calendar access permissions
    func requestCalendarPermission() async -> Bool {
        let status = await eventStore.requestFullAccessToEvents()

        await MainActor.run {
            calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }

        logger.info("Calendar authorization status: \(calendarAuthorizationStatus.rawValue)")
        return status
    }

    private func checkCalendarAuthorizationStatus() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Notification Observer Setup

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .appointmentConfirmed)
            .sink { [weak self] notification in
                Task { await self?.handleAppointmentConfirmed(notification) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appointmentRescheduleRequested)
            .sink { [weak self] notification in
                Task { await self?.handleAppointmentRescheduleRequest(notification) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Appointment Management

    /// Add a new appointment with reminders
    func addAppointment(_ appointment: HealthAppointment) async -> Bool {
        // Validate appointment data
        guard !appointment.title.isEmpty,
              appointment.dateTime > Date() else {
            logger.error("Invalid appointment data provided")
            return false
        }

        appointments.append(appointment)
        saveStoredData()

        // Schedule reminders for this appointment
        let reminderSuccess = await scheduleRemindersForAppointment(appointment)

        // Add to device calendar if authorized
        let calendarSuccess = await addAppointmentToCalendar(appointment)

        if reminderSuccess {
            logger.info("Added appointment: \(appointment.title) on \(appointment.dateTime)")
            refreshUpcomingAppointments()

            // Schedule pre-visit summary preparation
            await schedulePreVisitSummaryPreparation(appointment)
        } else {
            // Remove appointment if scheduling failed
            appointments.removeAll { $0.id == appointment.id }
            saveStoredData()
        }

        return reminderSuccess
    }

    /// Update existing appointment
    func updateAppointment(_ appointment: HealthAppointment) async -> Bool {
        guard let index = appointments.firstIndex(where: { $0.id == appointment.id }) else {
            logger.error("Appointment not found for update: \(appointment.id)")
            return false
        }

        let oldAppointment = appointments[index]

        // Cancel existing reminders
        await cancelRemindersForAppointment(oldAppointment.id)

        // Remove from calendar if it was added
        await removeAppointmentFromCalendar(oldAppointment)

        // Update appointment
        appointments[index] = appointment
        saveStoredData()

        // Schedule new reminders
        let reminderSuccess = await scheduleRemindersForAppointment(appointment)

        // Add updated appointment to calendar
        let calendarSuccess = await addAppointmentToCalendar(appointment)

        if reminderSuccess {
            logger.info("Updated appointment: \(appointment.title)")
            refreshUpcomingAppointments()

            // Update pre-visit summary preparation
            await schedulePreVisitSummaryPreparation(appointment)
        }

        return reminderSuccess
    }

    /// Remove appointment and cancel all reminders
    func removeAppointment(_ appointmentId: String) async {
        guard let appointment = appointments.first(where: { $0.id == appointmentId }) else {
            return
        }

        await cancelRemindersForAppointment(appointmentId)
        await removeAppointmentFromCalendar(appointment)

        appointments.removeAll { $0.id == appointmentId }
        saveStoredData()
        refreshUpcomingAppointments()

        logger.info("Removed appointment: \(appointmentId)")
    }

    /// Confirm appointment attendance
    func confirmAppointment(_ appointmentId: String) async {
        guard let index = appointments.firstIndex(where: { $0.id == appointmentId }) else {
            return
        }

        let appointment = appointments[index]
        let updatedAppointment = HealthAppointment(
            id: appointment.id,
            title: appointment.title,
            providerName: appointment.providerName,
            location: appointment.location,
            dateTime: appointment.dateTime,
            duration: appointment.duration,
            appointmentType: appointment.appointmentType,
            notes: appointment.notes,
            reminderSettings: appointment.reminderSettings,
            isConfirmed: true,
            calendarEventId: appointment.calendarEventId
        )

        appointments[index] = updatedAppointment
        saveStoredData()

        logger.info("Confirmed appointment: \(appointmentId)")

        // Send confirmation notification
        await sendConfirmationNotification(updatedAppointment)
    }

    // MARK: - Reminder Scheduling

    private func scheduleRemindersForAppointment(_ appointment: HealthAppointment) async -> Bool {
        var allSuccess = true

        // Schedule based on reminder settings
        for reminderMinutes in appointment.reminderSettings.reminderTimes {
            let success = await scheduleReminderForAppointment(
                appointment: appointment,
                minutesBefore: reminderMinutes
            )

            if !success {
                allSuccess = false
                logger.error("Failed to schedule reminder \(reminderMinutes) minutes before appointment: \(appointment.id)")
            }
        }

        return allSuccess
    }

    private func scheduleReminderForAppointment(
        appointment: HealthAppointment,
        minutesBefore: Int
    ) async -> Bool {
        let reminderTime = appointment.dateTime.addingTimeInterval(-Double(minutesBefore * 60))
        let notificationId = "\(appointment.id)_reminder_\(minutesBefore)"

        // Don't schedule reminders for past times
        guard reminderTime > Date() else {
            logger.info("Skipping past reminder time for appointment: \(appointment.id)")
            return true
        }

        let title: String
        let body: String

        if minutesBefore >= 1440 { // 24 hours or more
            let days = minutesBefore / 1440
            title = NSLocalizedString("notification.appointment.reminder.day.title", comment: "Appointment Tomorrow")
            body = String.localizedStringWithFormat(
                NSLocalizedString("notification.appointment.reminder.day.body", comment: "You have an appointment with %@ in %d day(s)"),
                appointment.providerName,
                days
            )
        } else if minutesBefore >= 60 { // 1 hour or more
            let hours = minutesBefore / 60
            title = NSLocalizedString("notification.appointment.reminder.hour.title", comment: "Appointment Today")
            body = String.localizedStringWithFormat(
                NSLocalizedString("notification.appointment.reminder.hour.body", comment: "Your appointment with %@ is in %d hour(s)"),
                appointment.providerName,
                hours
            )
        } else {
            title = NSLocalizedString("notification.appointment.reminder.soon.title", comment: "Appointment Soon")
            body = String.localizedStringWithFormat(
                NSLocalizedString("notification.appointment.reminder.soon.body", comment: "Your appointment with %@ is in %d minutes"),
                appointment.providerName,
                minutesBefore
            )
        }

        let accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("notification.appointment.accessibility", comment: "Appointment reminder: %@ with %@ in %d minutes"),
            appointment.title,
            appointment.providerName,
            minutesBefore
        )

        let request = NotificationRequest(
            id: notificationId,
            title: title,
            body: body,
            category: .appointment,
            trigger: .timeInterval(reminderTime.timeIntervalSinceNow),
            userInfo: [
                "appointmentId": appointment.id,
                "appointmentTitle": appointment.title,
                "providerName": appointment.providerName,
                "reminderMinutes": "\(minutesBefore)"
            ],
            isCritical: appointment.reminderSettings.isCritical,
            isHighPriority: true,
            accessibilityLabel: accessibilityLabel
        )

        return await notificationService.scheduleNotification(request)
    }

    private func cancelRemindersForAppointment(_ appointmentId: String) async {
        let appointment = appointments.first { $0.id == appointmentId }
        guard let appt = appointment else { return }

        let reminderIds = appt.reminderSettings.reminderTimes.map {
            "\(appointmentId)_reminder_\($0)"
        }

        await notificationService.cancelNotifications(withIds: reminderIds)

        // Also cancel pre-visit summary reminder
        await notificationService.cancelNotification(withId: "\(appointmentId)_pre_visit_summary")

        logger.info("Cancelled \(reminderIds.count) reminders for appointment: \(appointmentId)")
    }

    // MARK: - Calendar Integration

    private func addAppointmentToCalendar(_ appointment: HealthAppointment) async -> Bool {
        guard calendarAuthorizationStatus == .fullAccess else {
            logger.info("Calendar access not authorized, skipping calendar integration")
            return false
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = appointment.title
        event.startDate = appointment.dateTime
        event.endDate = appointment.dateTime.addingTimeInterval(TimeInterval(appointment.duration * 60))
        event.location = appointment.location
        event.notes = createEventNotes(for: appointment)

        // Set default calendar
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)

            // Update appointment with calendar event ID
            if let index = appointments.firstIndex(where: { $0.id == appointment.id }) {
                var updatedAppointment = appointment
                updatedAppointment.calendarEventId = event.eventIdentifier

                appointments[index] = updatedAppointment
                saveStoredData()
            }

            logger.info("Added appointment to calendar: \(appointment.id)")
            return true
        } catch {
            logger.error("Failed to add appointment to calendar: \(error.localizedDescription)")
            return false
        }
    }

    private func removeAppointmentFromCalendar(_ appointment: HealthAppointment) async {
        guard let eventId = appointment.calendarEventId,
              let event = eventStore.event(withIdentifier: eventId) else {
            return
        }

        do {
            try eventStore.remove(event, span: .thisEvent)
            logger.info("Removed appointment from calendar: \(appointment.id)")
        } catch {
            logger.error("Failed to remove appointment from calendar: \(error.localizedDescription)")
        }
    }

    private func createEventNotes(for appointment: HealthAppointment) -> String {
        var notes = "\(appointment.title)\n"
        notes += "Provider: \(appointment.providerName)\n"
        notes += "Type: \(appointment.appointmentType.displayName)\n"

        if !appointment.notes.isEmpty {
            notes += "\nNotes: \(appointment.notes)"
        }

        return notes
    }

    // MARK: - Pre-Visit Summary Preparation

    /// Schedule preparation of pre-visit health summary (REQ-080)
    private func schedulePreVisitSummaryPreparation(_ appointment: HealthAppointment) async {
        // Schedule summary preparation 24 hours before appointment
        let summaryPrepTime = appointment.dateTime.addingTimeInterval(-24 * 60 * 60)

        guard summaryPrepTime > Date() else {
            // If appointment is within 24 hours, prepare summary immediately
            await preparePreVisitSummary(appointment)
            return
        }

        let notificationId = "\(appointment.id)_pre_visit_summary"

        let title = NSLocalizedString("notification.previsit.title", comment: "Health Summary Ready")
        let body = String.localizedStringWithFormat(
            NSLocalizedString("notification.previsit.body", comment: "Your pre-visit health summary for tomorrow's appointment with %@ is ready to review"),
            appointment.providerName
        )

        let request = NotificationRequest(
            id: notificationId,
            title: title,
            body: body,
            category: .appointment,
            trigger: .timeInterval(summaryPrepTime.timeIntervalSinceNow),
            userInfo: [
                "type": "pre_visit_summary",
                "appointmentId": appointment.id
            ],
            isHighPriority: true
        )

        await notificationService.scheduleNotification(request)
    }

    /// Prepare pre-visit health summary
    private func preparePreVisitSummary(_ appointment: HealthAppointment) async {
        // This will be handled by HealthSummaryGenerator
        NotificationCenter.default.post(
            name: .preVisitSummaryRequested,
            object: nil,
            userInfo: [
                "appointmentId": appointment.id,
                "appointmentType": appointment.appointmentType.rawValue
            ]
        )

        logger.info("Requested pre-visit summary preparation for appointment: \(appointment.id)")
    }

    // MARK: - Notification Response Handlers

    private func handleAppointmentConfirmed(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let appointmentId = userInfo["appointmentId"] as? String else {
            return
        }

        await confirmAppointment(appointmentId)
    }

    private func handleAppointmentRescheduleRequest(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let appointmentId = userInfo["appointmentId"] as? String else {
            return
        }

        // Send reschedule notification
        NotificationCenter.default.post(
            name: .appointmentRescheduleUIRequested,
            object: nil,
            userInfo: ["appointmentId": appointmentId]
        )
    }

    private func sendConfirmationNotification(_ appointment: HealthAppointment) async {
        let title = NSLocalizedString("notification.appointment.confirmed.title", comment: "Appointment Confirmed")
        let body = String.localizedStringWithFormat(
            NSLocalizedString("notification.appointment.confirmed.body", comment: "Your appointment with %@ on %@ has been confirmed"),
            appointment.providerName,
            DateFormatter.localizedString(from: appointment.dateTime, dateStyle: .medium, timeStyle: .short)
        )

        let request = NotificationRequest(
            id: "\(appointment.id)_confirmation",
            title: title,
            body: body,
            category: .appointment,
            trigger: .immediate,
            userInfo: ["appointmentId": appointment.id]
        )

        await notificationService.scheduleNotification(request)
    }

    // MARK: - Data Queries

    /// Get appointments for a specific date range
    func getAppointments(from startDate: Date, to endDate: Date) -> [HealthAppointment] {
        return appointments.filter { appointment in
            appointment.dateTime >= startDate && appointment.dateTime <= endDate
        }.sorted { $0.dateTime < $1.dateTime }
    }

    /// Get next upcoming appointment
    func getNextAppointment() -> HealthAppointment? {
        let now = Date()
        return appointments
            .filter { $0.dateTime > now }
            .sorted { $0.dateTime < $1.dateTime }
            .first
    }

    /// Refresh upcoming appointments list
    private func refreshUpcomingAppointments() {
        let now = Date()
        let endOfWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now) ?? now

        upcomingAppointments = appointments
            .filter { $0.dateTime > now && $0.dateTime <= endOfWeek }
            .sorted { $0.dateTime < $1.dateTime }
    }

    /// Check for appointment conflicts
    func checkForConflicts(with newAppointment: HealthAppointment) -> [HealthAppointment] {
        let buffer: TimeInterval = 30 * 60 // 30 minutes buffer

        let newStart = newAppointment.dateTime
        let newEnd = newAppointment.dateTime.addingTimeInterval(TimeInterval(newAppointment.duration * 60))

        return appointments.filter { existing in
            existing.id != newAppointment.id &&

            let existingStart = existing.dateTime
            let existingEnd = existing.dateTime.addingTimeInterval(TimeInterval(existing.duration * 60))

            // Check for overlap with buffer
            return (newStart < existingEnd.addingTimeInterval(buffer)) &&
                   (newEnd.addingTimeInterval(buffer) > existingStart)
        }
    }
}

// MARK: - Supporting Models

/// Health appointment data model
struct HealthAppointment: Codable, Identifiable {
    let id: String
    let title: String
    let providerName: String
    let location: String
    let dateTime: Date
    let duration: Int // minutes
    let appointmentType: AppointmentType
    let notes: String
    let reminderSettings: AppointmentReminderSettings
    let isConfirmed: Bool
    var calendarEventId: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        providerName: String,
        location: String,
        dateTime: Date,
        duration: Int = 60,
        appointmentType: AppointmentType = .general,
        notes: String = "",
        reminderSettings: AppointmentReminderSettings = AppointmentReminderSettings(),
        isConfirmed: Bool = false,
        calendarEventId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.providerName = providerName
        self.location = location
        self.dateTime = dateTime
        self.duration = duration
        self.appointmentType = appointmentType
        self.notes = notes
        self.reminderSettings = reminderSettings
        self.isConfirmed = isConfirmed
        self.calendarEventId = calendarEventId
    }
}

/// Appointment types
enum AppointmentType: String, CaseIterable, Codable {
    case general = "general"
    case checkup = "checkup"
    case specialist = "specialist"
    case dental = "dental"
    case vision = "vision"
    case therapy = "therapy"
    case procedure = "procedure"
    case followUp = "follow_up"
    case emergency = "emergency"

    var displayName: String {
        switch self {
        case .general: return NSLocalizedString("appointment.type.general", comment: "General")
        case .checkup: return NSLocalizedString("appointment.type.checkup", comment: "Check-up")
        case .specialist: return NSLocalizedString("appointment.type.specialist", comment: "Specialist")
        case .dental: return NSLocalizedString("appointment.type.dental", comment: "Dental")
        case .vision: return NSLocalizedString("appointment.type.vision", comment: "Vision")
        case .therapy: return NSLocalizedString("appointment.type.therapy", comment: "Therapy")
        case .procedure: return NSLocalizedString("appointment.type.procedure", comment: "Procedure")
        case .followUp: return NSLocalizedString("appointment.type.followup", comment: "Follow-up")
        case .emergency: return NSLocalizedString("appointment.type.emergency", comment: "Emergency")
        }
    }
}

/// Appointment reminder settings
struct AppointmentReminderSettings: Codable {
    let reminderTimes: [Int] // Minutes before appointment
    let isCritical: Bool
    let includePreVisitSummary: Bool

    init(
        reminderTimes: [Int] = [1440, 120, 15], // 24 hours, 2 hours, 15 minutes
        isCritical: Bool = false,
        includePreVisitSummary: Bool = true
    ) {
        self.reminderTimes = reminderTimes
        self.isCritical = isCritical
        self.includePreVisitSummary = includePreVisitSummary
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let preVisitSummaryRequested = Notification.Name("preVisitSummaryRequested")
    static let appointmentRescheduleUIRequested = Notification.Name("appointmentRescheduleUIRequested")
}