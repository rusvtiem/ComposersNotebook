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
    @Published var selectedMeasureIndex: Int = 0
    @Published var cursorPosition: Double = 0  // beat position within measure

    // Selection state
    @Published var selectedEventIndex: Int? = nil  // index of selected note in current measure

    // Input state
    @Published var inputMode: InputMode = .navigate
    @Published var selectedDuration: DurationValue = .quarter
    @Published var selectedAccidental: Accidental? = nil  // nil = без альтерации, .natural = явный бекар
    @Published var isDotted: Bool = false
    @Published var selectedArticulation: Articulation?
    @Published var selectedDynamic: DynamicMarking?
    @Published var tieNext: Bool = false
    @Published var slurActive: Bool = false
    @Published var stemDirection: StemDirection = .auto
    @Published var zoomScale: CGFloat = 1.0  // pinch-to-zoom

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

    var currentMeasure: Measure? {
        guard let part = currentPart,
              selectedMeasureIndex < part.measures.count else { return nil }
        return part.measures[selectedMeasureIndex]
    }

    var effectiveTimeSignature: TimeSignature {
        guard let part = currentPart else { return score.timeSignature }
        // Walk backwards to find the most recent time signature
        for i in stride(from: selectedMeasureIndex, through: 0, by: -1) {
            if let ts = part.measures[i].timeSignature {
                return ts
            }
        }
        return score.timeSignature
    }

    var effectiveKeySignature: KeySignature {
        guard let part = currentPart else { return score.keySignature }
        for i in stride(from: selectedMeasureIndex, through: 0, by: -1) {
            if let ks = part.measures[i].keySignature {
                return ks
            }
        }
        return score.keySignature
    }

    // MARK: - Note Input

    func addNote(pitch: Pitch) {
        guard inputMode == .note else { return }

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
        Duration(value: selectedDuration, dotted: isDotted)
    }

    private func insertEvent(_ event: NoteEvent) {
        guard selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count else { return }

        // Clear placeholder whole rest when user starts entering notes
        clearPlaceholderRest()

        let ts = effectiveTimeSignature
        let measure = score.parts[selectedPartIndex].measures[selectedMeasureIndex]
        let remaining = measure.remainingBeats(timeSignature: ts)

        if event.duration.beats <= remaining + 0.001 {
            score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.append(event)
            cursorPosition += event.duration.beats
        } else {
            // Auto-advance to next measure
            advanceMeasure()
            clearPlaceholderRest()
            score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.append(event)
            cursorPosition = event.duration.beats
        }

        score.touch()
    }

    /// Remove the default whole rest placeholder if that's the only event in the measure
    private func clearPlaceholderRest() {
        let measure = score.parts[selectedPartIndex].measures[selectedMeasureIndex]
        if measure.events.count == 1,
           measure.events[0].isRest,
           measure.events[0].duration.value == .whole,
           !measure.events[0].duration.dotted {
            score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.removeAll()
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
    }

    func updateSelectedEventPitch(_ pitch: Pitch) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].type = .note(pitch: pitch)
        score.touch()
    }

    func updateSelectedEventDuration(_ duration: DurationValue) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].duration.value = duration
        score.touch()
    }

    func updateSelectedEventAccidental(_ accidental: Accidental) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        var event = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx]
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
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx] = event
        score.touch()
    }

    func updateSelectedEventArticulation(_ articulation: Articulation?) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        if let art = articulation {
            if score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].articulations.contains(art) {
                score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].articulations.removeAll { $0 == art }
            } else {
                score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].articulations.append(art)
            }
        } else {
            score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].articulations.removeAll()
        }
        score.touch()
    }

    func toggleSelectedEventTie() {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].tiedToNext.toggle()
        score.touch()
    }

    func toggleSelectedEventSlur() {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].slurStart.toggle()
        score.touch()
    }

    func updateSelectedEventStemDirection(_ direction: StemDirection) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx].stemDirection = direction
        score.touch()
    }

    func deleteSelectedEvent() {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        let removed = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.remove(at: idx)
        cursorPosition = max(0, cursorPosition - removed.duration.beats)
        selectedEventIndex = nil
        score.touch()
    }

    func moveSelectedEvent(toPitch pitch: Pitch) {
        updateSelectedEventPitch(pitch)
    }

    /// Add a pitch to the selected event, converting a note to a chord if needed
    func addPitchToSelectedEvent(_ pitch: Pitch) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        var event = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx]
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
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx] = event
        score.touch()
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
        guard !clipboard.isEmpty else { return }
        saveUndoState()
        clearPlaceholderRest()

        let ts = effectiveTimeSignature
        for event in clipboard {
            let measure = score.parts[selectedPartIndex].measures[selectedMeasureIndex]
            let remaining = measure.remainingBeats(timeSignature: ts)

            if event.duration.beats <= remaining + 0.001 {
                score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.append(event)
                cursorPosition += event.duration.beats
            } else {
                advanceMeasure()
                clearPlaceholderRest()
                score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.append(event)
                cursorPosition = event.duration.beats
            }
        }
        score.touch()
    }

    // MARK: - Transposition

    /// Transpose the selected event by a number of semitones
    func transposeSelectedEvent(semitones: Int) {
        guard let idx = selectedEventIndex,
              selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count,
              idx < score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.count else { return }
        saveUndoState()
        var event = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx]
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
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[idx] = event
        score.touch()
    }

    /// Transpose all events in the current measure by semitones
    func transposeMeasure(semitones: Int) {
        guard selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count else { return }
        saveUndoState()
        let events = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events
        for (i, event) in events.enumerated() {
            switch event.type {
            case .note(let pitch):
                let newMidi = pitch.midiNote + semitones
                guard newMidi >= 0, newMidi <= 127 else { continue }
                score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[i].type = .note(pitch: Pitch.fromMIDI(newMidi))
            case .chord(let pitches):
                let transposed = pitches.compactMap { p -> Pitch? in
                    let newMidi = p.midiNote + semitones
                    guard newMidi >= 0, newMidi <= 127 else { return nil }
                    return Pitch.fromMIDI(newMidi)
                }
                if transposed.count == pitches.count {
                    score.parts[selectedPartIndex].measures[selectedMeasureIndex].events[i].type = .chord(pitches: transposed)
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
        guard selectedPartIndex < score.parts.count,
              selectedMeasureIndex < score.parts[selectedPartIndex].measures.count else { return }

        let events = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events
        guard !events.isEmpty else { return }

        saveUndoState()
        let removed = score.parts[selectedPartIndex].measures[selectedMeasureIndex].events.removeLast()
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
            score.parts[partIndex].measures[selectedMeasureIndex].timeSignature = ts
        }
    }

    func setKeySignatureAtCurrentMeasure(_ ks: KeySignature) {
        saveUndoState()
        for partIndex in score.parts.indices {
            score.parts[partIndex].measures[selectedMeasureIndex].keySignature = ks
        }
    }

    // MARK: - Undo / Redo

    func saveUndoState() {
        undoStack.append(score)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(score)
        score = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(score)
        score = next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

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

    // MARK: - Score metadata

    func setTimeSignature(_ ts: TimeSignature) {
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].timeSignature = ts
        score.touch()
    }

    func setKeySignature(_ ks: KeySignature) {
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].keySignature = ks
        score.touch()
    }

    func setClef(_ clef: Clef) {
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].clefChange = clef
        score.touch()
    }

    func setTempo(_ tempo: TempoMarking) {
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].tempoMarking = tempo
        score.touch()
    }

    func setBarline(_ barline: BarlineType) {
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].barlineEnd = barline
        score.touch()
    }

    func setNavigationMark(_ mark: NavigationMark?) {
        saveUndoState()
        score.parts[selectedPartIndex].measures[selectedMeasureIndex].navigationMark = mark
        score.touch()
    }
}
