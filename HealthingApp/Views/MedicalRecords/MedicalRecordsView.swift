//
//  MedicalRecordsView.swift
//  HealthingApp
//
//  Created on 2026-01-26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VisionKit
import ModelsR4

struct MedicalRecordsView: View {
    @EnvironmentObject private var dataStore: HealthDataStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var ocrService = OCRService.shared
    @StateObject private var documentUploadManager = DocumentUploadManager.shared
    @StateObject private var documentSearchEngine = DocumentSearchEngine.shared
    @StateObject private var timelineManager = MedicalTimelineManager.shared
    @StateObject private var documentClassifier = DocumentClassifier.shared

    @State private var documents: [MedicalDocument] = []
    @State private var isLoading = false
    @State private var showingDocumentPicker = false
    @State private var showingImagePicker = false
    @State private var showingDocumentCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingOCRResults = false
    @State private var currentOCRResult: OCRResult?
    @State private var processingAlert: ProcessingAlert?

    // New Phase 2C properties
    @State private var searchText = ""
    @State private var selectedView: RecordsViewMode = .list
    @State private var showingSearchFilters = false
    @State private var searchFilters = SearchFilters()
    @State private var showingDocumentDetails = false
    @State private var selectedDocument: MedicalDocument?
    @State private var searchResults: [DocumentSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Header
                searchHeaderView

                // View Mode Picker
                viewModePickerView

                // Content Area
                if isLoading || ocrService.isProcessing || documentUploadManager.isUploading {
                    processingView
                } else if documents.isEmpty && searchResults.isEmpty {
                    EmptyRecordsView {
                        showDocumentOptions()
                    }
                } else {
                    contentView
                }
            }
            .navigationTitle("medical_records".localized)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSearchFilters = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("add".localized) {
                        Button("take_photo".localized) {
                            showingDocumentCamera = true
                        }

                        Button("choose_from_photos".localized) {
                            showingDocumentPicker = true
                        }

                        Button("import_document".localized) {
                            showDocumentPicker()
                        }
                    }
                }
            }
            .photosPicker(
                isPresented: $showingDocumentPicker,
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .images
            )
            .fullScreenCover(isPresented: $showingDocumentCamera) {
                DocumentCameraView { images in
                    processScannedImages(images)
                }
            }
            .sheet(isPresented: $showingOCRResults) {
                OCRResultsView(result: currentOCRResult)
            }
            .alert(item: $processingAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("ok".localized))
                )
            }
            .sheet(isPresented: $showingSearchFilters) {
                DocumentSearchFiltersView(filters: $searchFilters)
            }
            .sheet(isPresented: $showingDocumentDetails) {
                if let selectedDocument = selectedDocument {
                    DocumentDetailsView(document: selectedDocument)
                }
            }
        }
        .onChange(of: selectedPhotos) { _, newPhotos in
            processSelectedPhotos(newPhotos)
        }
        .onChange(of: searchText) { _, newText in
            Task {
                await performDocumentSearch(query: newText)
            }
        }
        .onAppear {
            Task {
                await loadMedicalRecords()
                await loadTimelineEvents()
            }
        }
    }

    // MARK: - View Components

    private var searchHeaderView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search medical documents...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)

            // Search suggestions
            if !documentSearchEngine.searchSuggestions.isEmpty && !searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(documentSearchEngine.searchSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                searchText = suggestion
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var viewModePickerView: some View {
        Picker("View Mode", selection: $selectedView) {
            Text("List").tag(RecordsViewMode.list)
            Text("Timeline").tag(RecordsViewMode.timeline)
            Text("Search").tag(RecordsViewMode.search)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            if ocrService.isProcessing {
                Text("processing_document".localized)
                    .font(.headline)

                ProgressView(value: ocrService.processingProgress)
                    .frame(width: 200)
            } else if documentUploadManager.isUploading {
                Text("Uploading Document")
                    .font(.headline)

                ProgressView(value: documentUploadManager.uploadProgress)
                    .frame(width: 200)

                Text("Step: \(documentUploadManager.currentProcessingStep.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("loading".localized)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        Group {
            switch selectedView {
            case .list:
                EnhancedMedicalRecordsList(
                    documents: documents,
                    searchResults: searchResults,
                    isSearchActive: !searchText.isEmpty,
                    onDocumentTapped: { document in
                        selectedDocument = document
                        showingDocumentDetails = true
                    }
                )
            case .timeline:
                MedicalTimelineView(timelineManager: timelineManager)
            case .search:
                DocumentSearchResultsView(
                    searchResults: searchResults,
                    isSearching: isSearching,
                    onDocumentTapped: { result in
                        if let document = documents.first(where: { $0.id == result.documentId }) {
                            selectedDocument = document
                            showingDocumentDetails = true
                        }
                    }
                )
            }
        }
    }

    private func showDocumentOptions() {
        showingDocumentPicker = true
    }

    private func loadMedicalRecords() async {
        isLoading = true

        // Placeholder for loading medical records from data store
        // In a real implementation, this would fetch from the HealthDataStore

        // Simulate loading
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Mock data for demonstration
        documents = [
            MedicalDocument(
                id: "1",
                title: "Lab Results - Blood Panel",
                category: "Lab Results",
                date: Date().addingTimeInterval(-86400 * 7),
                fileType: "PDF",
                fileSize: "2.3 MB",
                thumbnailUrl: nil
            ),
            MedicalDocument(
                id: "2",
                title: "Prescription - Medication List",
                category: "Prescription",
                date: Date().addingTimeInterval(-86400 * 14),
                fileType: "Image",
                fileSize: "1.1 MB",
                thumbnailUrl: nil
            )
        ]

        isLoading = false
    }

    private func processSelectedPhotos(_ photos: [PhotosPickerItem]) {
        Task {
            for photo in photos {
                if let data = try? await photo.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await processImageWithOCR(image, source: "photos")
                }
            }
            selectedPhotos = []
        }
    }

    private func processScannedImages(_ images: [UIImage]) {
        Task {
            for image in images {
                await processImageWithOCR(image, source: "scanner")
            }
        }
    }

    private func processImageWithOCR(_ image: UIImage, source: String) async {
        do {
            // Get supported languages for OCR based on current app language
            let supportedLanguages = localizationManager.currentLanguage.ocrLanguageCodes

            // Process image with OCR
            let ocrResult = try await ocrService.processImage(image, supportedLanguages: supportedLanguages)

            // Show OCR results to user
            await MainActor.run {
                currentOCRResult = ocrResult
                showingOCRResults = true
            }

            // Create document with extracted information
            await createDocumentFromOCRResult(ocrResult, originalImage: image, source: source)

        } catch {
            await MainActor.run {
                processingAlert = ProcessingAlert(
                    title: "ocr_processing_failed".localized,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func createDocumentFromOCRResult(_ ocrResult: OCRResult, originalImage: UIImage, source: String) async {
        do {
            // Create document metadata
            let metadata = DocumentMetadata(
                title: generateDocumentTitle(from: ocrResult),
                documentType: inferDocumentType(from: ocrResult.medicalInformation),
                providerName: extractProviderName(from: ocrResult.fullText),
                patientName: nil, // Could be extracted from OCR if needed
                documentDate: extractDocumentDate(from: ocrResult),
                notes: "Document imported from \(source) with OCR processing",
                originalFilename: "\(UUID().uuidString).jpg"
            )

            // Upload document using the enhanced DocumentUploadManager
            let medicalDocument = try await documentUploadManager.uploadDocument(
                from: originalImage,
                metadata: metadata
            )

            // Index document for search
            try await documentSearchEngine.indexDocument(medicalDocument)

            // Add to timeline
            try await timelineManager.addDocumentToTimeline(medicalDocument)

            // Refresh the lists
            await loadMedicalRecords()
            await loadTimelineEvents()

        } catch {
            await MainActor.run {
                processingAlert = ProcessingAlert(
                    title: "document_upload_failed".localized,
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Enhanced Document Processing

    private func generateDocumentTitle(from ocrResult: OCRResult) -> String {
        let medicalInfo = ocrResult.medicalInformation

        if !medicalInfo.medications.isEmpty {
            return "Prescription - \(medicalInfo.medications.first ?? "Medication List")"
        } else if !medicalInfo.vitals.isEmpty {
            return "Health Report - Vital Signs"
        } else if !medicalInfo.diagnoses.isEmpty {
            return "Medical Report - \(medicalInfo.diagnoses.first ?? "Diagnosis")"
        } else if !medicalInfo.dates.isEmpty {
            return "Medical Document - \(medicalInfo.dates.first ?? "")"
        } else {
            return "Medical Document - \(Date().formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func inferDocumentType(from medicalInfo: MedicalInformation) -> DocumentType? {
        if !medicalInfo.medications.isEmpty {
            return .prescription
        } else if !medicalInfo.vitals.isEmpty {
            return .diagnostic
        } else if !medicalInfo.diagnoses.isEmpty {
            return .consultation
        } else {
            return .other
        }
    }

    private func extractProviderName(from text: String) -> String? {
        // Simple pattern matching for provider names
        let providerPatterns = [
            #"(?i)(Dr\.?\s+[A-Z][a-z]+\s+[A-Z][a-z]+)"#,
            #"(?i)([A-Z][a-z]+\s+Medical\s+Center)"#,
            #"(?i)([A-Z][a-z]+\s+Hospital)"#,
            #"(?i)([A-Z][a-z]+\s+Clinic)"#
        ]

        for pattern in providerPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))

                if let match = matches.first,
                   let range = Range(match.range, in: text) {
                    return String(text[range])
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func extractDocumentDate(from ocrResult: OCRResult) -> Date? {
        guard let dateString = ocrResult.medicalInformation.dates.first else { return nil }

        let dateFormatter = DateFormatter()
        let dateFormats = [
            "MM/dd/yyyy", "dd/MM/yyyy", "yyyy-MM-dd", "MM-dd-yyyy",
            "MMMM d, yyyy", "d MMMM yyyy", "MMM d, yyyy"
        ]

        for format in dateFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    // MARK: - Search Functionality

    private func performDocumentSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        do {
            let results = try await documentSearchEngine.searchDocuments(
                query: query,
                filters: searchFilters,
                sortBy: .relevance,
                limit: 50
            )

            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }

            // Generate search suggestions
            let suggestions = await documentSearchEngine.generateSearchSuggestions(for: query)
            await MainActor.run {
                self.documentSearchEngine.searchSuggestions = suggestions
            }

        } catch {
            await MainActor.run {
                self.isSearching = false
                self.processingAlert = ProcessingAlert(
                    title: "Search Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func loadTimelineEvents() async {
        timelineManager.loadTimelineEvents()
    }

    private func classifyDocumentType(from medicalInfo: MedicalInformation) -> CodeableConcept {
        let type = CodeableConcept()
        let coding = Coding()
        coding.system = FHIRString("http://loinc.org")

        // Classify based on extracted medical information
        if !medicalInfo.medications.isEmpty {
            coding.code = FHIRString("57833-6")
            coding.display = FHIRString("Prescription record")
        } else if !medicalInfo.vitals.isEmpty {
            coding.code = FHIRString("33747-0")
            coding.display = FHIRString("General examination")
        } else if !medicalInfo.diagnoses.isEmpty {
            coding.code = FHIRString("18842-5")
            coding.display = FHIRString("Discharge summary")
        } else {
            coding.code = FHIRString("11502-2")
            coding.display = FHIRString("Laboratory report")
        }

        type.coding = [coding]
        return type
    }

    private func createDocumentDescription(from ocrResult: OCRResult, source: String) -> String {
        var description = "document imported from \(source)".localized

        if !ocrResult.detectedLanguages.isEmpty {
            let languages = ocrResult.detectedLanguages.joined(separator: ", ")
            description += "\n" + "multiple_languages_detected".localized + ": \(languages)"
        }

        let medicalInfo = ocrResult.medicalInformation
        var findings: [String] = []

        if !medicalInfo.medications.isEmpty {
            findings.append("medications_found".localized + ": \(medicalInfo.medications.count)")
        }
        if !medicalInfo.diagnoses.isEmpty {
            findings.append("diagnoses_found".localized + ": \(medicalInfo.diagnoses.count)")
        }
        if !medicalInfo.vitals.isEmpty {
            findings.append("vitals_found".localized + ": \(medicalInfo.vitals.count)")
        }
        if !medicalInfo.dates.isEmpty {
            findings.append("dates_extracted".localized + ": \(medicalInfo.dates.count)")
        }

        if !findings.isEmpty {
            description += "\n" + findings.joined(separator: "\n")
        }

        return description
    }

    private func showDocumentPicker() {
        // Implementation for PDF document picker
        // This would show a document picker for PDF files
    }

    private func createDocumentType() -> CodeableConcept {
        let type = CodeableConcept()
        let coding = Coding()
        coding.system = FHIRString("http://loinc.org")
        coding.code = FHIRString("11502-2")
        coding.display = FHIRString("Laboratory report")
        type.coding = [coding]
        return type
    }

    private func createDocumentCategory() -> CodeableConcept {
        let category = CodeableConcept()
        let coding = Coding()
        coding.system = FHIRString("http://hl7.org/fhir/us/core/CodeSystem/us-core-documentreference-category")
        coding.code = FHIRString("clinical-note")
        coding.display = FHIRString("Clinical Note")
        category.coding = [coding]
        return category
    }

    private func createPatientReference() -> Reference {
        let reference = Reference()
        reference.reference = FHIRString("Patient/current-user")
        return reference
    }

    private func createDocumentContent(url: URL) -> DocumentReferenceContent {
        let content = DocumentReferenceContent()
        let attachment = Attachment()
        attachment.url = FHIRString(url.absoluteString)
        attachment.contentType = FHIRString("image/jpeg")
        content.attachment = attachment
        return content
    }
}

// MARK: - Medical Records List

struct MedicalRecordsList: View {
    let documents: [MedicalDocument]

    var body: some View {
        List {
            ForEach(groupedDocuments, id: \.category) { group in
                Section(group.category) {
                    ForEach(group.documents) { document in
                        MedicalRecordRow(document: document)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var groupedDocuments: [DocumentGroup] {
        let groups = Dictionary(grouping: documents) { $0.category }
        return groups.map { category, docs in
            DocumentGroup(category: category, documents: docs.sorted { $0.date > $1.date })
        }.sorted { $0.category < $1.category }
    }
}

struct MedicalRecordRow: View {
    let document: MedicalDocument

    var body: some View {
        HStack {
            // Document type icon
            Image(systemName: documentIcon)
                .foregroundColor(documentColor)
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack {
                    Text(document.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(document.fileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // Open document viewer
        }
    }

    private var documentIcon: String {
        switch document.fileType.lowercased() {
        case "pdf":
            return "doc.text.fill"
        case "image", "jpg", "png":
            return "photo.fill"
        default:
            return "doc.fill"
        }
    }

    private var documentColor: Color {
        switch document.category.lowercased() {
        case "lab results":
            return .blue
        case "prescription":
            return .green
        case "imaging":
            return .purple
        default:
            return .gray
        }
    }
}

// MARK: - Empty State

struct EmptyRecordsView: View {
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.below.ecg.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Text("No Medical Records")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Keep all your medical documents organized and secure in one place.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 12) {
                Button(action: addAction) {
                    Label("Add Document", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Scan prescriptions, lab results, and reports")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "shield.fill")
                        Text("All documents encrypted and stored locally")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
        }
        .padding()
    }
}

// MARK: - Document Camera View

struct DocumentCameraView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraView

        init(_ parent: DocumentCameraView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []

            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                images.append(image)
            }

            parent.completion(images)
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Supporting Types

struct MedicalDocument: Identifiable {
    let id: String
    let title: String
    let category: String
    let date: Date
    let fileType: String
    let fileSize: String
    let thumbnailUrl: String?
}

struct DocumentGroup {
    let category: String
    let documents: [MedicalDocument]
}

// MARK: - OCR Results View

struct OCRResultsView: View {
    let result: OCRResult?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            if let result = result {
                List {
                    Section("text_recognition_complete".localized) {
                        ScrollView {
                            Text(result.fullText)
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(height: 200)
                    }

                    if !result.detectedLanguages.isEmpty {
                        Section("multiple_languages_detected".localized) {
                            ForEach(result.detectedLanguages, id: \.self) { language in
                                HStack {
                                    Text(getLanguageFlag(for: language))
                                    Text(getLanguageName(for: language))
                                }
                            }
                        }
                    }

                    let medicalInfo = result.medicalInformation

                    if !medicalInfo.medications.isEmpty {
                        Section("medications_found".localized) {
                            ForEach(medicalInfo.medications, id: \.self) { medication in
                                Text(medication)
                            }
                        }
                    }

                    if !medicalInfo.diagnoses.isEmpty {
                        Section("diagnoses_found".localized) {
                            ForEach(medicalInfo.diagnoses, id: \.self) { diagnosis in
                                Text(diagnosis)
                            }
                        }
                    }

                    if !medicalInfo.vitals.isEmpty {
                        Section("vitals_found".localized) {
                            ForEach(medicalInfo.vitals, id: \.self) { vital in
                                Text(vital)
                            }
                        }
                    }

                    if !medicalInfo.dates.isEmpty {
                        Section("dates_extracted".localized) {
                            ForEach(medicalInfo.dates, id: \.self) { date in
                                Text(date)
                            }
                        }
                    }
                }
            } else {
                Text("no_text_detected".localized)
            }
        }
        .navigationTitle("medical_terms_found".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("done".localized) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    private func getLanguageFlag(for languageCode: String) -> String {
        switch languageCode {
        case "en-US", "en":
            return "🇺🇸"
        case "zh-Hans":
            return "🇨🇳"
        case "zh-Hant":
            return "🇹🇼"
        default:
            return "🌐"
        }
    }

    private func getLanguageName(for languageCode: String) -> String {
        switch languageCode {
        case "en-US", "en":
            return "english".localized
        case "zh-Hans":
            return "simplified_chinese".localized
        case "zh-Hant":
            return "traditional_chinese".localized
        default:
            return languageCode
        }
    }
}

// MARK: - Supporting Types

struct ProcessingAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum DocumentError: LocalizedError {
    case imageProcessingFailed
    case ocrFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return "ocr_processing_failed".localized
        case .ocrFailed:
            return "ocr_failed".localized
        case .unsupportedFormat:
            return "error_occurred".localized
        }
    }
}

enum RecordsViewMode {
    case list
    case timeline
    case search
}

// MARK: - Enhanced Medical Records List

struct EnhancedMedicalRecordsList: View {
    let documents: [MedicalDocument]
    let searchResults: [DocumentSearchResult]
    let isSearchActive: Bool
    let onDocumentTapped: (MedicalDocument) -> Void

    var body: some View {
        List {
            if isSearchActive {
                // Show search results
                ForEach(searchResults, id: \.documentId) { result in
                    SearchResultRow(result: result) {
                        if let document = documents.first(where: { $0.id == result.documentId }) {
                            onDocumentTapped(document)
                        }
                    }
                }
            } else {
                // Show grouped documents
                ForEach(groupedDocuments, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.documents) { document in
                            EnhancedMedicalRecordRow(document: document) {
                                onDocumentTapped(document)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var groupedDocuments: [DocumentGroup] {
        let groups = Dictionary(grouping: documents) { $0.category }
        return groups.map { category, docs in
            DocumentGroup(category: category, documents: docs.sorted { $0.date > $1.date })
        }.sorted { $0.category < $1.category }
    }
}

struct EnhancedMedicalRecordRow: View {
    let document: MedicalDocument
    let onTap: () -> Void

    var body: some View {
        HStack {
            // Document type icon
            Image(systemName: documentIcon)
                .foregroundColor(documentColor)
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .fontWeight(.medium)
                    .lineLimit(2)

                // Classification results
                if let classificationResult = document.classificationResult {
                    Text(classificationResult.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                HStack {
                    Text(document.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let ocrConfidence = document.ocrConfidence, ocrConfidence > 0 {
                        Text("OCR: \(Int(ocrConfidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(document.fileSize.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if document.isIndexed {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var documentIcon: String {
        switch document.fileType.lowercased() {
        case "pdf":
            return "doc.text.fill"
        case "image", "jpg", "png":
            return "photo.fill"
        default:
            return "doc.fill"
        }
    }

    private var documentColor: Color {
        switch document.category.lowercased() {
        case "lab results":
            return .blue
        case "prescription":
            return .green
        case "imaging":
            return .purple
        default:
            return .gray
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: DocumentSearchResult
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(result.relevanceScore * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack {
                if let documentType = result.documentType {
                    Text(documentType.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let documentDate = result.documentDate {
                    Text(documentDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(result.searchSource.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Medical Timeline View

struct MedicalTimelineView: View {
    @ObservedObject var timelineManager: MedicalTimelineManager

    var body: some View {
        VStack {
            // Timeline range picker
            Picker("Time Range", selection: $timelineManager.selectedTimelineRange) {
                ForEach(TimelineRange.allCases, id: \.self) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            if timelineManager.isLoadingTimeline {
                ProgressView("Loading timeline...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if timelineManager.timelineGroupings.isEmpty {
                Text("No timeline events found")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(timelineManager.timelineGroupings, id: \.id) { group in
                        Section {
                            ForEach(group.events, id: \.id) { event in
                                TimelineEventRow(event: event)
                            }
                        } header: {
                            TimelineGroupHeader(group: group)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .onAppear {
            timelineManager.loadTimelineEvents()
        }
    }
}

struct TimelineEventRow: View {
    let event: TimelineEvent

    var body: some View {
        HStack {
            // Event icon
            Image(systemName: eventIcon)
                .foregroundColor(event.severity.color == "red" ? .red :
                               event.severity.color == "orange" ? .orange :
                               event.severity.color == "yellow" ? .yellow : .green)
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(event.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                HStack {
                    Text(event.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(event.severity.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severityColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var eventIcon: String {
        switch event.eventType {
        case .document:
            return "doc.text.fill"
        case .healthMetric:
            return "heart.fill"
        case .appointment:
            return "calendar.circle.fill"
        case .medication:
            return "pill.fill"
        case .emergency:
            return "exclamationmark.triangle.fill"
        }
    }

    private var severityColor: Color {
        switch event.severity {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

struct TimelineGroupHeader: View {
    let group: TimelineGroup

    var body: some View {
        HStack {
            Text(group.title)
                .font(.headline)

            Spacer()

            Text(group.summary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Document Search Results View

struct DocumentSearchResultsView: View {
    let searchResults: [DocumentSearchResult]
    let isSearching: Bool
    let onDocumentTapped: (DocumentSearchResult) -> Void

    var body: some View {
        VStack {
            if isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            if searchResults.isEmpty && !isSearching {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text("No search results found")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Try different keywords or check your search filters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(searchResults, id: \.documentId) { result in
                        SearchResultRow(result: result) {
                            onDocumentTapped(result)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
    }
}

// MARK: - Document Search Filters View

struct DocumentSearchFiltersView: View {
    @Binding var filters: SearchFilters
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section("Document Types") {
                    ForEach(DocumentType.allCases, id: \.self) { type in
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            if filters.documentTypes?.contains(type.rawValue) ?? false {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleDocumentType(type)
                        }
                    }
                }

                Section("Date Range") {
                    // Date range picker implementation
                    Text("Last 30 days") // Placeholder
                }

                Section("Minimum Confidence") {
                    Slider(
                        value: Binding(
                            get: { filters.minConfidence ?? 0.0 },
                            set: { filters.minConfidence = $0 }
                        ),
                        in: 0.0...1.0
                    )
                    Text("\(Int((filters.minConfidence ?? 0.0) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Search Filters")
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

    private func toggleDocumentType(_ type: DocumentType) {
        if filters.documentTypes == nil {
            filters.documentTypes = []
        }

        if filters.documentTypes!.contains(type.rawValue) {
            filters.documentTypes!.removeAll { $0 == type.rawValue }
        } else {
            filters.documentTypes!.append(type.rawValue)
        }
    }
}

// MARK: - Document Details View

struct DocumentDetailsView: View {
    let document: MedicalDocument
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Document header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title ?? "Medical Document")
                            .font(.title)
                            .fontWeight(.bold)

                        if let documentType = document.documentType {
                            Text(DocumentType(rawValue: documentType)?.displayName ?? documentType)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Document metadata
                    VStack(alignment: .leading, spacing: 8) {
                        if let uploadDate = document.uploadDate {
                            DetailRow(title: "Upload Date", value: uploadDate.formatted())
                        }

                        if let documentDate = document.documentDate {
                            DetailRow(title: "Document Date", value: documentDate.formatted())
                        }

                        if let providerName = document.providerName {
                            DetailRow(title: "Provider", value: providerName)
                        }

                        DetailRow(title: "File Size", value: "\(document.fileSize) bytes")

                        if let ocrConfidence = document.ocrConfidence, ocrConfidence > 0 {
                            DetailRow(title: "OCR Confidence", value: "\(Int(ocrConfidence * 100))%")
                        }

                        if let classificationResult = document.classificationResult {
                            DetailRow(title: "Classification", value: classificationResult)
                        }
                    }

                    // Extracted text
                    if let extractedText = document.extractedText, !extractedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extracted Text")
                                .font(.headline)

                            Text(extractedText)
                                .font(.body)
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Notes
                    if let notes = document.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)

                            Text(notes)
                                .font(.body)
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Document Details")
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

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

// MARK: - Extensions

extension SearchSource {
    var displayName: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .database: return "Database"
        case .combined: return "Combined"
        }
    }
}

#Preview {
    MedicalRecordsView()
        .environmentObject(HealthDataStore.shared)
        .environmentObject(LocalizationManager.shared)
}
