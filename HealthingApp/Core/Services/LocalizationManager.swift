//
//  LocalizationManager.swift
//  HealthingApp
//
//  Created on 2026-01-27.
//

import Foundation
import SwiftUI

/// Localization manager for handling multiple languages and dynamic language switching
class LocalizationManager: ObservableObject {

    // MARK: - Singleton
    static let shared = LocalizationManager()

    // MARK: - Published Properties
    @Published var currentLanguage: SupportedLanguage = .system {
        didSet {
            saveLanguagePreference()
            updateCurrentBundle()
        }
    }

    // MARK: - Private Properties
    private var currentBundle: Bundle = Bundle.main
    private let userDefaults = UserDefaults.standard
    private let languageKey = "selected_language"

    // MARK: - Initialization
    private init() {
        loadLanguagePreference()
        updateCurrentBundle()
    }

    // MARK: - Public Methods

    /// Get localized string for the given key
    func localizedString(for key: String, comment: String = "") -> String {
        return NSLocalizedString(key, bundle: currentBundle, comment: comment)
    }

    /// Get localized string with format arguments
    func localizedString(for key: String, arguments: CVarArg...) -> String {
        let format = localizedString(for: key)
        return String(format: format, arguments: arguments)
    }

    /// Change the app language
    func setLanguage(_ language: SupportedLanguage) {
        currentLanguage = language
    }

    /// Get available languages
    func getAvailableLanguages() -> [SupportedLanguage] {
        return SupportedLanguage.allCases
    }

    /// Check if a language is RTL (Right-to-Left)
    func isRTL(for language: SupportedLanguage) -> Bool {
        let locale = Locale(identifier: language.localeIdentifier)
        return Locale.characterDirection(forLanguage: locale.languageCode ?? "en") == .rightToLeft
    }

    /// Get the current locale
    var currentLocale: Locale {
        return Locale(identifier: currentLanguage.localeIdentifier)
    }

    // MARK: - Private Methods

    private func loadLanguagePreference() {
        guard let languageCode = userDefaults.string(forKey: languageKey),
              let language = SupportedLanguage(rawValue: languageCode) else {
            currentLanguage = .system
            return
        }
        currentLanguage = language
    }

    private func saveLanguagePreference() {
        userDefaults.set(currentLanguage.rawValue, forKey: languageKey)
    }

    private func updateCurrentBundle() {
        let bundlePath: String

        switch currentLanguage {
        case .system:
            // Use system language
            currentBundle = Bundle.main
            return

        case .english:
            bundlePath = "en"

        case .simplifiedChinese:
            bundlePath = "zh-Hans"

        case .traditionalChinese:
            bundlePath = "zh-Hant"
        }

        guard let path = Bundle.main.path(forResource: bundlePath, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            currentBundle = Bundle.main
            return
        }

        currentBundle = bundle
    }
}

// MARK: - Supported Languages

enum SupportedLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var displayName: String {
        switch self {
        case .system:
            return LocalizationManager.shared.localizedString(for: "system")
        case .english:
            return LocalizationManager.shared.localizedString(for: "english")
        case .simplifiedChinese:
            return LocalizationManager.shared.localizedString(for: "simplified_chinese")
        case .traditionalChinese:
            return LocalizationManager.shared.localizedString(for: "traditional_chinese")
        }
    }

    var nativeName: String {
        switch self {
        case .system:
            return "System"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.current.identifier
        case .english:
            return "en-US"
        case .simplifiedChinese:
            return "zh-Hans-CN"
        case .traditionalChinese:
            return "zh-Hant-TW"
        }
    }

    var ocrLanguageCodes: [String] {
        switch self {
        case .system:
            return ["en-US"]
        case .english:
            return ["en-US"]
        case .simplifiedChinese:
            return ["zh-Hans", "en-US"]
        case .traditionalChinese:
            return ["zh-Hant", "en-US"]
        }
    }

    var flag: String {
        switch self {
        case .system:
            return "🌐"
        case .english:
            return "🇺🇸"
        case .simplifiedChinese:
            return "🇨🇳"
        case .traditionalChinese:
            return "🇹🇼"
        }
    }
}

// MARK: - SwiftUI Extension

extension String {
    /// Get localized string using the LocalizationManager
    var localized: String {
        return LocalizationManager.shared.localizedString(for: self)
    }

    /// Get localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        let format = LocalizationManager.shared.localizedString(for: self)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// Apply localization environment
    func withLocalization() -> some View {
        self.environmentObject(LocalizationManager.shared)
            .environment(\.locale, LocalizationManager.shared.currentLocale)
    }
}

// MARK: - Localized Text View

struct LocalizedText: View {
    private let key: String
    private let arguments: [CVarArg]

    init(_ key: String, arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View {
        if arguments.isEmpty {
            Text(key.localized)
        } else {
            Text(key.localized(with: arguments))
        }
    }
}

// MARK: - Language Picker View

struct LanguagePickerView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                ForEach(SupportedLanguage.allCases, id: \.self) { language in
                    LanguageRow(
                        language: language,
                        isSelected: localizationManager.currentLanguage == language
                    ) {
                        localizationManager.setLanguage(language)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle("select_language".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct LanguageRow: View {
    let language: SupportedLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(language.flag)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.nativeName)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(language.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Date Formatting Extensions

extension DateFormatter {
    /// Create a localized date formatter
    static func localized(dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .none) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter
    }
}

extension NumberFormatter {
    /// Create a localized number formatter
    static func localized(numberStyle: NumberFormatter.Style = .decimal) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.numberStyle = numberStyle
        return formatter
    }
}