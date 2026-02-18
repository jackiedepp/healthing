//
//  HealthDataView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import HealthKit
import os.log

struct HealthDataView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @StateObject private var accessibilityManager = AccessibilityManager.shared
    @State private var selectedCategory: HealthCategory = .vitals
    @State private var healthData: [HealthDataPoint] = []
    @State private var isLoading = false
    @State private var showingManualEntry = false
    @State private var showingFilters = false
    @State private var searchText = ""

    private let logger = Logger(subsystem: "HealthingApp", category: "HealthDataView")

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category picker
                CategoryPicker(selectedCategory: $selectedCategory)
                    .padding(.horizontal)
                    .padding(.top)

                // Health data list
                if isLoading {
                    ProgressView("Loading health data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if healthData.isEmpty {
                    EmptyHealthDataView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HealthDataList(data: healthData)
                }
            }
            .navigationTitle("Health Data")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingFilters = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityEnhanced(
                        label: "Filter health data",
                        action: .filter
                    )
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingManualEntry = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityEnhanced(
                        label: "Add new health measurement",
                        action: .addMeasurement
                    )
                    .accessibleTouchTarget()
                }
            }
            .searchable(text: $searchText, prompt: "Search health data")
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView(category: selectedCategory)
            }
        }
        .onChange(of: selectedCategory) { _, newCategory in
            Task {
                await loadHealthData(for: newCategory)
            }
        }
        .onAppear {
            Task {
                await loadHealthData(for: selectedCategory)
            }
        }
    }

    private func loadHealthData(for category: HealthCategory) async {
        isLoading = true

        do {
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate

            let observations = try await dataStore.fetchHealthObservations(
                category: category.loincCategory,
                dateRange: startDate...endDate
            )

            healthData = observations.compactMap { observation in
                HealthDataPoint(
                    id: observation.id,
                    type: category.displayName,
                    value: observation.valueQuantity?.value?.decimal?.doubleValue ?? 0,
                    unit: observation.valueQuantity?.unit?.string ?? "",
                    timestamp: observation.effectiveDateTime?.nsDate ?? Date(),
                    deviceName: observation.device?.display?.string
                )
            }.sorted { $0.timestamp > $1.timestamp }

        } catch {
            print("Failed to load health data: \(error)")
            healthData = []
        }

        isLoading = false
    }
}

// MARK: - Category Picker

struct CategoryPicker: View {
    @Binding var selectedCategory: HealthCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HealthCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct CategoryChip: View {
    let category: HealthCategory
    let isSelected: Bool
    let action: () -> Void

    @StateObject private var accessibilityManager = AccessibilityManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: accessibilityManager.accessibleSpacing(8)) {
                Image(systemName: category.icon)
                    .accessibleFont(14, style: .caption)
                    .accessibilityHidden(true)

                Text(category.displayName)
                    .accessibleFont(15, style: .subheadline, weight: .medium)
                    .lineLimit(1)
            }
            .accessiblePadding(.horizontal, 16)
            .accessiblePadding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ?
                          accessibilityManager.accessibleColor(category.color) :
                          Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .stroke(
                                accessibilityManager.highContrastColors ? Color.primary.opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .foregroundColor(
                accessibilityManager.accessibleColor(
                    isSelected ? .white : .primary
                )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityEnhanced(
            label: category.displayName,
            hint: isSelected ? "Currently selected category" : "Tap to select this category",
            traits: isSelected ? [.button, .selected] : .button
        )
        .accessibleTouchTarget()
    }
}

// MARK: - Health Data List

struct HealthDataList: View {
    let data: [HealthDataPoint]

