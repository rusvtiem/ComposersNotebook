import SwiftUI
import UniformTypeIdentifiers

// MARK: - ADSR Curve View

struct ADSRCurveView: View {
    let attack: Float
    let decay: Float
    let sustain: Float
    let release: Float

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let totalTime = max(attack + decay + 0.3 + release, 0.5)
            let aX = CGFloat(attack / totalTime) * w
            let dX = aX + CGFloat(decay / totalTime) * w
            let sX = dX + CGFloat(0.3 / totalTime) * w
            let rX = w
            let sustainY = h * CGFloat(1.0 - sustain)

            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: aX, y: 0))
                path.addLine(to: CGPoint(x: dX, y: sustainY))
                path.addLine(to: CGPoint(x: sX, y: sustainY))
                path.addLine(to: CGPoint(x: rX, y: h))
            }
            .stroke(Color.accentColor, lineWidth: 2)

            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: aX, y: 0))
                path.addLine(to: CGPoint(x: dX, y: sustainY))
                path.addLine(to: CGPoint(x: sX, y: sustainY))
                path.addLine(to: CGPoint(x: rX, y: h))
                path.closeSubpath()
            }
            .fill(Color.accentColor.opacity(0.1))

            // Phase labels
            let labels: [(String, CGFloat)] = [
                ("A", aX / 2),
                ("D", (aX + dX) / 2),
                ("S", (dX + sX) / 2),
                ("R", (sX + rX) / 2)
            ]
            ForEach(Array(labels.enumerated()), id: \.offset) { _, item in
                Text(item.0)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .position(x: item.1, y: h - 6)
            }
        }
    }
}

// MARK: - Graphic EQ View

struct GraphicEQView: View {
    @Binding var low: Float
    @Binding var mid: Float
    @Binding var high: Float
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Equalizer"))
                    .font(.caption)
                Spacer()
            }

            HStack(spacing: 16) {
                eqBand(label: "200 Hz", value: $low)
                eqBand(label: "1 kHz", value: $mid)
                eqBand(label: "5 kHz", value: $high)
            }
            .frame(height: 120)
        }
    }

    private func eqBand(label: String, value: Binding<Float>) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%+.0f", value.wrappedValue))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let h = geo.size.height
                let normalized = CGFloat((value.wrappedValue + 12) / 24)
                let thumbY = h * (1 - normalized)

                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(width: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 4, height: max(0, abs(h / 2 - thumbY)))
                        .offset(y: value.wrappedValue >= 0 ? -(h / 2 - thumbY) / 2 : (thumbY - h / 2) / 2)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .offset(y: thumbY - h / 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let clamped = min(max(drag.location.y / h, 0), 1)
                            value.wrappedValue = Float((1 - clamped) * 24 - 12)
                            onChange()
                        }
                )
            }

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Sound Settings View

struct SoundSettingsView: View {
    @ObservedObject var soundFontManager: SoundFontManager
    let instrument: Instrument
    let onPreview: () -> Void

    @State private var settings: SoundFontManager.InstrumentSettings
    @State private var showAdvanced = false
    @State private var showSavePreset = false
    @State private var newPresetName = ""
    @State private var showSF2Picker = false
    @State private var importError: String?

    private var instrumentId: String { instrument.id.uuidString }

    init(soundFontManager: SoundFontManager, instrument: Instrument, onPreview: @escaping () -> Void) {
        self.soundFontManager = soundFontManager
        self.instrument = instrument
        self.onPreview = onPreview
        _settings = State(initialValue: soundFontManager.settings(for: instrument.id.uuidString))
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    presetPicker
                    volumeSlider
                    panSlider
                    reverbSlider
                } header: {
                    Label(instrument.name, systemImage: "music.note")
                }

