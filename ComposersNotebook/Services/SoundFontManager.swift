import Foundation
import AVFoundation

// MARK: - SoundFont Manager
// Manages built-in and user SoundFont (.sf2) files

@MainActor
class SoundFontManager: ObservableObject {

    static let shared = SoundFontManager()

    // MARK: - Published State

    @Published var availableSoundFonts: [SoundFontInfo] = []
    @Published var activeSoundFont: SoundFontInfo?
    @Published var isLoading = false

    // MARK: - Sound Font Info

    struct SoundFontInfo: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL
        let source: SoundFontSource
        let fileSize: Int64

        var fileSizeString: String {
            ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
    }

    enum SoundFontSource: Equatable {
        case builtIn       // Shipped with app (General MIDI)
        case bundledPlugin // On-Demand Resource (downloadable)
        case userImported  // User's own .sf2
    }

    // MARK: - Instrument Settings

    struct InstrumentSettings: Codable, Equatable {
        var volume: Float = 0.8      // 0...1
        var pan: Float = 0.0         // -1 (left) ... 1 (right)
        var reverb: Float = 0.3      // 0...1
        var brightness: Float = 0.5  // 0...1 (EQ highshelf)
        var attack: Float = 0.01     // ADSR seconds
        var decay: Float = 0.1
        var sustain: Float = 0.7     // level 0...1
        var release: Float = 0.3     // seconds
        var presetName: String?      // User-saved preset name

        static let `default` = InstrumentSettings()

        // Named presets
        static let warm = InstrumentSettings(brightness: 0.3, attack: 0.02, sustain: 0.8, release: 0.4, presetName: "Warm")
        static let bright = InstrumentSettings(brightness: 0.8, attack: 0.005, sustain: 0.6, release: 0.2, presetName: "Bright")
        static let classical = InstrumentSettings(reverb: 0.5, brightness: 0.5, attack: 0.01, sustain: 0.7, release: 0.35, presetName: "Classical")
        static let soft = InstrumentSettings(volume: 0.6, brightness: 0.25, attack: 0.03, sustain: 0.9, release: 0.5, presetName: "Soft")
    }

    // Per-instrument settings storage
    @Published var instrumentSettings: [String: InstrumentSettings] = [:] // instrument.id.uuidString -> settings

    // User-saved presets
    @Published var userPresets: [String: [UserPreset]] = [:] // instrument group -> presets

    struct UserPreset: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var settings: InstrumentSettings
        var instrumentGroup: String
    }

    // MARK: - Init

    private init() {
        scanAvailableSoundFonts()
        loadSettings()
    }

    // MARK: - SoundFont Discovery

    func scanAvailableSoundFonts() {
        var fonts: [SoundFontInfo] = []

        // 1. Built-in (from app bundle)
        if let bundleSF2s = Bundle.main.urls(forResourcesWithExtension: "sf2", subdirectory: nil) {
            for url in bundleSF2s {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                fonts.append(SoundFontInfo(
                    id: "builtin_\(url.lastPathComponent)",
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    source: .builtIn,
                    fileSize: size
                ))
            }
        }

        // 2. User-imported (from Documents/SoundFonts/)
        let userDir = userSoundFontDirectory
        if let userFiles = try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in userFiles where url.pathExtension.lowercased() == "sf2" {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { Int64($0) }) ?? 0
                fonts.append(SoundFontInfo(
                    id: "user_\(url.lastPathComponent)",
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    source: .userImported,
                    fileSize: size ?? 0
                ))
            }
        }

        availableSoundFonts = fonts

        // Set active if none
        if activeSoundFont == nil {
            activeSoundFont = fonts.first(where: { $0.source == .builtIn }) ?? fonts.first
        }
    }

    // MARK: - User SoundFont Import

    var userSoundFontDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("SoundFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Import a user's .sf2 file (copy to app's SoundFonts directory)
    func importSoundFont(from sourceURL: URL) throws -> SoundFontInfo {
        let fileName = sourceURL.lastPathComponent
        let destURL = userSoundFontDirectory.appendingPathComponent(fileName)

        // Accessing security-scoped resource
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let size = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
        let info = SoundFontInfo(
            id: "user_\(fileName)",
            name: destURL.deletingPathExtension().lastPathComponent,
            url: destURL,
            source: .userImported,
            fileSize: size
        )

        scanAvailableSoundFonts()
        return info
    }

    /// Delete a user-imported SoundFont
    func deleteUserSoundFont(_ info: SoundFontInfo) throws {
        guard info.source == .userImported else { return }
        try FileManager.default.removeItem(at: info.url)
        scanAvailableSoundFonts()
    }

    // MARK: - Load SoundFont into Sampler

    /// Load active SoundFont into AVAudioUnitSampler
    func loadIntoSampler(_ sampler: AVAudioUnitSampler, program: UInt8 = 0, bankMSB: UInt8 = UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8 = 0) throws {
        guard let sf = activeSoundFont else { return }

        try sampler.loadSoundBankInstrument(
            at: sf.url,
            program: program,
            bankMSB: bankMSB,
            bankLSB: bankLSB
        )
    }

    // MARK: - Settings Persistence

    private var settingsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sound_settings.json")
    }

    private var presetsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sound_presets.json")
    }

    func saveSettings() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(instrumentSettings) {
            try? data.write(to: settingsURL)
        }

        if let data = try? encoder.encode(userPresets) {
            try? data.write(to: presetsURL)
        }
    }

    func loadSettings() {
        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: settingsURL),
           let settings = try? decoder.decode([String: InstrumentSettings].self, from: data) {
            instrumentSettings = settings
        }

        if let data = try? Data(contentsOf: presetsURL),
           let presets = try? decoder.decode([String: [UserPreset]].self, from: data) {
            userPresets = presets
        }
    }

    // MARK: - Instrument Settings Access

    func settings(for instrumentId: String) -> InstrumentSettings {
        instrumentSettings[instrumentId] ?? .default
    }

    func updateSettings(for instrumentId: String, _ settings: InstrumentSettings) {
        instrumentSettings[instrumentId] = settings
        saveSettings()
    }

    func resetSettings(for instrumentId: String) {
        instrumentSettings[instrumentId] = .default
        saveSettings()
    }

    // MARK: - User Presets

    func savePreset(name: String, settings: InstrumentSettings, group: String) {
        var preset = UserPreset(id: UUID(), name: name, settings: settings, instrumentGroup: group)
        preset.settings.presetName = name

        var groupPresets = userPresets[group] ?? []
        groupPresets.append(preset)
        userPresets[group] = groupPresets
        saveSettings()
    }

    func deletePreset(_ preset: UserPreset) {
        userPresets[preset.instrumentGroup]?.removeAll { $0.id == preset.id }
        saveSettings()
    }

    // MARK: - Built-in Presets

    static let builtInPresets: [InstrumentSettings] = [
        .warm, .bright, .classical, .soft
    ]
}
