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

    /// Drives the on-screen playback cursor (the moving vertical line that sweeps
    /// the score during Play). `playbackStartDate` is when the current playback
    /// began; `playbackProgress` maps elapsed time to a measure+fraction. Both are
    /// set when `playScore` starts and cleared on stop/pause, so the cursor shows
    /// only while sound is actually playing.
    @Published var playbackStartDate: Date?
    @Published var playbackProgress: PlaybackProgress?

    /// URL активного SoundFont — нужен чтобы перегружать конкретный пресет (program)
    /// из того же банка при смене инструмента. Без него setInstrument не мог сменить
    /// пресет ни на что кроме пиано.
    private var currentSoundFontURL: URL?
    /// Пресет (program), реально загруженный в sampler сейчас. Кэш, чтобы не
    /// перегружать банк на каждую ноту/каждую смену партии впустую.
    private var loadedProgram: UInt8 = 0

    private var playbackTask: Task<Void, Never>?

    init() {
        audioEngine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        reverbNode = AVAudioUnitReverb()
        eqNode = AVAudioUnitEQ(numberOfBands: 3)

        wireAudioGraph()
        // Порядок критичен: сначала активируем .playback-сессию, потом стартуем
        // движок. Если запустить движок под дефолтной (ambient) сессией, на
        // устройстве в беззвучном режиме звука не будет — .playback игнорирует
        // mute-переключатель, ambient его уважает. Раньше setupAudioSession() шёл
        // ПОСЛЕ startEngine() → тишина в silent-mode.
        setupAudioSession()
        startEngine()
        loadActiveSoundFont()
        subscribeToSoundFontChanges()
        subscribeToAudioInterruptions()
    }

    /// Attach + connect nodes и выставить дефолтные пресеты reverb/EQ на текущих
    /// `audioEngine`/`sampler`/`eqNode`/`reverbNode`. Вынесено из init, чтобы
    /// `rebuildAudioGraph()` мог пересобрать граф после mediaServicesWereReset.
    private func wireAudioGraph() {
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
    }

    private func startEngine() {
        do {
            try audioEngine.start()
        } catch {
            print("MIDI Engine ошибка запуска: \(error)")
        }
    }

    /// Guarantee the engine is running before a note is triggered. AVAudioEngine can
    /// suspend itself after an interruption, a route change, or media-services reset;
    /// `startNote` on a stopped engine is silent. Re-activating the session and
    /// starting the engine on demand keeps input feedback and playback audible without
    /// waiting for the notification handlers to fire. (Fixes the "no sound" class.)
    private func ensureEngineRunning() {
        guard !audioEngine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngine()
    }

    /// Подписка на смену активного SoundFont (через NotificationCenter).
    /// Когда пользователь меняет SF — sampler перезагружается на лету.
    private func subscribeToSoundFontChanges() {
        NotificationCenter.default.addObserver(
            forName: .activeSoundFontDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadActiveSoundFont()
            }
        }
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

    /// Прерывания аудио (звонок, Siri, будильник) и сброс медиасервера.
    /// Без этого после телефонного звонка ноты «висят», а движок остаётся
    /// остановленным — звук пропадает навсегда до перезапуска приложения.
    private func subscribeToAudioInterruptions() {
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
        nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMediaServicesReset() }
        }
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        }
    }

    /// Смена аудио-маршрута (выдернули наушники / отключился Bluetooth).
    /// По гайдлайну Apple при пропаже прежнего устройства вывода воспроизведение
    /// нужно ставить на паузу, а не гнать звук внезапно в динамик; заодно
    /// поднимаем движок, если система его усыпила при переключении маршрута.
    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            stop()
        case .newDeviceAvailable, .categoryChange, .override:
            if !audioEngine.isRunning { startEngine() }
        default:
            break
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            // Система остановила движок. Гасим плейбек и ноты, иначе по возврату
            // из звонка они звучат мусором.
            stop()
        case .ended:
            // Реактивируем сессию и движок; без этого звук не вернётся.
            try? AVAudioSession.sharedInstance().setActive(true)
            if !audioEngine.isRunning { startEngine() }
        @unknown default:
            break
        }
    }

    private func handleMediaServicesReset() {
        // Media server рухнул: sampler и весь граф инвалидны. Пересобираем с нуля —
        // иначе движок молчит навсегда (Директива №0: авто-восстановление).
        stop()
        isSoundFontLoaded = false
        rebuildAudioGraph()
    }

    private func rebuildAudioGraph() {
        audioEngine.stop()
        audioEngine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        eqNode = AVAudioUnitEQ(numberOfBands: 3)
        reverbNode = AVAudioUnitReverb()
        wireAudioGraph()
        setupAudioSession()   // сессия ДО старта движка (см. init)
        startEngine()
        loadActiveSoundFont()
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
            currentSoundFontURL = url
            loadedProgram = program
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
            // Активный SF мог быть удалён/битым (loadSoundFont поймал ошибку и
            // оставил isSoundFontLoaded=false). Раньше в этом случае fallback не
            // срабатывал → тишина навсегда. Теперь падаем на встроенный GM.
            if isSoundFontLoaded { return }
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

        // 3-band EQ
        if eqNode.bands.count >= 3 {
            eqNode.bands[0].gain = settings.eqLow
            eqNode.bands[1].gain = settings.eqMid
            let brightnessGain = (settings.brightness - 0.5) * 12
            eqNode.bands[2].gain = settings.eqHigh + brightnessGain
        }

        // ADSR via MIDI CC (стандартные Sound Controllers SC2–SC6)
        // CC 73 = Attack Time, CC 75 = Decay Time, CC 72 = Release Time.
        // ВНИМАНИЕ: «уровня сустейна» стандартного CC НЕ существует. CC70 — это
        // Sound Variation (SC1), а не sustain level; отправка sustain*127 в CC70
        // на части SF2-банков переключает тембр/занижает выход (кандидат в «тихо/
        // нет звука»). Убрано — уровень сустейна берётся из огибающей самого SF2
        // (профессиональное поведение). [проверить на устройстве: громкость/тембр]
        let attackCC = UInt8(clamping: Int(settings.attack * 127 / 2.0))  // 0..2s -> 0..127
        let decayCC = UInt8(clamping: Int(settings.decay * 127 / 2.0))
        let releaseCC = UInt8(clamping: Int(settings.release * 127 / 2.0))

        sampler.sendController(73, withValue: attackCC, onChannel: 0)   // Attack
        sampler.sendController(75, withValue: decayCC, onChannel: 0)    // Decay
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
        let program = UInt8(clamping: midiProgram)
        guard program != loadedProgram else { return }   // уже нужный пресет — не трогаем

        if isSoundFontLoaded, let url = currentSoundFontURL {
            // КОРЕНЬ бага «нет звука для не-пиано»: sendProgramChange на
            // AVAudioUnitSampler переключает пресет ТОЛЬКО если он уже присутствует в
            // загруженном банке. loadSoundBankInstrument грузит из SF2 ровно один
            // program за раз (при загрузке SF это был program 0 = пиано). Значит для
            // любого инструмента != пиано канал оставался на несуществующем пресете
            // → note-on в пустоту → тишина. Грузим нужный пресет из того же SF2.
            do {
                try sampler.loadSoundBankInstrument(at: url, program: program,
                    bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
                loadedProgram = program
            } catch {
                // В этом SF2 нет такого пресета — откат на GM Grand Piano (program 0),
                // чтобы всегда был звук, а не тишина (эталон MuseScore §4: fallback).
                if loadedProgram != 0 {
                    try? sampler.loadSoundBankInstrument(at: url, program: 0,
                        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
                    loadedProgram = 0
                }
            }
        } else {
            // SoundFont не загружен — пробуем General MIDI напрямую.
            sampler.sendProgramChange(program, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                      bankLSB: UInt8(kAUSampler_DefaultBankLSB), onChannel: channel)
            loadedProgram = program
        }
    }

    // MARK: - Play Single Note (for input feedback)

    func playNote(pitch: Pitch, velocity: Int = 80, duration: Double = 0.3, midiProgram: Int = 0) {
        ensureEngineRunning()
        setInstrument(midiProgram: midiProgram)
        let note = UInt8(clamping: pitch.midiNote)
        let vel = UInt8(clamping: velocity)

        sampler.startNote(note, withVelocity: vel, onChannel: 0)

        Task {
            try? await Task.sleep(for: .seconds(duration))
            sampler.stopNote(note, onChannel: 0)
        }
    }

    // MARK: - Play Score (expanded: repeats, voltas, D.S./D.C./Coda, tempo changes, hairpins, octave shifts, tuplets)

    /// Полный плейбек партитуры через PlaybackScheduler.
    /// Развёрнуто учитывает повторы, voltas, D.S./D.C./Coda, accel/rit,
    /// hairpins (интерполяция velocity), octave shifts, tuplet timing.
    func playScoreExpanded(_ score: Score) {
        stop()
        ensureEngineRunning()
        isPlaying = true

        let plan = PlaybackScheduler.expand(score: score)
        guard !plan.isEmpty else { isPlaying = false; return }

        // Загружаем инструменты партий заранее
        var partProgramByIndex: [Int: Int] = [:]
        for (idx, part) in score.parts.enumerated() {
            partProgramByIndex[idx] = part.effectiveMidiProgram
            applySettingsForInstrument(part.instrument)
        }

        // Группируем по startBeat — все ноты с одним startBeat играем одновременно
        playbackTask = Task { @MainActor in
            var lastBeat: Double = 0
            for ev in plan {
                guard isPlaying else { break }

                let beatGap = ev.startBeat - lastBeat
                if beatGap > 0 {
                    let secGap = beatGap * (60.0 / ev.bpmAtStart)
                    try? await Task.sleep(for: .seconds(secGap))
                }
                lastBeat = ev.startBeat

                // Переключаем инструмент партии если изменился
                if let prog = partProgramByIndex[ev.partIndex] {
                    setInstrument(midiProgram: prog)
                }

                let note = UInt8(clamping: ev.midiNote)
                let vel = UInt8(clamping: ev.velocity)
                sampler.startNote(note, withVelocity: vel, onChannel: 0)

                let durSec = ev.durationBeats * (60.0 / ev.bpmAtStart)
                let noteEnd = ev.tiedToNext ? nil : Task {
                    try? await Task.sleep(for: .seconds(durSec))
                    if !Task.isCancelled {
                        await MainActor.run { self.sampler.stopNote(note, onChannel: 0) }
                    }
                }
                _ = noteEnd
            }
            isPlaying = false
        }
    }

    // MARK: - Play Score (legacy: без раскрытия повторов)

    /// One note to sound during playback, timed by its absolute onset (seconds from
    /// the start instant) rather than a running sum of sleeps.
    struct ScheduledNote: Equatable {
        let onset: Double        // seconds from playback start
        let durationSec: Double  // sounding length
        let midi: UInt8
        let velocity: UInt8
        let program: Int
        let tied: Bool
    }

    /// Flatten the score into absolutely-timed notes. Resolves per-measure tempo and
    /// time signature exactly as `PlaybackProgress.build` does (same measure onsets),
    /// so a note's onset sits on the same timeline the on-screen cursor reads — the
    /// two can't drift apart. Each event's onset is its measure's onset plus its beat
    /// offset within the measure; grace notes (0 metric beats) sound but consume no
    /// grid time. Pure/static (nonisolated) so it's unit-testable without audio.
    nonisolated static func buildNoteSchedule(score: Score, fromMeasure: Int) -> [ScheduledNote] {
        let baseBPM = score.tempo.bpm
        let start = max(0, fromMeasure)
        guard start < score.measureCount else { return [] }
        var out: [ScheduledNote] = []
        var measureStart = 0.0
        for measureIndex in start..<score.measureCount {
            var currentBPM = baseBPM
            for part in score.parts where measureIndex < part.measures.count {
                if let tempo = part.measures[measureIndex].tempoMarking { currentBPM = tempo.bpm }
            }
            let secPerBeat = currentBPM > 0 ? 60.0 / currentBPM : 0.5

            var measureTimeSig = score.timeSignature
            for part in score.parts {
                let program = part.effectiveMidiProgram
                for staff in part.staves where measureIndex < staff.measures.count {
                    let measure = staff.measures[measureIndex]
                    if let ts = measure.timeSignature { measureTimeSig = ts }
                    var beatOffset = 0.0
                    for event in measure.events {
                        let onset = measureStart + beatOffset * secPerBeat
                        // Grace notes carry 0 metric beats — give them their written
                        // length so they still sound, but don't advance the grid.
                        let soundBeats = event.actualBeats > 0 ? event.actualBeats : event.duration.beats
                        let durSec = soundBeats * secPerBeat
                        switch event.type {
                        case .note(let pitch):
                            out.append(ScheduledNote(onset: onset, durationSec: durSec,
                                                     midi: UInt8(clamping: pitch.midiNote),
                                                     velocity: UInt8(clamping: event.velocity),
                                                     program: program, tied: event.tiedToNext))
                        case .chord(let pitches):
                            for p in pitches {
                                out.append(ScheduledNote(onset: onset, durationSec: durSec,
                                                         midi: UInt8(clamping: p.midiNote),
                                                         velocity: UInt8(clamping: event.velocity),
                                                         program: program, tied: event.tiedToNext))
                            }
                        case .rest:
                            break
                        }
                        beatOffset += max(0, event.actualBeats)
                    }
                }
            }
            measureStart += measureTimeSig.totalBeats * secPerBeat
        }
        return out
    }

    func playScore(_ score: Score, fromMeasure: Int = 0) {
        stop()
        ensureEngineRunning()
        isPlaying = true

        // Arm the on-screen playback cursor: schedule of measure onsets + the
        // start instant. The surface samples these each frame to place the line.
        let progress = PlaybackProgress.build(score: score, fromMeasure: fromMeasure)
        let startDate = Date()
        playbackProgress = progress
        playbackStartDate = startDate

        // Preload each part's instrument once, before any note fires.
        for part in score.parts { applySettingsForInstrument(part.instrument) }

        let schedule = MIDIEngine.buildNoteSchedule(score: score, fromMeasure: fromMeasure)
        guard !schedule.isEmpty else {
            // Nothing to sound (e.g. all rests) — still let the cursor sweep, then end.
            playbackTask = Task { @MainActor in
                let wait = startDate.addingTimeInterval(progress.totalDuration).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                isPlaying = false
                playbackStartDate = nil
                playbackProgress = nil
            }
            return
        }

        // Fire every note against the FIXED start instant. Because each onset is
        // measured from `startDate` (not a running sum), scheduling latency on one
        // note never pushes the next — the sound stays locked to the wall clock the
        // cursor uses, instead of sliding progressively behind it.
        playbackTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for n in schedule {
                    group.addTask { @MainActor [weak self] in
                        guard let self else { return }
                        let wait = startDate.addingTimeInterval(n.onset).timeIntervalSinceNow
                        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                        guard self.isPlaying, !Task.isCancelled else { return }
                        self.setInstrument(midiProgram: n.program)
                        self.sampler.startNote(n.midi, withVelocity: n.velocity, onChannel: 0)
                        if !n.tied {
                            try? await Task.sleep(for: .seconds(n.durationSec))
                            if self.isPlaying { self.sampler.stopNote(n.midi, onChannel: 0) }
                        }
                    }
                }
                // Hold until the last measure's end so the cursor completes its sweep.
                group.addTask { @MainActor [weak self] in
                    let wait = startDate.addingTimeInterval(progress.totalDuration).timeIntervalSinceNow
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    _ = self
                }
            }
            isPlaying = false
            playbackStartDate = nil
            playbackProgress = nil
        }
    }

    // MARK: - Play Single Part

    func playPart(_ part: Part, score: Score, fromMeasure: Int = 0) {
        stop()
        isPlaying = true

        playbackTask = Task { @MainActor in
            setInstrument(midiProgram: part.effectiveMidiProgram)
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
        playbackStartDate = nil
        playbackProgress = nil
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
        playbackStartDate = nil
        playbackProgress = nil
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
        }
    }
}
