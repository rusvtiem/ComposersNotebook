import AVFoundation
import AudioToolbox

// MARK: - MIDI Engine

@MainActor
class MIDIEngine: ObservableObject {
    static let shared = MIDIEngine()

    private var audioEngine: AVAudioEngine
    private var sampler: AVAudioUnitSampler
    @Published var isPlaying = false

    private var playbackTask: Task<Void, Never>?

    init() {
        audioEngine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        audioEngine.attach(sampler)
        audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format: nil)

        do {
            try audioEngine.start()
        } catch {
            print("MIDI Engine ошибка запуска: \(error)")
        }

        setupAudioSession()
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

    // MARK: - Set Instrument

    func setInstrument(midiProgram: Int, channel: UInt8 = 0) {
        sampler.sendProgramChange(UInt8(midiProgram), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                  bankLSB: UInt8(kAUSampler_DefaultBankLSB), onChannel: channel)
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
