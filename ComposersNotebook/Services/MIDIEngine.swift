import AVFoundation
import AudioToolbox

// MARK: - MIDI Engine

@MainActor
class MIDIEngine: ObservableObject {
    static let shared = MIDIEngine()

    private var audioEngine: AVAudioEngine
    private var sampler: AVAudioUnitSampler
    private var reverbNode: AVAudioUnitReverb
    private var eqNode: AVAudioUnitEQ
    @Published var isPlaying = false
    @Published var isSoundFontLoaded = false

    private var playbackTask: Task<Void, Never>?

    init() {
        audioEngine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        reverbNode = AVAudioUnitReverb()
        eqNode = AVAudioUnitEQ(numberOfBands: 3)

        // Audio chain: sampler -> EQ -> reverb -> mixer
        audioEngine.attach(sampler)
        audioEngine.attach(eqNode)
        audioEngine.attach(reverbNode)

        audioEngine.connect(sampler, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: nil)

        // Default reverb
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 30

        // Default EQ bands: low, mid, high
        if eqNode.bands.count >= 3 {
            eqNode.bands[0].filterType = .lowShelf
            eqNode.bands[0].frequency = 200
            eqNode.bands[0].gain = 0
            eqNode.bands[0].bypass = false

            eqNode.bands[1].filterType = .parametric
            eqNode.bands[1].frequency = 1000
            eqNode.bands[1].gain = 0
            eqNode.bands[1].bypass = false

            eqNode.bands[2].filterType = .highShelf
            eqNode.bands[2].frequency = 5000
            eqNode.bands[2].gain = 0
            eqNode.bands[2].bypass = false
        }

        do {
            try audioEngine.start()
        } catch {
            print("MIDI Engine ошибка запуска: \(error)")
        }

        setupAudioSession()
        loadActiveSoundFont()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio Session ошибка: \(error)")
        }
    }

    // MARK: - SoundFont Loading

    /// Load SoundFont file into sampler
    func loadSoundFont(at url: URL, program: UInt8 = 0) {
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            isSoundFontLoaded = true
        } catch {
            print("SoundFont загрузка ошибка: \(error)")
            isSoundFontLoaded = false
        }
    }

    /// Load active SoundFont from SoundFontManager, or fallback to bundled TimGM6mb.sf2
    func loadActiveSoundFont() {
        if let sf = SoundFontManager.shared.activeSoundFont {
            loadSoundFont(at: sf.url)
            return
        }
        // Fallback: load bundled GM SoundFont
        if let bundledURL = Bundle.main.url(forResource: "TimGM6mb", withExtension: "sf2") {
            loadSoundFont(at: bundledURL)
        }
    }

    // MARK: - Sound Settings

    /// Apply instrument settings (volume, pan, reverb, EQ, ADSR via MIDI CC)
    func applySettings(_ settings: SoundFontManager.InstrumentSettings) {
        sampler.volume = settings.volume
        sampler.pan = settings.pan
        reverbNode.wetDryMix = settings.reverb * 100

        // Brightness via high shelf EQ
        if eqNode.bands.count >= 3 {
            let brightnessGain = (settings.brightness - 0.5) * 12 // -6dB to +6dB
            eqNode.bands[2].gain = brightnessGain
        }

        // ADSR via MIDI CC (standard controllers)
        // CC 73 = Attack Time, CC 75 = Decay Time, CC 70 = Sound Variation (sustain level), CC 72 = Release Time
        let attackCC = UInt8(clamping: Int(settings.attack * 127 / 2.0))  // 0..2s -> 0..127
        let decayCC = UInt8(clamping: Int(settings.decay * 127 / 2.0))
        let sustainCC = UInt8(clamping: Int(settings.sustain * 127))
        let releaseCC = UInt8(clamping: Int(settings.release * 127 / 2.0))

        sampler.sendController(73, withValue: attackCC, onChannel: 0)   // Attack
        sampler.sendController(75, withValue: decayCC, onChannel: 0)    // Decay
        sampler.sendController(70, withValue: sustainCC, onChannel: 0)  // Sound Variation / Sustain level
        sampler.sendController(72, withValue: releaseCC, onChannel: 0)  // Release

        // CC 74 = Brightness (Filter Cutoff) — more direct than EQ
        let brightnessCC = UInt8(clamping: Int(settings.brightness * 127))
        sampler.sendController(74, withValue: brightnessCC, onChannel: 0)

        // CC 91 = Reverb Send Level
        let reverbCC = UInt8(clamping: Int(settings.reverb * 127))
        sampler.sendController(91, withValue: reverbCC, onChannel: 0)

        // CC 10 = Pan
        let panCC = UInt8(clamping: Int((settings.pan + 1.0) / 2.0 * 127))
        sampler.sendController(10, withValue: panCC, onChannel: 0)

        // CC 7 = Volume
        let volumeCC = UInt8(clamping: Int(settings.volume * 127))
        sampler.sendController(7, withValue: volumeCC, onChannel: 0)

        // CC 1 = Modulation (vibrato) — reuse attack field for strings
        let modCC = UInt8(clamping: Int(settings.attack * 127 / 2.0))
        sampler.sendController(1, withValue: modCC, onChannel: 0)
    }

    /// Apply settings for a specific instrument during playback
    func applySettingsForInstrument(_ instrument: Instrument) {
        let settings = SoundFontManager.shared.settings(for: instrument.id.uuidString)
        applySettings(settings)
    }

    /// Preview sound with current settings (plays a short note)
    func previewSound(pitch: Pitch = Pitch(name: .C, octave: 4), midiProgram: Int = 0) {
        playNote(pitch: pitch, velocity: 80, duration: 0.5, midiProgram: midiProgram)
    }

    // MARK: - Set Instrument

    func setInstrument(midiProgram: Int, channel: UInt8 = 0) {
        if isSoundFontLoaded {
            // When SoundFont is loaded, switch program within it
            sampler.sendProgramChange(UInt8(midiProgram), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                      bankLSB: 0, onChannel: channel)
        } else {
            // Fallback to default General MIDI
            sampler.sendProgramChange(UInt8(midiProgram), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                      bankLSB: UInt8(kAUSampler_DefaultBankLSB), onChannel: channel)
        }
    }

    // MARK: - Play Single Note (for input feedback)

    func playNote(pitch: Pitch, velocity: Int = 80, duration: Double = 0.3, midiProgram: Int = 0) {
        setInstrument(midiProgram: midiProgram)
        let note = UInt8(clamping: pitch.midiNote)
        let vel = UInt8(clamping: velocity)

        sampler.startNote(note, withVelocity: vel, onChannel: 0)

        Task {
            try? await Task.sleep(for: .seconds(duration))
            sampler.stopNote(note, onChannel: 0)
        }
    }

    // MARK: - Play Score

    func playScore(_ score: Score, fromMeasure: Int = 0) {
        stop()
        isPlaying = true

        playbackTask = Task { @MainActor in
            let baseBPM = score.tempo.bpm

            for measureIndex in fromMeasure..<score.measureCount {
                guard isPlaying else { break }

                // Determine current tempo (check for tempo changes)
                var currentBPM = baseBPM
                for part in score.parts {
                    if let tempo = part.measures[measureIndex].tempoMarking {
                        currentBPM = tempo.bpm
                    }
                }
                let secPerBeat = 60.0 / currentBPM

                // Collect all events across parts for this measure
                for part in score.parts {
                    guard measureIndex < part.measures.count else { continue }
                    let measure = part.measures[measureIndex]

                    Task {
                        setInstrument(midiProgram: part.instrument.midiProgram)
                        applySettingsForInstrument(part.instrument)

                        for event in measure.events {
                            guard isPlaying else { return }

                            let durationSec = event.duration.beats * secPerBeat

                            switch event.type {
                            case .note(let pitch):
                                let note = UInt8(clamping: pitch.midiNote)
                                let vel = UInt8(clamping: event.velocity)
                                sampler.startNote(note, withVelocity: vel, onChannel: 0)
                                try? await Task.sleep(for: .seconds(durationSec))
                                if !event.tiedToNext {
                                    sampler.stopNote(note, onChannel: 0)
                                }

                            case .chord(let pitches):
                                let vel = UInt8(clamping: event.velocity)
                                for p in pitches {
                                    sampler.startNote(UInt8(clamping: p.midiNote), withVelocity: vel, onChannel: 0)
                                }
                                try? await Task.sleep(for: .seconds(durationSec))
                                if !event.tiedToNext {
                                    for p in pitches {
                                        sampler.stopNote(UInt8(clamping: p.midiNote), onChannel: 0)
                                    }
                                }

                            case .rest:
                                try? await Task.sleep(for: .seconds(durationSec))
                            }
                        }
                    }

                    // Wait for the full measure duration
                    let ts = measure.timeSignature ?? score.timeSignature
                    let measureDuration = ts.totalBeats * secPerBeat
                    try? await Task.sleep(for: .seconds(measureDuration))
                }
            }

            isPlaying = false
        }
    }

    // MARK: - Play Single Part

    func playPart(_ part: Part, score: Score, fromMeasure: Int = 0) {
        stop()
        isPlaying = true

        playbackTask = Task { @MainActor in
            setInstrument(midiProgram: part.instrument.midiProgram)
            applySettingsForInstrument(part.instrument)
            let bpm = score.tempo.bpm

            for measureIndex in fromMeasure..<part.measures.count {
                guard isPlaying else { break }
                let measure = part.measures[measureIndex]

                var currentBPM = bpm
                if let tempo = measure.tempoMarking {
                    currentBPM = tempo.bpm
                }
                let secPerBeat = 60.0 / currentBPM

                for event in measure.events {
                    guard isPlaying else { break }
                    let durationSec = event.duration.beats * secPerBeat

                    switch event.type {
                    case .note(let pitch):
                        let note = UInt8(clamping: pitch.midiNote)
                        sampler.startNote(note, withVelocity: UInt8(clamping: event.velocity), onChannel: 0)
                        try? await Task.sleep(for: .seconds(durationSec))
                        if !event.tiedToNext {
                            sampler.stopNote(note, onChannel: 0)
                        }

                    case .chord(let pitches):
                        for p in pitches {
                            sampler.startNote(UInt8(clamping: p.midiNote), withVelocity: UInt8(clamping: event.velocity), onChannel: 0)
                        }
                        try? await Task.sleep(for: .seconds(durationSec))
                        if !event.tiedToNext {
                            for p in pitches {
                                sampler.stopNote(UInt8(clamping: p.midiNote), onChannel: 0)
                            }
                        }

                    case .rest:
                        try? await Task.sleep(for: .seconds(durationSec))
                    }
                }
            }

            isPlaying = false
        }
    }

    // MARK: - Pause

    @Published var isPaused = false
    private var pausedMeasureIndex: Int?

    func pause() {
        isPaused = true
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
        }
    }

    func resume(score: Score, fromMeasure: Int) {
        isPaused = false
        playScore(score, fromMeasure: fromMeasure)
    }

    // MARK: - Stop

    func stop() {
        isPlaying = false
        isPaused = false
        playbackTask?.cancel()
        playbackTask = nil
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
        }
    }
}
