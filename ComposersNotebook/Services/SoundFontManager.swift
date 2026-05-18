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
        case bundledPlugin // On-Demand Resource (legacy)
        case downloaded    // Downloaded from author site into Documents/SoundFonts/
        case userImported  // User's own .sf2 imported via Files picker
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
        var eqLow: Float = 0.0      // -12...+12 dB (low shelf 200Hz)
        var eqMid: Float = 0.0      // -12...+12 dB (parametric 1kHz)
        var eqHigh: Float = 0.0     // -12...+12 dB (high shelf 5kHz)
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
        restoreActiveSoundFont()
    }

    // MARK: - Active SoundFont Persistence

    private let activeSoundFontKey = "ComposersNotebook.activeSoundFontID"

    /// Сохраняем выбор пользователя между запусками.
    func setActiveSoundFont(_ font: SoundFontInfo?) {
        activeSoundFont = font
        if let id = font?.id {
            UserDefaults.standard.set(id, forKey: activeSoundFontKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeSoundFontKey)
        }
        NotificationCenter.default.post(name: .activeSoundFontDidChange, object: nil)
    }

    private func restoreActiveSoundFont() {
        guard let savedID = UserDefaults.standard.string(forKey: activeSoundFontKey) else { return }
        if let found = availableSoundFonts.first(where: { $0.id == savedID }) {
            activeSoundFont = found
        }
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

        // 2. Downloaded recommended (from Documents/SoundFonts/Downloaded/)
        let downloadedDir = downloadedSoundFontDirectory
        if let downloadedFiles = try? FileManager.default.contentsOfDirectory(at: downloadedDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in downloadedFiles where url.pathExtension.lowercased() == "sf2" {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                fonts.append(SoundFontInfo(
                    id: "downloaded_\(url.lastPathComponent)",
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    source: .downloaded,
                    fileSize: size
                ))
            }
        }

        // 3. User-imported (from Documents/SoundFonts/)
        let userDir = userSoundFontDirectory
        if let userFiles = try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in userFiles where url.pathExtension.lowercased() == "sf2" {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                fonts.append(SoundFontInfo(
                    id: "user_\(url.lastPathComponent)",
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    source: .userImported,
                    fileSize: size
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

    /// Каталог в Documents для SoundFont, скачанных из приложения через
    /// меню "Available for download". Отделён от пользовательских импортов,
    /// чтобы избежать путаницы (что наше, что чужое).
    var downloadedSoundFontDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("SoundFonts", isDirectory: true).appendingPathComponent("Downloaded", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Import a user's .sf2 file (copy to app's SoundFonts directory).
    /// Validates SoundFont magic bytes ("RIFF...sfbk") before accepting.
    func importSoundFont(from sourceURL: URL) throws -> SoundFontInfo {
        let fileName = sourceURL.lastPathComponent
        let destURL = userSoundFontDirectory.appendingPathComponent(fileName)

        // Accessing security-scoped resource
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        // Magic-byte validation: SF2 = "RIFF<size>sfbk"
        if let handle = try? FileHandle(forReadingFrom: sourceURL) {
            defer { try? handle.close() }
            let header = handle.readData(ofLength: 12)
            let isValidSF2 = header.count == 12 &&
                header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 && // RIFF
                header[8] == 0x73 && header[9] == 0x66 && header[10] == 0x62 && header[11] == 0x6B   // sfbk
            if !isValidSF2 {
                throw NSError(domain: "SoundFontManager", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "File is not a valid SoundFont (.sf2)")
                ])
            }
        }

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

    /// Delete a downloaded SoundFont. Built-in fonts cannot be deleted.
    /// If the active SoundFont is the one being deleted — fall back to
    /// any built-in font so playback keeps working.
    func deleteDownloadedSoundFont(_ info: SoundFontInfo) throws {
        guard info.source == .downloaded else { return }
        if activeSoundFont?.id == info.id {
            let fallback = availableSoundFonts.first { $0.source == .builtIn }
            setActiveSoundFont(fallback)
        }
        try FileManager.default.removeItem(at: info.url)
        scanAvailableSoundFonts()
    }

    // MARK: - Recommended SoundFont Download
    //
    // Скачивание из меню "Available for download". Использует URL автора
    // (или зеркало) → сохраняет в Documents/SoundFonts/Downloaded/.
    // Прогресс публикуется через @Published downloadProgress; ошибки
    // публикуются в downloadErrors с автоматической retry-логикой по
    // зеркалам из манифеста.

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadErrors: [String: String] = [:]
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]

    /// Запустить скачивание рекомендованного SoundFont. Если конкретного
    /// recommendedSoundFonts.directDownloadURL нет — ничего не делает
    /// (UI должен предлагать пользователю открыть homepage и импортировать вручную).
    func downloadRecommended(_ recommended: RecommendedSoundFont) {
        guard let primary = recommended.directDownloadURL else { return }

        // Если уже скачан — ничего.
        if downloadedSoundFontExists(named: recommended.fileName) { return }

        downloadProgress[recommended.id] = 0
        downloadErrors.removeValue(forKey: recommended.id)

        let urls = [primary] + recommended.mirrors
        Task { @MainActor [weak self] in
            await self?.tryDownload(urls: urls, recommended: recommended)
        }
    }

    private func tryDownload(urls: [URL], recommended: RecommendedSoundFont) async {
        for url in urls {
            do {
                try await performDownload(from: url, recommended: recommended)
                downloadProgress.removeValue(forKey: recommended.id)
                scanAvailableSoundFonts()
                return
            } catch {
                // Continue to next mirror
                continue
            }
        }
        // All mirrors failed
        downloadProgress.removeValue(forKey: recommended.id)
        downloadErrors[recommended.id] = String(localized: "All download sources are unavailable. Try opening the author site and importing the file manually.")
    }

    private func performDownload(from url: URL, recommended: RecommendedSoundFont) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: url) { progress in
            Task { @MainActor [weak self] in
                self?.downloadProgress[recommended.id] = progress
            }
        }

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: "SoundFontManager", code: http.statusCode)
        }

        // Magic-byte validation
        if let handle = try? FileHandle(forReadingFrom: tempURL) {
            defer { try? handle.close() }
            let header = handle.readData(ofLength: 12)
            let isValid = header.count == 12 &&
                header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 &&
                header[8] == 0x73 && header[9] == 0x66 && header[10] == 0x62 && header[11] == 0x6B
            if !isValid {
                try? FileManager.default.removeItem(at: tempURL)
                throw NSError(domain: "SoundFontManager", code: -1)
            }
        }

        let destURL = downloadedSoundFontDirectory.appendingPathComponent(recommended.fileName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
    }

    func cancelDownload(recommendedID: String) {
        activeDownloadTasks[recommendedID]?.cancel()
        activeDownloadTasks.removeValue(forKey: recommendedID)
        downloadProgress.removeValue(forKey: recommendedID)
    }

    /// Скачан ли recommended SoundFont (по имени файла)?
    func downloadedSoundFontExists(named fileName: String) -> Bool {
        let url = downloadedSoundFontDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Найти SoundFontInfo для уже скачанного recommended.
    func downloadedInfo(for recommended: RecommendedSoundFont) -> SoundFontInfo? {
        availableSoundFonts.first { $0.source == .downloaded && $0.url.lastPathComponent == recommended.fileName }
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

    // MARK: - On-Demand Resources (ODR)

    struct ODRPack: Identifiable {
        let id: String
        let name: String
        let tag: String
        let description: String
        let estimatedSize: String
    }

    static let availableODRPacks: [ODRPack] = [
        ODRPack(id: "piano_hq", name: "Piano HQ", tag: "soundfont.piano.hq", description: "Steinway Grand Piano (24-bit)", estimatedSize: "25 MB"),
        ODRPack(id: "strings_hq", name: "Strings HQ", tag: "soundfont.strings.hq", description: "Orchestral Strings Section", estimatedSize: "18 MB"),
        ODRPack(id: "choir_hq", name: "Choir HQ", tag: "soundfont.choir.hq", description: "SATB Choir Voices", estimatedSize: "15 MB"),
        ODRPack(id: "woodwinds_hq", name: "Woodwinds HQ", tag: "soundfont.woodwinds.hq", description: "Flute, Oboe, Clarinet, Bassoon", estimatedSize: "12 MB"),
        ODRPack(id: "brass_hq", name: "Brass HQ", tag: "soundfont.brass.hq", description: "Horn, Trumpet, Trombone, Tuba", estimatedSize: "14 MB"),
        ODRPack(id: "guitar_hq", name: "Guitar HQ", tag: "soundfont.guitar.hq", description: "Acoustic & Classical Guitar", estimatedSize: "10 MB"),
    ]

    @Published var odrDownloadProgress: [String: Double] = [:]
    @Published var odrDownloadedPacks: Set<String> = []
    private var activeRequests: [String: NSBundleResourceRequest] = [:]

    func downloadODRPack(_ pack: ODRPack) {
        let request = NSBundleResourceRequest(tags: [pack.tag])
        activeRequests[pack.id] = request
        odrDownloadProgress[pack.id] = 0.0

        // Async path avoids non-Sendable closure capture warnings that the
        // legacy completion-handler API triggered under Swift 6 strict mode.
        Task { @MainActor [weak self] in
            guard let self else { return }

            if await Self.conditionallyBegin(request) {
                self.odrDownloadedPacks.insert(pack.id)
                self.odrDownloadProgress.removeValue(forKey: pack.id)
                self.scanAvailableSoundFonts()
                self.activeRequests.removeValue(forKey: pack.id)
                return
            }

            let progress = request.progress
            let progressTask = Task { @MainActor [weak self] in
                while !progress.isFinished && !progress.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.odrDownloadProgress[pack.id] = progress.fractionCompleted
                }
            }

            do {
                try await Self.beginAccessing(request)
                self.odrDownloadedPacks.insert(pack.id)
                self.scanAvailableSoundFonts()
            } catch {
                print("ODR download error: \(error)")
            }

            progressTask.cancel()
            self.odrDownloadProgress.removeValue(forKey: pack.id)
            self.activeRequests.removeValue(forKey: pack.id)
        }
    }

    /// Continuation wrapper around the completion-handler API. Confines the
    /// non-Sendable `NSBundleResourceRequest` to this single function so the
    /// capture warning does not propagate into the caller's task.
    private static func conditionallyBegin(_ request: NSBundleResourceRequest) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            request.conditionallyBeginAccessingResources { available in
                cont.resume(returning: available)
            }
        }
    }

    private static func beginAccessing(_ request: NSBundleResourceRequest) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            request.beginAccessingResources { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    func cancelODRDownload(_ pack: ODRPack) {
        activeRequests[pack.id]?.progress.cancel()
        activeRequests.removeValue(forKey: pack.id)
        odrDownloadProgress.removeValue(forKey: pack.id)
    }

    func isODRPackDownloaded(_ pack: ODRPack) -> Bool {
        odrDownloadedPacks.contains(pack.id)
    }

    // MARK: - Recommended Free SoundFonts (no AI, no purchase)
    //
    // Список бесплатных SoundFont, которые можно скачать в Files
    // и импортировать через `importSoundFont(from:)`. Никаких ИИ.

    struct RecommendedSoundFont: Identifiable {
        let id: String
        let name: String
        let author: String
        let homepage: String
        let estimatedSize: String
        let license: String
        let summary: String
        let fileName: String
        let directDownloadURL: URL?
        let mirrors: [URL]
    }

    /// Manifest of recommended SoundFonts.
    ///
    /// Direct download URLs and mirrors are stored here so URL changes can be
    /// shipped via an app update without modifying download logic. When all
    /// sources fail at runtime, the UI shows the homepage so the user can
    /// download manually and import via "+ Import .sf2".
    static let recommendedSoundFonts: [RecommendedSoundFont] = [
        RecommendedSoundFont(
            id: "general_user_gs",
            name: "GeneralUser GS",
            author: "S. Christian Collins",
            homepage: "https://schristiancollins.com/generaluser.php",
            estimatedSize: String(localized: "~30 MB"),
            license: "CC BY 3.0",
            summary: String(localized: "Balanced GM/GS bank: 259 presets, 11 drum kits. Compact universal SoundFont."),
            fileName: "GeneralUserGS.sf2",
            directDownloadURL: nil,
            mirrors: []
        ),
        RecommendedSoundFont(
            id: "fluidr3_gm",
            name: "FluidR3 GM",
            author: "Frank Wen",
            homepage: "https://member.keymusician.com/Member/FluidR3_GM/index.html",
            estimatedSize: String(localized: "~141 MB"),
            license: "MIT",
            summary: String(localized: "Large GM bank known from FluidSynth/MuseScore. Open-source standard."),
            fileName: "FluidR3_GM.sf2",
            directDownloadURL: nil,
            mirrors: []
        ),
        RecommendedSoundFont(
            id: "musescore_general",
            name: "MuseScore_General",
            author: "MuseScore Studio",
            homepage: "https://musescore.org/en/handbook/4/soundfonts-and-sfz-files",
            estimatedSize: String(localized: "~208 MB"),
            license: "CC BY 4.0",
            summary: String(localized: "MuseScore 4 default. AVAudioUnitSampler accepts only .sf2 — take the 208 MB version, not .sf3."),
            fileName: "MuseScore_General.sf2",
            directDownloadURL: nil,
            mirrors: []
        ),
        RecommendedSoundFont(
            id: "sonatina",
            name: "Sonatina Symphonic Orchestra",
            author: "Mattias Westlund",
            homepage: "https://sso.mattiaswestlund.net/",
            estimatedSize: String(localized: "~503 MB"),
            license: "CC Sampling Plus 1.0",
            summary: String(localized: "Heavy-duty orchestral bank. Install only if storage is not a concern."),
            fileName: "Sonatina.sf2",
            directDownloadURL: nil,
            mirrors: []
        ),
        RecommendedSoundFont(
            id: "salamander",
            name: "Salamander Grand Piano",
            author: "Alexander Holm",
            homepage: "https://sfzinstruments.github.io/pianos/salamander.html",
            estimatedSize: String(localized: "~200 MB"),
            license: "CC BY 3.0",
            summary: String(localized: "Yamaha C5 concert grand piano. Best when piano is the primary instrument."),
            fileName: "Salamander.sf2",
            directDownloadURL: nil,
            mirrors: []
        ),
    ]
}

// MARK: - URLSession download with progress

private extension URLSession {
    func download(from url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await bytes(from: url)
        let total = response.expectedContentLength
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sf2")

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        var bytesReceived: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(65536)

        for try await byte in asyncBytes {
            buffer.append(byte)
            bytesReceived += 1
            if buffer.count >= 65536 {
                try handle.write(contentsOf: Data(buffer))
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    onProgress(Double(bytesReceived) / Double(total))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: Data(buffer))
        }
        onProgress(1.0)
        return (tempURL, response)
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Постится когда `activeSoundFont` меняется (через `setActiveSoundFont`).
    /// MIDIEngine подписывается и перезагружает sampler.
    static let activeSoundFontDidChange = Notification.Name("ComposersNotebook.activeSoundFontDidChange")
}
