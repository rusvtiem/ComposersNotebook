import SwiftUI

// MARK: - Theme System

struct AppTheme: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isBuiltIn: Bool = false

    // Color tokens (stored as hex strings for Codable)
    var accentHex: String
    var backgroundHex: String
    var surfaceHex: String
    var textPrimaryHex: String
    var textSecondaryHex: String
    var staffLineHex: String
    var noteHeadHex: String
    var selectedNoteHex: String
    var barlineHex: String
    var cursorHex: String
    var toolbarBackgroundHex: String

    // Staff appearance
    var staffLineOpacity: Double = 0.4
    var noteHeadOpacity: Double = 1.0

    // Font preferences
    var useSerifForDynamics: Bool = true

    // Color scheme preference
    var colorSchemePreference: ThemeColorScheme = .dark
}

enum ThemeColorScheme: String, Codable, CaseIterable {
    case light
    case dark
    case system
}

// MARK: - Color Scheme Resolution

extension AppTheme {
    var resolvedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Color Convenience

extension AppTheme {
    var accent: Color { Color(hex: accentHex) }
    var background: Color { Color(hex: backgroundHex) }
    var surface: Color { Color(hex: surfaceHex) }
    var textPrimary: Color { Color(hex: textPrimaryHex) }
    var textSecondary: Color { Color(hex: textSecondaryHex) }
    var staffLine: Color { Color(hex: staffLineHex) }
    var noteHead: Color { Color(hex: noteHeadHex) }
    var selectedNote: Color { Color(hex: selectedNoteHex) }
    var barline: Color { Color(hex: barlineHex) }
    var cursor: Color { Color(hex: cursorHex) }
    var toolbarBackground: Color { Color(hex: toolbarBackgroundHex) }
}

// MARK: - Built-in Themes

extension AppTheme {
    static let light = AppTheme(
        id: "light",
        name: String(localized: "Светлая"),
        isBuiltIn: true,
        accentHex: "#007AFF",
        backgroundHex: "#FFFFFF",
        surfaceHex: "#F2F2F7",
        textPrimaryHex: "#000000",
        textSecondaryHex: "#8E8E93",
        staffLineHex: "#000000",
        noteHeadHex: "#000000",
        selectedNoteHex: "#007AFF",
        barlineHex: "#000000",
        cursorHex: "#FF3B30",
        toolbarBackgroundHex: "#F9F9F9",
        colorSchemePreference: .light
    )

    static let dark = AppTheme(
        id: "dark",
        name: String(localized: "Тёмная"),
        isBuiltIn: true,
        accentHex: "#0A84FF",
        backgroundHex: "#000000",
        surfaceHex: "#1C1C1E",
        textPrimaryHex: "#FFFFFF",
        textSecondaryHex: "#8E8E93",
        staffLineHex: "#FFFFFF",
        noteHeadHex: "#FFFFFF",
        selectedNoteHex: "#0A84FF",
        barlineHex: "#FFFFFF",
        cursorHex: "#FF453A",
        toolbarBackgroundHex: "#1C1C1E",
        colorSchemePreference: .dark
    )

    static let sepia = AppTheme(
        id: "sepia",
        name: String(localized: "Сепия"),
        isBuiltIn: true,
        accentHex: "#A0522D",
        backgroundHex: "#FAF0E6",
        surfaceHex: "#F5E6D3",
        textPrimaryHex: "#3E2723",
        textSecondaryHex: "#795548",
        staffLineHex: "#5D4037",
        noteHeadHex: "#3E2723",
        selectedNoteHex: "#A0522D",
        barlineHex: "#5D4037",
        cursorHex: "#D84315",
        toolbarBackgroundHex: "#F0E0CE",
        colorSchemePreference: .light
    )

    static let midnight = AppTheme(
        id: "midnight",
        name: String(localized: "Полночь"),
        isBuiltIn: true,
        accentHex: "#5E5CE6",
        backgroundHex: "#0A0A1A",
        surfaceHex: "#16162A",
        textPrimaryHex: "#E0E0F0",
        textSecondaryHex: "#7070A0",
        staffLineHex: "#C0C0E0",
        noteHeadHex: "#E0E0F0",
        selectedNoteHex: "#5E5CE6",
        barlineHex: "#C0C0E0",
        cursorHex: "#FF6B6B",
        toolbarBackgroundHex: "#12122A",
        colorSchemePreference: .dark
    )

    static let parchment = AppTheme(
        id: "parchment",
        name: String(localized: "Пергамент"),
        isBuiltIn: true,
        accentHex: "#8B4513",
        backgroundHex: "#F5F0E8",
        surfaceHex: "#EDE5D8",
        textPrimaryHex: "#2C1810",
        textSecondaryHex: "#6B5B4F",
        staffLineHex: "#4A3728",
        noteHeadHex: "#2C1810",
        selectedNoteHex: "#8B4513",
        barlineHex: "#4A3728",
        cursorHex: "#C62828",
        toolbarBackgroundHex: "#EAE0D2",
        colorSchemePreference: .light
    )

    static let allBuiltIn: [AppTheme] = [.light, .dark, .sepia, .midnight, .parchment]
}

// MARK: - Theme Manager

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme {
        didSet { save() }
    }
    @Published var customThemes: [AppTheme] = []

    private let currentThemeKey = "currentThemeId"
    private let customThemesKey = "customThemes"

    init() {
        // Load custom themes
        if let data = UserDefaults.standard.data(forKey: customThemesKey),
           let themes = try? JSONDecoder().decode([AppTheme].self, from: data) {
            self.customThemes = themes
        }

        // Load current theme
        let savedId = UserDefaults.standard.string(forKey: currentThemeKey) ?? "dark"
        let allThemes = AppTheme.allBuiltIn + (
            (try? JSONDecoder().decode([AppTheme].self, from: UserDefaults.standard.data(forKey: customThemesKey) ?? Data())) ?? []
        )
        self.currentTheme = allThemes.first(where: { $0.id == savedId }) ?? .dark
    }

    var allThemes: [AppTheme] {
        AppTheme.allBuiltIn + customThemes
    }

    func applyTheme(_ theme: AppTheme) {
        currentTheme = theme
    }

    func addCustomTheme(_ theme: AppTheme) {
        var newTheme = theme
        newTheme.isBuiltIn = false
        customThemes.append(newTheme)
        save()
    }

    func deleteCustomTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        if currentTheme.id == id {
            currentTheme = .dark
        }
        save()
    }

    func duplicateTheme(_ theme: AppTheme, name: String) -> AppTheme {
        var copy = theme
        copy.id = UUID().uuidString
        copy.name = name
        copy.isBuiltIn = false
        addCustomTheme(copy)
        return copy
    }

    // MARK: - JSON Export/Import

    func exportTheme(_ theme: AppTheme) throws -> Data {
        try JSONEncoder().encode(theme)
    }

    func importTheme(from data: Data) throws -> AppTheme {
        var theme = try JSONDecoder().decode(AppTheme.self, from: data)
        theme.id = UUID().uuidString
        theme.isBuiltIn = false
        addCustomTheme(theme)
        return theme
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(currentTheme.id, forKey: currentThemeKey)
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: customThemesKey)
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
