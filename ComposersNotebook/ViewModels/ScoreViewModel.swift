import SwiftUI
import Combine

// MARK: - Input Mode

enum InputMode: Equatable {
    case note
    case rest
    case select
}

// MARK: - Score View Model

@MainActor
class ScoreViewModel: ObservableObject {
    // Score data
    @Published var score: Score
    @Published var selectedPartIndex: Int = 0
    @Published var selectedMeasureIndex: Int = 0
    @Published var cursorPosition: Double = 0  // beat position within measure

    // Input state
    @Published var inputMode: InputMode = .note
    @Published var selectedDuration: DurationValue = .quarter
    @Published var selectedAccidental: Accidental = .natural
    @Published var isDotted: Bool = false
    @Published var selectedArticulation: Articulation?
    @Published var selectedDynamic: DynamicMarking?
    @Published var tieNext: Bool = false
    @Published var slurActive: Bool = false
    @Published var stemDirection: StemDirection = .auto

    // Playback
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Int = 0  // measure index
    let midiEngine = MIDIEngine.shared

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
        saveUndoState()

        let duration = makeDuration()
        var event = NoteEvent.note(pitch, duration: duration)
        event.stemDirection = stemDirection

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
