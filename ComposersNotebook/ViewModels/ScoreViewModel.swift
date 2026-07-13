import SwiftUI
import Combine

// MARK: - Input Mode

enum InputMode: Equatable {
    case navigate  // Default: tap = select measure, scroll freely
    case note      // Tap = insert note at pitch
    case rest      // Tap = insert rest with selected duration
}

// MARK: - Score View Model

@MainActor
class ScoreViewModel: ObservableObject {
    // Score data
    @Published var score: Score
    @Published var selectedPartIndex: Int = 0
    @Published var selectedStaffIndex: Int = 0  // 0 = treble (top), 1 = bass (bottom) for grand staff
    @Published var selectedMeasureIndex: Int = 0
    @Published var cursorPosition: Double = 0  // beat position within measure

    // Selection state
    @Published var selectedEventIndex: Int? = nil  // index of selected note in current measure
    @Published var selectedPitchIndex: Int? = nil   // index of selected pitch within chord

    // Input state
    @Published var inputMode: InputMode = .navigate
    @Published var selectedDuration: DurationValue = .quarter
    @Published var selectedAccidental: Accidental? = nil  // nil = без альтерации, .natural = явный бекар
    @Published var isDotted: Bool = false
    @Published var isDoubleDotted: Bool = false
    @Published var selectedArticulation: Articulation?
    @Published var selectedDynamic: DynamicMarking?
    @Published var tieNext: Bool = false
    @Published var slurActive: Bool = false
    @Published var stemDirection: StemDirection = .auto
    @Published var zoomScale: CGFloat = 1.0  // pinch-to-zoom

    // Voice layers
    @Published var selectedVoice: VoiceLayer = .voice1
    @Published var showAllVoices: Bool = true  // false = show only selectedVoice

    // Playback technique
    @Published var selectedTechnique: PlaybackTechnique? = nil

    // Lyrics
    @Published var isEditingLyric: Bool = false
    @Published var currentLyricText: String = ""

    // Playback
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Int = 0  // measure index
    let midiEngine = MIDIEngine.shared

    // Clipboard
    private var clipboard: [NoteEvent] = []
    @Published var hasClipboardContent: Bool = false

    // Undo/Redo
    private var undoStack: [Score] = []
    private var redoStack: [Score] = []
    private let maxUndoLevels = 50

    // Auto-save
    private var autoSaveTimer: Timer?
    private var autoSaveURL: URL?
    /// true, если текущее состояние партитуры уже сохранено в .cnb и с тех пор
    /// не редактировалось. Тогда черновик автосейва избыточен и чистится при закрытии.
    private var savedToCNB = false

    init(score: Score) {
        self.score = score
        setupAutoSave()
    }

    deinit {
        autoSaveTimer?.invalidate()
    }

    // MARK: - Current Part/Measure

    var currentPart: Part? {
        guard selectedPartIndex < score.parts.count else { return nil }
        return score.parts[selectedPartIndex]
    }

    var currentStaff: Staff? {
        guard let part = currentPart,
              selectedStaffIndex < part.staves.count else { return nil }
        return part.staves[selectedStaffIndex]
    }

    var currentMeasure: Measure? {
        guard let staff = currentStaff,
              selectedMeasureIndex < staff.measures.count else { return nil }
        return staff.measures[selectedMeasureIndex]
    }

    var effectiveTimeSignature: TimeSignature {
        guard let staff = currentStaff else { return score.timeSignature }
        for i in stride(from: selectedMeasureIndex, through: 0, by: -1) {
            if let ts = staff.measures[i].timeSignature {
                return ts
            }
        }
        return score.timeSignature
    }

    var effectiveKeySignature: KeySignature {
        guard let staff = currentStaff else { return score.keySignature }
        for i in stride(from: selectedMeasureIndex, through: 0, by: -1) {
            if let ks = staff.measures[i].keySignature {
                return ks
            }
        }
        return score.keySignature
    }

    var effectiveClef: Clef {
        guard let staff = currentStaff else { return .treble }
        for i in stride(from: selectedMeasureIndex, through: 0, by: -1) {
            if let clef = staff.measures[i].clefChange {
                return clef
            }
        }
        return staff.clef
    }