    var body: some View {
        List {
            ForEach(groupedData, id: \.date) { group in
                Section(group.dateString) {
                    ForEach(group.points) { point in
                        HealthDataRow(dataPoint: point)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var groupedData: [HealthDataGroup] {
        let groups = Dictionary(grouping: data) { point in
            Calendar.current.startOfDay(for: point.timestamp)
        }

        return groups.map { date, points in
            HealthDataGroup(date: date, points: points.sorted { $0.timestamp > $1.timestamp })
        }.sorted { $0.date > $1.date }
    }
}

struct HealthDataRow: View {
    let dataPoint: HealthDataPoint

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(formatValue(dataPoint.value))
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(dataPoint.unit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let deviceName = dataPoint.deviceName {
                    Text(deviceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(dataPoint.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Empty State

struct EmptyHealthDataView: View {
    @StateObject private var accessibilityManager = AccessibilityManager.shared

    var body: some View {
        VStack(spacing: accessibilityManager.accessibleSpacing(20)) {
            Image(systemName: "heart.text.square")
                .accessibleFont(60, style: .largeTitle)
                .accessibleForegroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: accessibilityManager.accessibleSpacing(8)) {
                Text("No Health Data")
                    .accessibleFont(24, style: .title2, weight: .semibold)
                    .multilineTextAlignment(.center)

                Text("Connect your devices or add measurements manually to see your health data here.")
                    .accessibleFont(16, style: .body)
                    .multilineTextAlignment(.center)
                    .accessibleForegroundColor(.secondary)
                    .accessiblePadding(.horizontal, 40)
            }
            .accessibilityElement(children: .combine)
            .accessibilityEnhanced(
                label: "No health data available. Connect your devices or add measurements manually to see your health data here.",
                traits: .staticText
            )

            Button("Add Measurement") {
                // Trigger manual entry - handled by parent
            }
            .buttonStyle(.borderedProminent)
            .accessibleFont(17, style: .body, weight: .medium)
            .accessibilityEnhanced(
                label: "Add measurement",
                hint: "Double tap to add a new health measurement manually",
                action: .addMeasurement
            )
            .accessibleTouchTarget()
        }
        .accessiblePadding(.all, 40)
    }
}

// MARK: - Manual Entry View

struct ManualEntryView: View {
    let category: HealthCategory
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var dataStore: HealthDataStore
    @StateObject private var accessibilityManager = AccessibilityManager.shared

    @State private var value: String = ""
    @State private var selectedDate = Date()
    @State private var notes: String = ""
    @State private var isSaving = false

    // Enhanced validation states
    @State private var validationState: ValidationState = .valid
    @State private var validationMessage: String = ""
    @State private var showingValidationAlert = false
    @State private var hasAttemptedSave = false

    private let logger = Logger(subsystem: "HealthingApp", category: "ManualEntryView")

    var body: some View {
        NavigationView {
            Form {
                // Value input section with enhanced validation
                Section {
                    VStack(alignment: .leading, spacing: accessibilityManager.accessibleSpacing(8)) {
                        HStack {
                            TextField(
                                category.inputPrompt,
                                text: $value
                            )
                            .accessibleFont(17, style: .body)
                            .keyboardType(category.keyboardType)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: value) { _, newValue in
                                validateInput(newValue)
                            }
                            .accessibilityEnhanced(
                                label: "Enter \(category.displayName.lowercased()) value",
                                hint: "Required field. Enter a numeric value.",
                                value: value.isEmpty ? "Empty" : "\(value) \(category.unit)"
                            )

                            Text(category.unit)
                                .accessibleFont(15, style: .subheadline, weight: .medium)
                                .accessibleForegroundColor(.secondary)
                                .accessibilityHidden(true) // Included in text field accessibility
                        }

                        // Validation feedback
                        if hasAttemptedSave && validationState != .valid {
                            HStack(spacing: 6) {
                                Image(systemName: validationIcon)
                                    .accessibleFont(12, style: .caption)
                                    .accessibleForegroundColor(validationColor)

                                Text(validationMessage)
                                    .accessibleFont(12, style: .caption)
                                    .accessibleForegroundColor(validationColor)
                            }
                            .accessibilityEnhanced(
                                label: "Validation error: \(validationMessage)",
                                traits: .staticText
                            )
                        }

                        // Input guidance
                        Text(category.validationGuidance)
                            .accessibleFont(12, style: .caption)
                            .accessibleForegroundColor(.secondary)
                            .accessibilityEnhanced(
                                label: "Input guidance: \(category.validationGuidance)",
                                traits: .staticText
                            )
                    }
                } header: {
                    Text(category.displayName)
                        .accessibleFont(13, style: .caption, weight: .semibold)
                }

                // Date and time section
                Section {
                    DatePicker(
                        "Measured At",
                        selection: $selectedDate,
                        in: category.validDateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityEnhanced(
                        label: "Date and time of measurement",
                        hint: "Select when this measurement was taken"
                    )

                    // Date validation
                    if selectedDate > Date() {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .accessibleFont(12, style: .caption)
                                .accessibleForegroundColor(.orange)

                            Text("Future dates are not recommended for health measurements")
                                .accessibleFont(12, style: .caption)
                                .accessibleForegroundColor(.orange)
                        }
                    }
                } header: {
                    Text("Date & Time")
                        .accessibleFont(13, style: .caption, weight: .semibold)
                }

                // Notes section
                Section {
                    TextField(
                        "Optional notes about this measurement",
                        text: $notes,
                        axis: .vertical
                    )
                    .accessibleFont(16, style: .body)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityEnhanced(
                        label: "Notes",
                        hint: "Optional. Add any relevant context or notes about this measurement."
                    )
                } header: {
                    Text("Notes (Optional)")
                        .accessibleFont(13, style: .caption, weight: .semibold)
                }

                // Save button section for accessibility
                if accessibilityManager.prefersLargerHitTargets {
                    Section {
                        Button(action: attemptSave) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                }

                                Text(isSaving ? "Saving..." : "Save Measurement")
                                    .accessibleFont(17, style: .body, weight: .medium)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .accessiblePadding(.vertical, 12)
                        }
                        .disabled(!isValidInput || isSaving)
                        .buttonStyle(.borderedProminent)
                        .accessibilityEnhanced(
                            label: isSaving ? "Saving health measurement" : "Save health measurement",
                            hint: isValidInput ? "Double tap to save this measurement" : "Fix validation errors before saving"
                        )
                        .accessibleTouchTarget(minimumSize: 60)
                    }
                }
            }
            .navigationTitle("Add \(category.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .accessibilityEnhanced(
                        label: "Cancel",
                        hint: "Discard this measurement and return to previous screen",
                        action: .dismiss
                    )
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        attemptSave()
                    }
                    .disabled(!isValidInput || isSaving)
                    .accessibilityEnhanced(
                        label: isSaving ? "Saving..." : "Save",
                        hint: isValidInput ? "Save this health measurement" : "Fix validation errors before saving"
                    )
                }
            }
            .alert(
                "Invalid Input",
                isPresented: $showingValidationAlert
            ) {
                Button("OK") { }
            } message: {
                Text(validationMessage)
            }
        }
    }

    // MARK: - Validation Methods

    private func validateInput(_ input: String) {
        guard !input.isEmpty else {
            validationState = .empty
            validationMessage = "Please enter a value"
            return
        }

        guard let numericValue = Double(input) else {
            validationState = .invalidFormat
            validationMessage = "Please enter a valid number"
            return
        }

        let validation = category.validateValue(numericValue)
        validationState = validation.state
        validationMessage = validation.message
    }

    private func attemptSave() {
        hasAttemptedSave = true
        validateInput(value)

        guard validationState == .valid else {
            showingValidationAlert = true
            accessibilityManager.announceHealthInsight(
                HealthInsight(
                    id: "validation-error",
                    title: "Input Error",
                    message: validationMessage,
                    category: .vital,
                    priority: .medium,
                    timestamp: Date()
                )
            )
            return
        }

        saveHealthData()
    }

    private func saveHealthData() {
        guard let doubleValue = Double(value) else { return }
        logger.info("Saving health data: \(category.displayName) = \(doubleValue) \(category.unit)")

        isSaving = true

        Task {
            do {
                // Create FHIR observation
                let observation = createObservation(
                    value: doubleValue,
                    unit: category.unit,
                    date: selectedDate,
                    category: category
                )

                // Store in local database
                try await dataStore.storeHealthObservation(observation)

                await MainActor.run {
                    logger.info("Health data saved successfully")

                    // Announce success for accessibility
                    accessibilityManager.announceHealthInsight(
                        HealthInsight(
                            id: "save-success",
                            title: "Measurement Saved",
                            message: "\(category.displayName) measurement of \(doubleValue) \(category.unit) has been saved",
                            category: .vital,
                            priority: .medium,
                            timestamp: Date()
                        )
                    )

                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                logger.error("Failed to save health data: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    validationState = .saveError
                    validationMessage = "Failed to save measurement. Please try again."
                    showingValidationAlert = true
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var isValidInput: Bool {
        return validationState == .valid && !value.isEmpty
    }

    private var validationIcon: String {
        switch validationState {
        case .valid: return "checkmark.circle.fill"
        case .empty: return "exclamationmark.circle.fill"
        case .invalidFormat: return "xmark.circle.fill"
        case .outOfRange: return "exclamationmark.triangle.fill"
        case .saveError: return "xmark.circle.fill"
        }
    }

    private var validationColor: Color {
        switch validationState {
        case .valid: return accessibilityManager.accessibleColor(.green)
        case .empty: return accessibilityManager.accessibleColor(.orange)
        case .invalidFormat: return accessibilityManager.accessibleColor(.red)
        case .outOfRange: return accessibilityManager.accessibleColor(.orange)
        case .saveError: return accessibilityManager.accessibleColor(.red)
        }
    }

    private func createObservation(value: Double, unit: String, date: Date, category: HealthCategory) -> HealthingObservation {
        let code = CodeableConcept()
        let coding = Coding()
        coding.system = FHIRString("http://loinc.org")
        coding.code = FHIRString(category.loincCode)
        coding.display = FHIRString(category.displayName)
        code.coding = [coding]

        let valueQuantity = Quantity()
        valueQuantity.value = FHIRDecimal(value)
        valueQuantity.unit = FHIRString(unit)

        let patientReference = Reference()
        patientReference.reference = FHIRString("Patient/current-user")

        let observationCategory = CodeableConcept()
        let categoryCoding = Coding()
        categoryCoding.system = FHIRString("http://terminology.hl7.org/CodeSystem/observation-category")
        categoryCoding.code = FHIRString("vital-signs")
        observationCategory.coding = [categoryCoding]

        return HealthingObservation(
            id: UUID().uuidString,
            status: .final,
            code: code,
            subject: patientReference,
            effectiveDateTime: DateTime(date),
            valueQuantity: valueQuantity,
            valueCodeableConcept: nil,
            device: nil,
            component: nil,
            category: [observationCategory]
        )
    }
}

// MARK: - Supporting Types

enum ValidationState: Equatable {
    case valid
    case empty
    case invalidFormat
    case outOfRange
    case saveError
}

struct ValidationResult {
    let state: ValidationState
    let message: String
}

enum HealthCategory: CaseIterable {
    case vitals, activity, body, respiratory

    var displayName: String {
        switch self {
        case .vitals: return NSLocalizedString("Heart Rate", comment: "Heart rate category")
        case .activity: return NSLocalizedString("Daily Steps", comment: "Activity category")
        case .body: return NSLocalizedString("Weight", comment: "Body measurement category")
        case .respiratory: return NSLocalizedString("Respiratory Rate", comment: "Respiratory category")
        }
    }

    var icon: String {
        switch self {
        case .vitals: return "heart.fill"
        case .activity: return "figure.walk"
        case .body: return "scalemass.fill"
        case .respiratory: return "lungs.fill"
        }
    }

    var color: Color {
        switch self {
        case .vitals: return .red
        case .activity: return .blue
        case .body: return .green
        case .respiratory: return .purple
        }
    }

    var unit: String {
        switch self {
        case .vitals: return NSLocalizedString("bpm", comment: "Beats per minute unit")
        case .activity: return NSLocalizedString("steps", comment: "Steps unit")
        case .body: return NSLocalizedString("kg", comment: "Kilograms unit")
        case .respiratory: return NSLocalizedString("breaths/min", comment: "Breaths per minute unit")
        }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .vitals, .respiratory: return .numberPad
        case .activity: return .numberPad
        case .body: return .decimalPad
        }
    }

    var inputPrompt: String {
        switch self {
        case .vitals: return NSLocalizedString("Enter heart rate", comment: "Heart rate input prompt")
        case .activity: return NSLocalizedString("Enter step count", comment: "Steps input prompt")
        case .body: return NSLocalizedString("Enter weight", comment: "Weight input prompt")
        case .respiratory: return NSLocalizedString("Enter respiratory rate", comment: "Respiratory rate input prompt")
        }
    }

    var validationGuidance: String {
        switch self {
        case .vitals:
            return NSLocalizedString("Normal range: 60-100 bpm for adults at rest", comment: "Heart rate guidance")
        case .activity:
            return NSLocalizedString("Daily step count (0 to 100,000 steps)", comment: "Steps guidance")
        case .body:
            return NSLocalizedString("Weight in kilograms (20-300 kg)", comment: "Weight guidance")
        case .respiratory:
            return NSLocalizedString("Normal range: 12-20 breaths per minute for adults", comment: "Respiratory guidance")
        }
    }

    var validDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return oneYearAgo...tomorrow
    }

    var loincCode: String {
        switch self {
        case .vitals: return "8867-4"
        case .activity: return "55423-8"
        case .body: return "29463-7"
        case .respiratory: return "9279-1"
        }
    }

    var loincCategory: String {
        switch self {
        case .vitals: return "vital-signs"
        case .activity: return "activity"
        case .body: return "body-measurement"
        case .respiratory: return "vital-signs"
        }
    }

    // Enhanced validation with specific ranges for each category
    func validateValue(_ value: Double) -> ValidationResult {
        switch self {
        case .vitals:
            return validateHeartRate(value)
        case .activity:
            return validateSteps(value)
        case .body:
            return validateWeight(value)
        case .respiratory:
            return validateRespiratoryRate(value)
        }
    }

    private func validateHeartRate(_ value: Double) -> ValidationResult {
        if value < 30 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Heart rate seems unusually low. Please verify the value.", comment: "Low heart rate validation")
            )
        } else if value > 220 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Heart rate seems unusually high. Please verify the value.", comment: "High heart rate validation")
            )
        } else if value < 50 || value > 120 {
            return ValidationResult(
                state: .valid,
                message: NSLocalizedString("This value is outside the typical resting range but may be normal for you.", comment: "Heart rate warning")
            )
        } else {
            return ValidationResult(
                state: .valid,
                message: NSLocalizedString("Heart rate is within normal range.", comment: "Normal heart rate")
            )
        }
    }

    private func validateSteps(_ value: Double) -> ValidationResult {
        if value < 0 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Step count cannot be negative.", comment: "Negative steps validation")
            )
        } else if value > 100000 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Step count seems unusually high. Please verify the value.", comment: "High steps validation")
            )
        } else {
            return ValidationResult(
                state: .valid,
                message: NSLocalizedString("Step count looks good.", comment: "Valid steps")
            )
        }
    }

    private func validateWeight(_ value: Double) -> ValidationResult {
        if value < 20 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Weight seems unusually low. Please verify the value.", comment: "Low weight validation")
            )
        } else if value > 300 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Weight seems unusually high. Please verify the value.", comment: "High weight validation")
            )
        } else {
            return ValidationResult(
                state: .valid,
                message: NSLocalizedString("Weight is within acceptable range.", comment: "Valid weight")
            )
        }
    }

    private func validateRespiratoryRate(_ value: Double) -> ValidationResult {
        if value < 6 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Respiratory rate seems unusually low. Please verify the value.", comment: "Low respiratory rate validation")
            )
        } else if value > 40 {
            return ValidationResult(
                state: .outOfRange,
                message: NSLocalizedString("Respiratory rate seems unusually high. Please verify the value.", comment: "High respiratory rate validation")
            )
        } else if value < 10 || value > 24 {
            return ValidationResult(
                state: .valid,
                message: NSLocalizedString("This respiratory rate is outside typical range but may be normal for you.", comment: "Respiratory rate warning")
            )
        } else {
            return ValidationResult(
                state: .valid,
                message: NSLocalizedString("Respiratory rate is within normal range.", comment: "Normal respiratory rate")
            )
        }
    }
}

struct HealthDataPoint: Identifiable {
    let id: String
    let type: String
    let value: Double
    let unit: String
    let timestamp: Date
    let deviceName: String?
}

struct HealthDataGroup {
    let date: Date
    let points: [HealthDataPoint]

    var dateString: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

#Preview {
    HealthDataView()
        .environmentObject(HealthDataStore.shared)
}