                Section {
                    Button {
                        withAnimation { showAdvanced.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text(String(localized: "Advanced Settings"))
                            Spacer()
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showAdvanced {
                        // ADSR with visual curve
                        ADSRCurveView(
                            attack: settings.attack,
                            decay: settings.decay,
                            sustain: settings.sustain,
                            release: settings.release
                        )
                        .frame(height: 80)
                        .padding(.vertical, 4)

                        attackSlider
                        decaySlider
                        sustainSlider
                        releaseSlider

                        Divider()

                        brightnessSlider

                        // Graphic EQ
                        GraphicEQView(
                            low: $settings.eqLow,
                            mid: $settings.eqMid,
                            high: $settings.eqHigh,
                            onChange: saveAndApply
                        )
                        .padding(.vertical, 4)

                        Divider()

                        instrumentSpecificControls
                    }
                } header: {
                    Text(String(localized: "Sound Character"))
                }

                Section {
                    soundFontPicker
                } header: {
                    Text(String(localized: "Sound Source"))
                }

                // MARK: - Downloadable Sound Packs (ODR)
                Section {
                    ForEach(SoundFontManager.availableODRPacks) { pack in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pack.name).font(.body)
                                Text(pack.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(pack.estimatedSize).font(.caption2).foregroundStyle(.tertiary)

                            if soundFontManager.isODRPackDownloaded(pack) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else if let progress = soundFontManager.odrDownloadProgress[pack.id] {
                                ProgressView(value: progress)
                                    .frame(width: 50)
                                Button {
                                    soundFontManager.cancelODRDownload(pack)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Button {
                                    soundFontManager.downloadODRPack(pack)
                                } label: {
                                    Image(systemName: "icloud.and.arrow.down")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Sound Packs"))
                }

                Section {
                    Button {
                        onPreview()
                        HapticManager.buttonTap()
                    } label: {
                        Label(String(localized: "Preview Sound"), systemImage: "play.circle")
                    }

                    Button {
                        showSavePreset = true
                    } label: {
                        Label(String(localized: "Save as Preset"), systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        settings = .default
                        saveAndApply()
                        HapticManager.success()
                    } label: {
                        Label(String(localized: "Reset to Default"), systemImage: "arrow.counterclockwise")
                    }
                }

                if let presets = soundFontManager.userPresets[instrument.group.rawValue], !presets.isEmpty {
                    Section {
                        ForEach(presets) { preset in
                            Button {
                                settings = preset.settings
                                saveAndApply()
                            } label: {
                                HStack {
                                    Text(preset.name)
                                    Spacer()
                                    if settings.presetName == preset.name {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    soundFontManager.deletePreset(preset)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(String(localized: "My Presets"))
                    }
                }
            }
            .navigationTitle(instrument.name)
            .navigationBarTitleDisplayMode(.inline)
            .alert(String(localized: "Save Preset"), isPresented: $showSavePreset) {
                TextField(String(localized: "Preset name"), text: $newPresetName)
                Button(String(localized: "Save")) {
                    if !newPresetName.isEmpty {
                        soundFontManager.savePreset(
                            name: newPresetName,
                            settings: settings,
                            group: instrument.group.rawValue
                        )
                        newPresetName = ""
                        HapticManager.success()
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
        }
    }

    // MARK: - Simple Controls

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Sound Preset"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SoundFontManager.builtInPresets, id: \.presetName) { preset in
                        Button {
                            settings = preset
                            saveAndApply()
                            HapticManager.buttonTap()
                        } label: {
                            Text(localizedPresetName(preset.presetName ?? ""))
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    settings.presetName == preset.presetName
                                        ? Color.accentColor.opacity(0.2)
                                        : Color(.systemGray5)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var volumeSlider: some View {
        sliderRow(
            label: String(localized: "Volume"),
            icon: "speaker.wave.2",
            value: $settings.volume,
            range: 0...1,
            tooltip: String(localized: "Master volume of this instrument (0–100%)"),
            onChange: saveAndApply
        )
    }

    private var panSlider: some View {
        sliderRow(
            label: String(localized: "Pan"),
            icon: "arrow.left.and.right",
            value: $settings.pan,
            range: -1...1,
            leftLabel: "L",
            rightLabel: "R",
            tooltip: String(localized: "Stereo position: left (-100%) to right (+100%)"),
            onChange: saveAndApply
        )
    }

    private var reverbSlider: some View {
        sliderRow(
            label: String(localized: "Reverb"),
            icon: "waveform.path",
            value: $settings.reverb,
            range: 0...1,
            leftLabel: String(localized: "Dry"),
            rightLabel: String(localized: "Hall"),
            tooltip: String(localized: "Reverb amount: dry (no echo) to hall (concert hall)"),
            onChange: saveAndApply
        )
    }

    // MARK: - Advanced Controls

    private var brightnessSlider: some View {
        sliderRow(
            label: String(localized: "Brightness"),
            icon: "sun.max",
            value: $settings.brightness,
            range: 0...1,
            leftLabel: String(localized: "Warm"),
            rightLabel: String(localized: "Bright"),
            tooltip: String(localized: "Tonal brightness: warm (darker) to bright (more overtones). Controls MIDI CC74 filter cutoff."),
            onChange: saveAndApply
        )
    }

    private var attackSlider: some View {
        sliderRow(
            label: String(localized: "Attack"),
            icon: "waveform.badge.plus",
            value: $settings.attack,
            range: 0.001...0.5,
            leftLabel: String(localized: "Fast"),
            rightLabel: String(localized: "Slow"),
            tooltip: String(localized: "Attack time: how quickly the sound reaches full volume. Fast = percussive, Slow = pad-like."),
            onChange: saveAndApply
        )
    }

    private var decaySlider: some View {
        sliderRow(
            label: String(localized: "Decay"),
            icon: "waveform.badge.minus",
            value: $settings.decay,
            range: 0.01...1.0,
            tooltip: String(localized: "Decay time: how quickly the sound falls from peak to sustain level."),
            onChange: saveAndApply
        )
    }

    private var sustainSlider: some View {
        sliderRow(
            label: String(localized: "Sustain"),
            icon: "waveform",
            value: $settings.sustain,
            range: 0...1,
            tooltip: String(localized: "Sustain level: volume maintained while the note is held (0–100%)."),
            onChange: saveAndApply
        )
    }

    private var releaseSlider: some View {
        sliderRow(
            label: String(localized: "Release"),
            icon: "waveform.path.ecg",
            value: $settings.release,
            range: 0.01...2.0,
            leftLabel: String(localized: "Short"),
            rightLabel: String(localized: "Long"),
            tooltip: String(localized: "Release time: how quickly the sound fades after the note ends. Short = staccato, Long = resonant."),
            onChange: saveAndApply
        )
    }

    // MARK: - Instrument-Specific Controls

    @ViewBuilder
    private var instrumentSpecificControls: some View {
        switch instrument.group {
        case .keyboards:
            sliderRow(
                label: String(localized: "Hammer Hardness"),
                icon: "hammer",
                value: Binding(
                    get: { settings.brightness * 0.8 + 0.1 },
                    set: { settings.brightness = ($0 - 0.1) / 0.8; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Soft"),
                rightLabel: String(localized: "Hard"),
                tooltip: String(localized: "Piano hammer hardness: soft = mellow tone, hard = bright percussive attack."),
                onChange: {}
            )
            sliderRow(
                label: String(localized: "Pedal Resonance"),
                icon: "waveform.circle",
                value: Binding(
                    get: { settings.reverb * 0.5 },
                    set: { settings.reverb = $0 / 0.5; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Dry"),
                rightLabel: String(localized: "Rich"),
                tooltip: String(localized: "Sustain pedal resonance: simulates sympathetic string vibration."),
                onChange: {}
            )
            Picker(String(localized: "Lid Position"), selection: Binding(
                get: { Int(settings.brightness * 2) },
                set: { settings.brightness = Float($0) / 2.0; saveAndApply() }
            )) {
                Text(String(localized: "Closed")).tag(0)
                Text(String(localized: "Half Open")).tag(1)
                Text(String(localized: "Full Open")).tag(2)
            }
            .pickerStyle(.segmented)
            .help(String(localized: "Grand piano lid position affects brightness and projection."))

        case .strings:
            sliderRow(
                label: String(localized: "Vibrato Speed"),
                icon: "waveform.path",
                value: Binding(
                    get: { settings.attack * 2 },
                    set: { settings.attack = $0 / 2; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Slow"),
                rightLabel: String(localized: "Fast"),
                tooltip: String(localized: "Vibrato oscillation speed: slow = expressive, fast = tense."),
                onChange: {}
            )
            sliderRow(
                label: String(localized: "Vibrato Depth"),
                icon: "waveform.badge.magnifyingglass",
                value: Binding(
                    get: { settings.sustain },
                    set: { settings.sustain = $0; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Subtle"),
                rightLabel: String(localized: "Wide"),
                tooltip: String(localized: "Vibrato pitch deviation: subtle = barely noticeable, wide = dramatic."),
                onChange: {}
            )
            Picker(String(localized: "Bow Type"), selection: Binding(
                get: { settings.brightness > 0.5 ? 1 : 0 },
                set: { settings.brightness = $0 == 1 ? 0.7 : 0.3; saveAndApply() }
            )) {
                Text(String(localized: "Standard")).tag(0)
                Text(String(localized: "Baroque")).tag(1)
            }
            .pickerStyle(.segmented)
            .help(String(localized: "Bow style: standard (modern) or baroque (lighter, more articulate)."))

        case .woodwinds:
            sliderRow(
                label: String(localized: "Air Amount"),
                icon: "wind",
                value: Binding(
                    get: { settings.sustain },
                    set: { settings.sustain = $0; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Less"),
                rightLabel: String(localized: "More"),
                tooltip: String(localized: "Breath intensity: affects fullness and presence of the wind sound."),
                onChange: {}
            )
            sliderRow(
                label: String(localized: "Tone Brightness"),
                icon: "sun.max",
                value: Binding(
                    get: { settings.brightness },
                    set: { settings.brightness = $0; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Dark"),
                rightLabel: String(localized: "Bright"),
                tooltip: String(localized: "Tonal quality: dark = hollow sound, bright = focused projection."),
                onChange: {}
            )

        case .brass:
            Picker(String(localized: "Mute Type"), selection: Binding(
                get: { Int(settings.brightness * 4) },
                set: { settings.brightness = Float($0) / 4.0; saveAndApply() }
            )) {
                Text(String(localized: "Open")).tag(0)
                Text(String(localized: "Straight")).tag(1)
                Text(String(localized: "Cup")).tag(2)
                Text(String(localized: "Harmon")).tag(3)
                Text(String(localized: "Plunger")).tag(4)
            }
            .pickerStyle(.menu)
            .help(String(localized: "Brass mute: Open = full sound, Straight = nasal, Cup = muted, Harmon = wah-wah, Plunger = comic."))

            sliderRow(
                label: String(localized: "Tone Brightness"),
                icon: "sun.max",
                value: Binding(
                    get: { settings.brightness },
                    set: { settings.brightness = $0; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Mellow"),
                rightLabel: String(localized: "Brilliant"),
                tooltip: String(localized: "Embouchure brightness: mellow = relaxed, brilliant = punchy."),
                onChange: {}
            )

        case .voices:
            Picker(String(localized: "Vowel"), selection: Binding(
                get: { Int(settings.brightness * 4) },
                set: { settings.brightness = Float($0) / 4.0; saveAndApply() }
            )) {
                Text("A (ah)").tag(0)
                Text("E (eh)").tag(1)
                Text("I (ee)").tag(2)
                Text("O (oh)").tag(3)
                Text("U (oo)").tag(4)
            }
            .pickerStyle(.segmented)
            .help(String(localized: "Sung vowel: affects the timbre and openness of the vocal sound."))

            sliderRow(
                label: String(localized: "Ensemble Width"),
                icon: "person.3",
                value: Binding(
                    get: { settings.pan * 0.5 + 0.5 },
                    set: { settings.pan = ($0 - 0.5) / 0.5; saveAndApply() }
                ),
                range: 0...1,
                leftLabel: String(localized: "Solo"),
                rightLabel: String(localized: "Section"),
                tooltip: String(localized: "Ensemble size: Solo = single voice, Section = choir of 20+ voices."),
                onChange: {}
            )

        case .percussion:
            Picker(String(localized: "Stick Type"), selection: Binding(
                get: { Int(settings.brightness * 2) },
                set: { settings.brightness = Float($0) / 2.0; saveAndApply() }
            )) {
                Text(String(localized: "Sticks")).tag(0)
                Text(String(localized: "Brushes")).tag(1)
                Text(String(localized: "Mallets")).tag(2)
            }
            .pickerStyle(.segmented)
            .help(String(localized: "Strike implement: Sticks = standard, Brushes = jazz, Mallets = orchestral."))

            sliderRow(
                label: String(localized: "Dampening"),
                icon: "hand.raised",
                value: Binding(
                    get: { settings.release },
                    set: { settings.release = $0; saveAndApply() }
                ),
                range: 0.01...2.0,
                leftLabel: String(localized: "Tight"),
                rightLabel: String(localized: "Ring"),
                tooltip: String(localized: "Dampening: Tight = muted immediately, Ring = natural resonance."),
                onChange: {}
            )
        }
    }

    // MARK: - SoundFont Picker

    private var soundFontPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = soundFontManager.activeSoundFont {
                HStack {
                    VStack(alignment: .leading) {
                        Text(active.name).font(.body)
                        Text(active.fileSizeString).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    sourceLabel(active.source)
                }
            }

            ForEach(soundFontManager.availableSoundFonts) { sf in
                Button {
                    soundFontManager.activeSoundFont = sf
                    MIDIEngine.shared.loadActiveSoundFont()
                } label: {
                    HStack {
                        Text(sf.name)
                        Spacer()
                        Text(sf.fileSizeString)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        sourceLabel(sf.source)
                        if sf == soundFontManager.activeSoundFont {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if sf.source == .userImported {
                        Button(role: .destructive) {
                            try? soundFontManager.deleteUserSoundFont(sf)
                            if soundFontManager.activeSoundFont == nil {
                                MIDIEngine.shared.loadActiveSoundFont()
                            }
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                showSF2Picker = true
            } label: {
                Label(String(localized: "Import SoundFont"), systemImage: "square.and.arrow.down")
            }
            .help(String(localized: "Import a .sf2 SoundFont file from Files app. Quality SF2 files are 10-30 MB."))
            .sheet(isPresented: $showSF2Picker) {
                SoundFontDocumentPicker { url in
                    do {
                        let info = try soundFontManager.importSoundFont(from: url)
                        soundFontManager.activeSoundFont = info
                        MIDIEngine.shared.loadActiveSoundFont()
                        HapticManager.success()
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }

            if let error = importError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func saveAndApply() {
        soundFontManager.updateSettings(for: instrumentId, settings)
        MIDIEngine.shared.applySettings(settings)
    }

    private func sliderRow(
        label: String,
        icon: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        leftLabel: String? = nil,
        rightLabel: String? = nil,
        tooltip: String? = nil,
        onChange: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 4) {
                if let left = leftLabel {
                    Text(left).font(.caption2).foregroundStyle(.tertiary)
                }
                Slider(value: value, in: range) { _ in onChange() }
                if let right = rightLabel {
                    Text(right).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .help(tooltip ?? label)
    }

    private func sourceLabel(_ source: SoundFontManager.SoundFontSource) -> some View {
        Text({
            switch source {
            case .builtIn: return String(localized: "Built-in")
            case .bundledPlugin: return String(localized: "Plugin")
            case .userImported: return String(localized: "Custom")
            }
        }())
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }

    private func localizedPresetName(_ name: String) -> String {
        switch name {
        case "Warm": return String(localized: "Warm")
        case "Bright": return String(localized: "Bright")
        case "Classical": return String(localized: "Classical")
        case "Soft": return String(localized: "Soft")
        default: return name
        }
    }
}

// MARK: - SoundFont Document Picker

struct SoundFontDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let sf2Type = UTType(filenameExtension: "sf2") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [sf2Type])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