    // MARK: - Staff mapping (Verovio tap → model)

    /// Total staves across all parts, in render order. Verovio lays staves out in
    /// this same part-then-staff order, so a rendered staff's global index maps
    /// straight back through `partStaff(forFlattenedStaffIndex:)`.
    var totalStaffCount: Int {
        score.parts.reduce(0) { $0 + $1.staves.count }
    }

    /// Resolve a render-order flattened staff index (0 = part 0 / staff 0, then
    /// that part's next staff, then the next part) to concrete indices.
    func partStaff(forFlattenedStaffIndex index: Int) -> (part: Int, staff: Int)? {
        guard index >= 0 else { return nil }
        var remaining = index
        for (pi, part) in score.parts.enumerated() {
            if remaining < part.staves.count { return (pi, remaining) }
            remaining -= part.staves.count
        }
        return nil
    }

    /// Point the current selection at a specific part+staff (e.g. the staff a
    /// Verovio tap landed on), so `effectiveClef`/`effectiveKeySignature` read that
    /// staff. Safe against stale indices.
    func focusStaff(partIndex: Int, staffIndex: Int) {
        guard partIndex < score.parts.count,
              staffIndex < score.parts[partIndex].staves.count else { return }
        selectedPartIndex = partIndex
        selectedStaffIndex = staffIndex
        let measureCount = score.parts[partIndex].staves[staffIndex].measures.count
        if selectedMeasureIndex >= measureCount { selectedMeasureIndex = max(0, measureCount - 1) }
    }

    // MARK: - Note Input

    /// Insert a fresh note at the cursor from the Verovio editing surface, which
    /// resolves pitch from a tap on the engraving instead of the toolbar input
    /// mode. Bypasses the `inputMode` guard and deselects first so the tap adds a
    /// standalone note rather than extending the selected event into a chord.
    func insertNoteAtCursor(_ pitch: Pitch) {
        let previousMode = inputMode
        inputMode = .note
        selectedEventIndex = nil
        addNote(pitch: pitch)
        inputMode = previousMode
    }

    func addNote(pitch: Pitch) {
        guard inputMode == .note else { return }

        // Auto-select staff for grand staff instruments (split at middle C = C4)
        if let part = currentPart, part.isGrandStaff {
            let middleC = 60 // MIDI note for C4
            selectedStaffIndex = pitch.midiNote >= middleC ? 0 : 1
        }

        // If a note/chord is selected, add pitch to it (build chord)
        if selectedEventIndex != nil {
            addPitchToSelectedEvent(pitch)
            let midiProg = currentPart?.instrument.midiProgram ?? 0
            midiEngine.playNote(pitch: pitch, velocity: 80, duration: 0.3, midiProgram: midiProg)
            return
        }

        saveUndoState()

        let duration = makeDuration()
        var event = NoteEvent.note(pitch, duration: duration)
        event.stemDirection = stemDirection
        event.voice = selectedVoice
        event.technique = selectedTechnique
        if pitch.accidental == .natural && selectedAccidental == .natural {
            event.showNatural = true
        }

        if let articulation = selectedArticulation {
            event.articulations = [articulation]
        }
        if let dynamic = selectedDynamic {
            event.dynamic = dynamic
            selectedDynamic = nil  // dynamics apply once
        }
        if tieNext {
            event.tiedToNext = true
            tieNext = false
        }
        if slurActive {
            event.slurStart = true
        }

        insertEvent(event)

        // Sound feedback on input
        let midiProg = currentPart?.instrument.midiProgram ?? 0
        midiEngine.playNote(pitch: pitch, velocity: 80, duration: 0.3, midiProgram: midiProg)
    }

    func addRest() {
        guard inputMode == .rest else { return }
        saveUndoState()
        let duration = makeDuration()
        let event = NoteEvent.rest(duration: duration)
        insertEvent(event)
    }

    func addChord(pitches: [Pitch]) {
        guard !pitches.isEmpty else { return }
        saveUndoState()

        let duration = makeDuration()
        var event = NoteEvent.chord(pitches, duration: duration)

        if let articulation = selectedArticulation {
            event.articulations = [articulation]
        }
        if let dynamic = selectedDynamic {
            event.dynamic = dynamic
            selectedDynamic = nil
        }

        insertEvent(event)
    }

