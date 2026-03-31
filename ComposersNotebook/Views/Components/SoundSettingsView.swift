import SwiftUI

// MARK: - Sound Settings View
// Two-level sound settings: Simple (default) + Advanced (expandable)

struct SoundSettingsView: View {
    @ObservedObject var soundFontManager: SoundFontManager
    let instrument: Instrument
    let onPreview: () -> Void

    @State private var settings: SoundFontManager.InstrumentSettings
    @State private var showAdvanced = false
    @State private var showSavePreset = false
    @State private var newPresetName = ""

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
                // MARK: - Simple Level (always visible)
                Section {
                    presetPicker
                    volumeSlider
                    panSlider
                    reverbSlider
                } header: {
                    Label(instrument.name, systemImage: "music.note")
                }

                // MARK: - Advanced Level (expandable)
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
                        brightnessSlider
                        attackSlider
                        decaySlider
                        sustainSlider
                        releaseSlider
                        instrumentSpecificControls
                    }
                } header: {
                    Text(String(localized: "Sound Character"))
                }

                // MARK: - SoundFont Selection
                Section {
                    soundFontPicker
                } header: {
                    Text(String(localized: "Sound Source"))
                }

                // MARK: - Actions
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

                // MARK: - User Presets
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
                                            .foregroundStyle(.accent)
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
            onChange: saveAndApply
        )
    }

    private var decaySlider: some View {
        sliderRow(
            label: String(localized: "Decay"),
            icon: "waveform.badge.minus",
            value: $settings.decay,
            range: 0.01...1.0,
            onChange: saveAndApply
        )
    }

    private var sustainSlider: some View {
        sliderRow(
            label: String(localized: "Sustain"),
            icon: "waveform",
            value: $settings.sustain,
            range: 0...1,
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
            onChange: saveAndApply
        )
    }

    // MARK: - Instrument-Specific Controls

    @ViewBuilder
    private var instrumentSpecificControls: some View {
        switch instrument.group {
        case .keyboards:
            Text(String(localized: "Piano-specific settings"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Future: hammer hardness, pedal resonance, lid position

        case .strings:
            Text(String(localized: "String-specific settings"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Future: bow type, vibrato speed/depth

        case .woodwinds:
            Text(String(localized: "Woodwind-specific settings"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Future: air amount, brightness

        case .brass:
            Text(String(localized: "Brass-specific settings"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Future: mute type, brightness

        case .voices:
            Text(String(localized: "Voice-specific settings"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Future: vowel, ensemble width

        case .percussion:
            Text(String(localized: "Percussion-specific settings"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Future: stick type, dampening
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

            if soundFontManager.availableSoundFonts.count > 1 {
                ForEach(soundFontManager.availableSoundFonts) { sf in
                    Button {
                        soundFontManager.activeSoundFont = sf
                    } label: {
                        HStack {
                            Text(sf.name)
                            Spacer()
                            sourceLabel(sf.source)
                            if sf == soundFontManager.activeSoundFont {
                                Image(systemName: "checkmark").foregroundStyle(.accent)
                            }
                        }
                    }
                }
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

// MARK: - InstrumentGroup rawValue for persistence

extension InstrumentGroup: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "woodwinds": self = .woodwinds
        case "brass": self = .brass
        case "percussion": self = .percussion
        case "strings": self = .strings
        case "keyboards": self = .keyboards
        case "voices": self = .voices
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .woodwinds: return "woodwinds"
        case .brass: return "brass"
        case .percussion: return "percussion"
        case .strings: return "strings"
        case .keyboards: return "keyboards"
        case .voices: return "voices"
        }
    }
}