    private func makeDuration() -> Duration {
        Duration(value: selectedDuration, dotted: isDotted, doubleDotted: isDoubleDotted)
    }

    private func insertEvent(_ event: NoteEvent) {
        guard isCurrentMeasurePathValid else { return }

        // Clear placeholder whole rest when user starts entering notes
        clearPlaceholderRest()

        let ts = effectiveTimeSignature
        let measure = score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex]
        let remaining = measure.remainingBeats(timeSignature: ts)

        if event.duration.beats <= remaining + 0.001 {
            score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.append(event)
            cursorPosition += event.duration.beats
        } else {
            // Auto-advance to next measure
            advanceMeasure()
            clearPlaceholderRest()
            score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.append(event)
            cursorPosition = event.duration.beats
        }

        score.touch()
    }

    /// Remove the default whole rest placeholder if that's the only event in the measure
    private func clearPlaceholderRest() {
        guard isCurrentMeasurePathValid else { return }
        let measure = score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex]
        if measure.events.count == 1,
           measure.events[0].isRest,
           measure.events[0].duration.value == .whole,
           !measure.events[0].duration.dotted {
            score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.removeAll()
            cursorPosition = 0
        }
    }

    // MARK: - Note Selection & Editing

    var selectedEvent: NoteEvent? {
        guard let idx = selectedEventIndex,
              let measure = currentMeasure,
              idx < measure.events.count else { return nil }
        return measure.events[idx]
    }

    func selectEvent(at index: Int) {
        guard let measure = currentMeasure, index < measure.events.count else { return }
        selectedEventIndex = index
    }

    func deselectEvent() {
        selectedEventIndex = nil
        selectedPitchIndex = nil
    }

    /// Resolves a note id exported into MusicXML (see `MusicXMLExporter.idAttribute`)
    /// back to its location and selects it. This is the bridge from a tap on a
    /// Verovio-drawn notehead (whose SVG id is our exported id) to our model.
    /// Returns true if found. The id is `e<uuidHex>` with an optional `-N` chord suffix.
    @discardableResult
    func selectEvent(byExportedID exportedID: String) -> Bool {
        var hex = exportedID
        if hex.hasPrefix("e") { hex.removeFirst() }
        if let dash = hex.firstIndex(of: "-") { hex = String(hex[..<dash]) }
        for (pi, part) in score.parts.enumerated() {
            for (si, staff) in part.staves.enumerated() {
                for (mi, measure) in staff.measures.enumerated() {
                    for (ei, event) in measure.events.enumerated() {
                        let eventHex = event.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                        if eventHex == hex {
                            selectedPartIndex = pi
                            selectedStaffIndex = si
                            selectedMeasureIndex = mi
                            selectedEventIndex = ei
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    func selectPitchInChord(at pitchIndex: Int) {
        selectedPitchIndex = pitchIndex
    }

    /// Remove a specific pitch from a chord; if only one remains, convert back to single note
    func removePitchFromChord(at pitchIndex: Int) {
        mutateSelectedEvent { event in
            guard case .chord(var pitches) = event.type,
                  pitchIndex < pitches.count, pitches.count > 1 else { return }
            pitches.remove(at: pitchIndex)
            event.type = pitches.count == 1 ? .note(pitch: pitches[0]) : .chord(pitches: pitches)
            self.selectedPitchIndex = nil
        }
    }

    /// Replace a specific pitch within a chord
    func replacePitchInChord(at pitchIndex: Int, with newPitch: Pitch) {
        mutateSelectedEvent { event in
            switch event.type {
            case .chord(var pitches):
                guard pitchIndex < pitches.count else { return }
                pitches[pitchIndex] = newPitch
                pitches.sort { $0.staffPosition > $1.staffPosition }
                event.type = .chord(pitches: pitches)
            case .note:
                event.type = .note(pitch: newPitch)
            case .rest:
                break
            }
        }
    }

    func updateSelectedEventPitch(_ pitch: Pitch) {
        mutateSelectedEvent { $0.type = .note(pitch: pitch) }
    }

    func updateSelectedEventDuration(_ duration: DurationValue) {
        mutateSelectedEvent { $0.duration.value = duration }
    }

    func updateSelectedEventAccidental(_ accidental: Accidental) {
        mutateSelectedEvent { event in
            event.showNatural = (accidental == .natural)
            switch event.type {
            case .note(var pitch):
                pitch.accidental = accidental
                event.type = .note(pitch: pitch)
            case .chord(var pitches):
                for i in pitches.indices { pitches[i].accidental = accidental }
                event.type = .chord(pitches: pitches)
            case .rest: break
            }
        }
    }

    func updateSelectedEventArticulation(_ articulation: Articulation?) {
        mutateSelectedEvent { event in
            guard let art = articulation else {
                event.articulations.removeAll()
                return
            }
            if event.articulations.contains(art) {
                event.articulations.removeAll { $0 == art }
            } else {
                event.articulations.append(art)
            }
        }
    }

    func updateSelectedEventDynamic(_ dynamic: DynamicMarking) {
        mutateSelectedEvent { $0.dynamic = ($0.dynamic == dynamic) ? nil : dynamic }
    }

    func toggleSelectedEventTie() {
        mutateSelectedEvent { $0.tiedToNext.toggle() }
    }

    func toggleSelectedEventSlur() {
        mutateSelectedEvent { $0.slurStart.toggle() }
    }

    func updateSelectedEventStemDirection(_ direction: StemDirection) {
        mutateSelectedEvent { $0.stemDirection = direction }
    }

    func deleteSelectedEvent() {
        // Replace note/chord with rest of same duration (don't shift other notes)
        mutateSelectedEvent { event in
            var restEvent = NoteEvent(type: .rest, duration: event.duration)
            restEvent.duration.dotted = event.duration.dotted
            restEvent.duration.doubleDotted = event.duration.doubleDotted
            event = restEvent
        }
        selectedEventIndex = nil
    }

    func moveSelectedEvent(toPitch pitch: Pitch) {
        updateSelectedEventPitch(pitch)
    }

    /// Add a pitch to the selected event, converting a note to a chord if needed
    func addPitchToSelectedEvent(_ pitch: Pitch) {
        mutateSelectedEvent { event in
            switch event.type {
            case .note(let existing):
                // Convert note to chord
                if existing != pitch {
                    event.type = .chord(pitches: [existing, pitch])
                }
            case .chord(var pitches):
                // Add pitch to chord if not already present
                if !pitches.contains(where: { $0.name == pitch.name && $0.octave == pitch.octave }) {
                    pitches.append(pitch)
                    pitches.sort { $0.staffPosition > $1.staffPosition } // low to high on staff
                    event.type = .chord(pitches: pitches)
                }
            case .rest:
                break
            }
        }
    }

    // MARK: - Copy / Cut / Paste

    /// Copy the selected event to clipboard
    func copySelectedEvent() {
        guard let event = selectedEvent else { return }
        clipboard = [event]
        hasClipboardContent = true
    }

    /// Copy all events in the current measure to clipboard
    func copyMeasure() {
        guard let measure = currentMeasure else { return }
        clipboard = measure.events
        hasClipboardContent = true
    }

    /// Cut the selected event (copy + delete)
    func cutSelectedEvent() {
        copySelectedEvent()
        deleteSelectedEvent()
    }

    /// Paste clipboard contents at cursor position
    func paste() {
        guard !clipboard.isEmpty, isCurrentMeasurePathValid else { return }
        saveUndoState()
        clearPlaceholderRest()

        let ts = effectiveTimeSignature
        for event in clipboard {
            let measure = score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex]
            let remaining = measure.remainingBeats(timeSignature: ts)

            if event.duration.beats <= remaining + 0.001 {
                score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.append(event)
                cursorPosition += event.duration.beats
            } else {
                advanceMeasure()
                clearPlaceholderRest()
                score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.append(event)
                cursorPosition = event.duration.beats
            }
        }
        score.touch()
    }

    // MARK: - Transposition

    /// Transpose the selected event by a number of semitones
    func transposeSelectedEvent(semitones: Int) {
        mutateSelectedEvent { event in
            switch event.type {
            case .note(let pitch):
                let newMidi = pitch.midiNote + semitones
                guard newMidi >= 0, newMidi <= 127 else { return }
                event.type = .note(pitch: Pitch.fromMIDI(newMidi))
            case .chord(let pitches):
                let transposed = pitches.compactMap { p -> Pitch? in
                    let newMidi = p.midiNote + semitones
                    guard newMidi >= 0, newMidi <= 127 else { return nil }
                    return Pitch.fromMIDI(newMidi)
                }
                guard transposed.count == pitches.count else { return }
                event.type = .chord(pitches: transposed)
            case .rest:
                return
            }
        }
    }

    /// Transpose all events in the current measure by semitones
    func transposeMeasure(semitones: Int) {
        guard isCurrentMeasurePathValid else { return }
        saveUndoState()
        let events = score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events
        for (i, event) in events.enumerated() {
            switch event.type {
            case .note(let pitch):
                let newMidi = pitch.midiNote + semitones
                guard newMidi >= 0, newMidi <= 127 else { continue }
                score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events[i].type = .note(pitch: Pitch.fromMIDI(newMidi))
            case .chord(let pitches):
                let transposed = pitches.compactMap { p -> Pitch? in
                    let newMidi = p.midiNote + semitones
                    guard newMidi >= 0, newMidi <= 127 else { return nil }
                    return Pitch.fromMIDI(newMidi)
                }
                if transposed.count == pitches.count {
                    score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events[i].type = .chord(pitches: transposed)
                }
            case .rest:
                continue
            }
        }
        score.touch()
    }

    /// Transpose selected event by diatonic steps (positive = up, negative = down)
    func transposeSelectedEventDiatonic(steps: Int) {
        // Each diatonic step maps to different semitones depending on key
        // Simplified: use fixed major scale intervals
        let semitonesPerStep: [Int] = [0, 2, 4, 5, 7, 9, 11] // C major
        let octaves = steps / 7
        let remainder = ((steps % 7) + 7) % 7
        let semitones = octaves * 12 + semitonesPerStep[remainder] - (steps < 0 && remainder != 0 ? 12 : 0)
        transposeSelectedEvent(semitones: semitones)
    }

    // MARK: - Delete

    func deleteLastEvent() {
        guard isCurrentMeasurePathValid else { return }

        let events = score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events
        guard !events.isEmpty else { return }

        saveUndoState()
        let removed = score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.removeLast()
        cursorPosition = max(0, cursorPosition - removed.duration.beats)
        score.touch()
    }

    // MARK: - Navigation

    func advanceMeasure() {
        guard let part = currentPart else { return }
        if selectedMeasureIndex < part.measures.count - 1 {
            selectedMeasureIndex += 1
        } else {
            // Add new measure
            score.appendMeasure()
            selectedMeasureIndex = score.parts[selectedPartIndex].measures.count - 1
        }
        cursorPosition = 0
    }

    func previousMeasure() {
        if selectedMeasureIndex > 0 {
            selectedMeasureIndex -= 1
            cursorPosition = 0
        }
    }

    func selectPart(at index: Int) {
        guard index < score.parts.count else { return }
        selectedPartIndex = index
        selectedStaffIndex = 0
    }

    func addPart(instrument: Instrument) {
        saveUndoState()
        let measureCount = score.parts.first?.measureCount ?? 1
        let measures = (0..<measureCount).map { _ in Measure.wholeRest() }
        let newPart = Part(instrument: instrument, measures: measures)
        score.parts.append(newPart)
        selectedPartIndex = score.parts.count - 1
        score.touch()
    }

    func removePart(at index: Int) {
        guard score.parts.count > 1, index < score.parts.count else { return }
        saveUndoState()
        score.parts.remove(at: index)
        if selectedPartIndex >= score.parts.count {
            selectedPartIndex = score.parts.count - 1
        }
        // Сбросить выбор стана: удалённая grand-staff партия могла оставить
        // selectedStaffIndex = 1, а новая выбранная партия одностанная → краш.
        selectedStaffIndex = 0
        selectedEventIndex = nil
        let maxMeasure = max(0, score.parts[selectedPartIndex].measureCount - 1)
        if selectedMeasureIndex > maxMeasure { selectedMeasureIndex = maxMeasure }
        score.touch()
    }

    // MARK: - Measure Operations

    func insertMeasureBefore() {
        saveUndoState()
        score.insertMeasure(at: selectedMeasureIndex)
    }

    func insertMeasureAfter() {
        saveUndoState()
        score.insertMeasure(at: selectedMeasureIndex + 1)
        selectedMeasureIndex += 1
    }

    func deleteMeasure() {
        guard score.measureCount > 1 else { return }
        saveUndoState()
        score.removeMeasure(at: selectedMeasureIndex)
        if selectedMeasureIndex >= score.measureCount {
            selectedMeasureIndex = score.measureCount - 1
        }
    }

    // MARK: - Time Signature / Key Signature Changes

    func setTimeSignatureAtCurrentMeasure(_ ts: TimeSignature) {
        saveUndoState()
        for partIndex in score.parts.indices {
            for staffIndex in score.parts[partIndex].staves.indices {
                score.parts[partIndex].staves[staffIndex].measures[selectedMeasureIndex].timeSignature = ts
            }
        }
    }

    func setKeySignatureAtCurrentMeasure(_ ks: KeySignature) {
        saveUndoState()
        for partIndex in score.parts.indices {
            for staffIndex in score.parts[partIndex].staves.indices {
                score.parts[partIndex].staves[staffIndex].measures[selectedMeasureIndex].keySignature = ks
            }
        }
    }

    // MARK: - Undo / Redo

    func saveUndoState() {
        undoStack.append(score)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        savedToCNB = false
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(score)
        score = previous
        clampSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(score)
        score = next
        clampSelection()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Приводит индексы выбора в валидный диапазон относительно текущего score.
    /// После undo/redo восстановленная партитура может иметь меньше партий/тактов,
    /// чем было при выборе — устаревшие индексы дали бы пустой/неверный выбор.
    /// Выделенное событие снимается: оно почти наверняка уже не то, что было.
    private func clampSelection() {
        guard !score.parts.isEmpty else {
            selectedPartIndex = 0; selectedStaffIndex = 0; selectedMeasureIndex = 0
            selectedEventIndex = nil; selectedPitchIndex = nil; cursorPosition = 0
            return
        }
        selectedPartIndex = min(selectedPartIndex, score.parts.count - 1)
        let staves = score.parts[selectedPartIndex].staves
        selectedStaffIndex = staves.isEmpty ? 0 : min(selectedStaffIndex, staves.count - 1)
        let measureCount = staves.isEmpty ? 0 : staves[selectedStaffIndex].measures.count
        selectedMeasureIndex = measureCount == 0 ? 0 : min(selectedMeasureIndex, measureCount - 1)
        selectedEventIndex = nil
        selectedPitchIndex = nil
        cursorPosition = 0
    }

    // MARK: - Auto-save

    private func setupAutoSave() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        autoSaveURL = docs.appendingPathComponent("autosave_\(score.id.uuidString).json")

        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.autoSave()
            }
        }
    }

    func autoSave() {
        guard let url = autoSaveURL else { return }
        do {
            let data = try JSONEncoder().encode(score)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Автосохранение не удалось: \(error)")
        }
    }

    func save() {
        autoSave()
    }

    /// Вызывается после явного сохранения в .cnb: черновик автосейва стал избыточным.
    func markSavedToCNB() {
        savedToCNB = true
    }

    /// Вызывается при закрытии редактора. Если работа уже в .cnb и с тех пор не
    /// менялась — удаляем черновик, чтобы он не копился в списке восстановления.
    /// Иначе черновик сохраняется: это несохранённые правки, их нельзя терять.
    func finalizeOnClose() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        guard savedToCNB, let url = autoSaveURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Score metadata

    func setTimeSignature(_ ts: TimeSignature) {
        mutateCurrentMeasure { $0.timeSignature = ts }
    }

    func setKeySignature(_ ks: KeySignature) {
        mutateCurrentMeasure { $0.keySignature = ks }
    }

    func setClef(_ clef: Clef) {
        mutateCurrentMeasure { $0.clefChange = clef }
    }

    func setTempo(_ tempo: TempoMarking) {
        mutateCurrentMeasure { $0.tempoMarking = tempo }
    }

    func setBarline(_ barline: BarlineType) {
        mutateCurrentMeasure { $0.barlineEnd = barline }
    }

    func setNavigationMark(_ mark: NavigationMark?) {
        mutateCurrentMeasure { $0.navigationMark = mark }
    }

    // MARK: - Measure properties (Phase 2c spanner/text editing)
    //
    // Общий мутирующий хелпер: позволяет UI редактировать текущий такт
    // через одну точку входа с автоматическим saveUndoState + score.touch().

    /// Валиден ли путь part→staff→measure для текущего выбора.
    /// Ключевая защита от grand-staff краша: `selectedStaffIndex` может «протухнуть»
    /// (напр. после удаления партии фортепиано/органа selectedStaffIndex остаётся 1,
    /// а новая выбранная партия одностанная) — обращение к staves[1] иначе вылетает.
    var isCurrentMeasurePathValid: Bool {
        selectedPartIndex < score.parts.count &&
        selectedStaffIndex < score.parts[selectedPartIndex].staves.count &&
        selectedMeasureIndex < score.parts[selectedPartIndex].staves[selectedStaffIndex].measures.count
    }

    /// Применяет мутацию к текущему выбранному такту с undo/touch.
    /// Если путь выбора вне диапазона — ничего не делает.
    func mutateCurrentMeasure(_ mutate: (inout Measure) -> Void) {
        guard isCurrentMeasurePathValid else { return }
        saveUndoState()
        mutate(&score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex])
        score.touch()
    }

    /// Применяет мутацию к выбранному событию (selectedEventIndex) в текущем такте
    /// с проверкой всего пути part→staff→measure→event + undo/touch.
    /// Единая безопасная точка входа для всех событийных мутаторов.
    func mutateSelectedEvent(_ mutate: (inout NoteEvent) -> Void) {
        guard let idx = selectedEventIndex,
              isCurrentMeasurePathValid,
              idx < score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        mutate(&score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events[idx])
        score.touch()
    }

    // Volta
    func setVolta(_ volta: Volta?) {
        mutateCurrentMeasure { $0.volta = volta }
    }

    // Rehearsal mark
    func setRehearsalMark(_ mark: RehearsalMark?) {
        mutateCurrentMeasure { $0.rehearsalMark = mark }
    }

    // Tempo change (accel/rit)
    func setTempoChange(_ change: TempoChange?) {
        mutateCurrentMeasure { $0.tempoChange = change }
    }

    // Multi-measure rest count
    func setMultiMeasureRestCount(_ count: Int) {
        mutateCurrentMeasure { $0.multiMeasureRestCount = max(0, count) }
    }

    // Hairpins
    func addHairpin(_ hairpin: Hairpin) {
        mutateCurrentMeasure { $0.hairpins.append(hairpin) }
    }

    func updateHairpin(id: UUID, type: HairpinType, startBeat: Double, endBeat: Double) {
        mutateCurrentMeasure { measure in
            guard let idx = measure.hairpins.firstIndex(where: { $0.id == id }) else { return }
            measure.hairpins[idx].type = type
            measure.hairpins[idx].startBeat = startBeat
            measure.hairpins[idx].endBeat = endBeat
        }
    }

    func removeHairpin(id: UUID) {
        mutateCurrentMeasure { $0.hairpins.removeAll { $0.id == id } }
    }

    // Octave shifts
    func addOctaveShift(_ shift: OctaveShift) {
        mutateCurrentMeasure { $0.octaveShifts.append(shift) }
    }

    func updateOctaveShift(id: UUID, kind: OctaveShiftKind, startBeat: Double, endBeat: Double) {
        mutateCurrentMeasure { measure in
            guard let idx = measure.octaveShifts.firstIndex(where: { $0.id == id }) else { return }
            measure.octaveShifts[idx].kind = kind
            measure.octaveShifts[idx].startBeat = startBeat
            measure.octaveShifts[idx].endBeat = endBeat
        }
    }

    func removeOctaveShift(id: UUID) {
        mutateCurrentMeasure { $0.octaveShifts.removeAll { $0.id == id } }
    }

    // Expression texts
    func addExpressionText(_ text: ExpressionText) {
        mutateCurrentMeasure { $0.expressionTexts.append(text) }
    }

    func updateExpressionText(at index: Int, text: String, italianTerm: Bool, attachToBeat: Double) {
        mutateCurrentMeasure { measure in
            guard index < measure.expressionTexts.count else { return }
            measure.expressionTexts[index].text = text
            measure.expressionTexts[index].italianTerm = italianTerm
            measure.expressionTexts[index].attachToBeat = attachToBeat
        }
    }

    func removeExpressionText(at index: Int) {
        mutateCurrentMeasure { measure in
            guard index < measure.expressionTexts.count else { return }
            measure.expressionTexts.remove(at: index)
        }
    }

    // MARK: - Event-level Phase 2c attributes (tuplet, chord symbol, fingering)

    /// Установить tuplet на одиночное событие (не группа — для группы см.
    /// `applyTupletGroupStartingAtSelected`). Если nil — снять группировку.
    func setTupletForSelectedEvent(_ tuplet: Tuplet?) {
        guard let idx = selectedEventIndex else { return }
        mutateCurrentMeasure { measure in
            guard idx < measure.events.count else { return }
            measure.events[idx].tuplet = tuplet
        }
    }

    /// Применить tuplet-группу начиная с выбранного события и захватывая
    /// следующие `actualCount - 1` событий в том же такте. Если событий не
    /// хватает — группа сокращается до доступных.
    func applyTupletGroupStartingAtSelected(actualCount: Int, normalCount: Int) {
        guard let start = selectedEventIndex,
              actualCount > 1 else { return }
        mutateCurrentMeasure { measure in
            let groupID = UUID()
            let end = min(start + actualCount, measure.events.count)
            for (i, idx) in (start..<end).enumerated() {
                measure.events[idx].tuplet = Tuplet(
                    actualCount: actualCount,
                    normalCount: normalCount,
                    groupID: groupID,
                    positionInGroup: i
                )
            }
        }
    }

    /// Снять tuplet со всех событий группы выбранного события.
    func removeTupletGroupFromSelected() {
        guard let idx = selectedEventIndex,
              let measure = currentMeasure,
              idx < measure.events.count,
              let groupID = measure.events[idx].tuplet?.groupID else { return }
        mutateCurrentMeasure { measure in
            for i in measure.events.indices where measure.events[i].tuplet?.groupID == groupID {
                measure.events[i].tuplet = nil
            }
        }
    }

    func setChordSymbolForSelectedEvent(_ symbol: ChordSymbol?) {
        guard let idx = selectedEventIndex else { return }
        mutateCurrentMeasure { measure in
            guard idx < measure.events.count else { return }
            measure.events[idx].chordSymbol = symbol
        }
    }

    func setFingeringForSelectedEvent(_ fingering: String?) {
        guard let idx = selectedEventIndex else { return }
        mutateCurrentMeasure { measure in
            guard idx < measure.events.count else { return }
            measure.events[idx].fingering = (fingering?.isEmpty == true) ? nil : fingering
        }
    }

    // MARK: - Voice Layers

    /// Events in current measure filtered by selected voice (or all if showAllVoices)
    var currentMeasureEventsForVoice: [NoteEvent] {
        guard let measure = currentMeasure else { return [] }
        if showAllVoices { return measure.events }
        return measure.events.filter { $0.voice == selectedVoice }
    }

    func selectVoice(_ voice: VoiceLayer) {
        selectedVoice = voice
    }

    func updateSelectedEventVoice(_ voice: VoiceLayer) {
        mutateSelectedEvent { $0.voice = voice }
    }

    // MARK: - Lyrics

    func setLyricForSelectedEvent(_ text: String) {
        mutateSelectedEvent { $0.lyric = text.isEmpty ? nil : text }
    }

    func startLyricEditing() {
        guard let event = selectedEvent else { return }
        currentLyricText = event.lyric ?? ""
        isEditingLyric = true
    }

    func commitLyric() {
        setLyricForSelectedEvent(currentLyricText)
        isEditingLyric = false
        currentLyricText = ""
    }

    // MARK: - Playback Techniques

    func updateSelectedEventTechnique(_ technique: PlaybackTechnique?) {
        mutateSelectedEvent { $0.technique = technique }
    }

    func setStrumPattern(_ pattern: StrumPattern) {
        mutateSelectedEvent { $0.strumPattern = pattern }
    }
}
