import SwiftUI
import Combine

// MARK: - Input Mode

enum InputMode: Equatable {
    case navigate  // Default: tap = select measure, scroll freely
    case note      // Tap = insert note at pitch
    case rest      // Tap = insert rest with selected duration
    case repitch   // Retype pitch of the selected note, keep duration, advance (MuseScore re-pitch)
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
    // Диапазонное выделение (MuseScore Shift+стрелки / Ctrl+A). Якорь — неподвижный
    // конец диапазона; selectedMeasureIndex/selectedEventIndex — подвижный «фокус».
    // nil-якорь = обычное одиночное выделение. Диапазон всегда в пределах текущего стана.
    @Published var selectionAnchorMeasureIndex: Int? = nil
    @Published var selectionAnchorEventIndex: Int? = nil

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
    // Явный режим «в аккорд» (паритет MuseScore): когда включён, ввод ноты при
    // выделенном событии наращивает аккорд; когда выключен — ввод создаёт новую
    // ноту даже при выделении (убирает класс случайных аккордов от неявного тапа).
    @Published var addToChordMode: Bool = false
    // Режим вставки (MuseScore Ctrl+I): ввод ноты не перезаписывает, а РАЗДВИГАЕТ
    // музыку вправо — вся последующая музыка стана переливается по тактам с
    // залиговкой через тактовую черту, при необходимости добавляются такты.
    @Published var insertMode: Bool = false

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

    /// Inverse of `partStaff(forFlattenedStaffIndex:)`: the render-order flattened
    /// staff index for a concrete part+staff. Used to find the Verovio staff column
    /// (staves are drawn flattened across parts) that the model cursor sits on.
    func flattenedStaffIndex(part: Int, staff: Int) -> Int? {
        guard part >= 0, part < score.parts.count,
              staff >= 0, staff < score.parts[part].staves.count else { return nil }
        var base = 0
        for pi in 0..<part { base += score.parts[pi].staves.count }
        return base + staff
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

    /// The most recent pitched note before the input cursor — the reference for
    /// MuseScore-style nearest-octave letter input. Walks back from the current
    /// measure; within a measure takes the last note/chord (chord → its top
    /// pitch). Rests are skipped. `nil` when nothing has been entered yet.
    var previousInputPitch: Pitch? {
        guard let staff = currentStaff, !staff.measures.isEmpty else { return nil }
        let start = min(selectedMeasureIndex, staff.measures.count - 1)
        for mi in stride(from: start, through: 0, by: -1) {
            for event in staff.measures[mi].events.reversed() {
                switch event.type {
                case .note(let pitch): return pitch
                case .chord(let pitches): return pitches.max(by: { $0.midiNote < $1.midiNote })
                case .rest: continue
                }
            }
        }
        return nil
    }

    /// The octave that places `name` closest to the previous note (MuseScore rule:
    /// A–G lands in the octave nearest the preceding note). `PitchName.rawValue` is
    /// the diatonic degree (C=0…B=6), so a diatonic index is `octave*7 + degree`.
    /// Falls back to `fallback` when there is no previous note. Clamped to 1…7.
    func nearestOctave(forName name: PitchName, fallback: Int) -> Int {
        guard let ref = previousInputPitch else { return fallback }
        let newDeg = name.rawValue
        let refIndex = ref.octave * 7 + ref.name.rawValue
        var best = ref.octave
        var bestDist = Int.max
        for octave in [ref.octave - 1, ref.octave, ref.octave + 1] {
            let dist = abs((octave * 7 + newDeg) - refIndex)
            if dist < bestDist { bestDist = dist; best = octave }
        }
        return min(7, max(1, best))
    }

    /// Insert a fresh note at the cursor from the Verovio editing surface, which
    /// resolves pitch from a tap on the engraving instead of the toolbar input
    /// mode. Bypasses the `inputMode` guard and deselects first so the tap adds a
    /// standalone note rather than extending the selected event into a chord.
    func insertNoteAtCursor(_ pitch: Pitch) {
        // В режиме «в аккорд» тап рядом с выделенным событием наращивает аккорд,
        // а не создаёт отдельную ноту.
        if addToChordMode, selectedEventIndex != nil {
            addPitchToSelectedEvent(pitch)
            let midiProg = currentPart?.instrument.midiProgram ?? 0
            midiEngine.playNote(pitch: pitch, velocity: 80, duration: 0.3, midiProgram: midiProg)
            return
        }
        let previousMode = inputMode
        inputMode = .note
        selectedEventIndex = nil
        addNote(pitch: pitch)
        inputMode = previousMode
    }

    func addNote(pitch: Pitch) {
        if inputMode == .repitch {
            repitchSelected(toPitches: [pitch])
            return
        }
        guard inputMode == .note else { return }

        // Auto-select staff for grand staff instruments (split at middle C = C4)
        if let part = currentPart, part.isGrandStaff {
            let middleC = 60 // MIDI note for C4
            selectedStaffIndex = pitch.midiNote >= middleC ? 0 : 1
        }

        // Наращивание аккорда — только в явном режиме «в аккорд». Иначе ввод при
        // выделенной ноте создаёт новую ноту (паритет MuseScore, без случайных аккордов).
        if selectedEventIndex != nil && addToChordMode {
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
        if inputMode == .repitch {
            repitchSelected(toPitches: pitches)
            return
        }
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

    /// Last event before the cursor (note/chord/rest), walking back across
    /// measures. Basis for MuseScore `R` when nothing is explicitly selected.
    private var lastEnteredEvent: NoteEvent? {
        guard let staff = currentStaff, !staff.measures.isEmpty else { return nil }
        let start = min(selectedMeasureIndex, staff.measures.count - 1)
        for mi in stride(from: start, through: 0, by: -1) {
            if let last = staff.measures[mi].events.last { return last }
        }
        return nil
    }

    /// MuseScore `R`: repeat the selected event (or the last entered one) at the
    /// input cursor with the same pitch(es) and duration. Relational marks (ties,
    /// slurs) are intentionally dropped — they belong between specific notes, not
    /// on a fresh copy. A brand-new id makes the copy an independent event.
    func repeatLastEvent() {
        guard let source = selectedEvent ?? lastEnteredEvent else { return }
        saveUndoState()
        let copy = NoteEvent(
            type: source.type,
            duration: source.duration,
            articulations: source.articulations,
            dynamic: source.dynamic,
            stemDirection: source.stemDirection,
            showNatural: source.showNatural,
            voice: source.voice,
            technique: source.technique
        )
        // Repeating continues input past the selection rather than editing it.
        if selectedEventIndex != nil { deselectEvent() }
        insertEvent(copy)
        if case .rest = copy.type {} else {
            let midiProg = currentPart?.instrument.midiProgram ?? 0
            for pitch in copy.pitches {
                midiEngine.playNote(pitch: pitch, velocity: 80, duration: 0.3, midiProgram: midiProg)
            }
        }
    }

    /// MuseScore re-pitch: replace the pitch content of the selected note/chord
    /// with `pitches`, KEEPING its duration and other properties, then advance to
    /// the next event. Rests are skipped (stepped over without change). No-op when
    /// nothing is selected or only rests remain ahead.
    func repitchSelected(toPitches pitches: [Pitch]) {
        guard !pitches.isEmpty else { return }
        // Step over rests to the next pitched event; bail if we can't advance.
        while let ev = selectedEvent, ev.isRest {
            let before = (selectedMeasureIndex, selectedEventIndex)
            selectNextEvent()
            if (selectedMeasureIndex, selectedEventIndex) == before { return }
        }
        guard selectedEvent != nil else { return }
        saveUndoState()
        mutateSelectedEvent { event in
            if pitches.count == 1 {
                event.type = .note(pitch: pitches[0])
                event.showNatural = (pitches[0].accidental == .natural)
            } else {
                event.type = .chord(pitches: pitches.sorted { $0.staffPosition > $1.staffPosition })
            }
        }
        let midiProg = currentPart?.instrument.midiProgram ?? 0
        for pitch in pitches {
            midiEngine.playNote(pitch: pitch, velocity: 80, duration: 0.3, midiProgram: midiProg)
        }
        selectNextEvent()
    }

    /// MuseScore grace note (клавиша «/»): помечает выбранную ноту/аккорд как
    /// форшлаг (acciaccatura) или снимает пометку. Паузу форшлагом не делаем.
    /// Форшлаг не занимает времени такта (actualBeats == 0) и рисуется мелким —
    /// цепляется к следующему за ним событию, как `<grace>` в MusicXML.
    func toggleGraceOnSelected() {
        setGraceOnSelected(.acciaccatura)
    }

    /// MuseScore appoggiatura (long grace, no slash). Toggles the selected
    /// note/chord to an appoggiatura, or off if already one.
    func toggleAppoggiaturaOnSelected() {
        setGraceOnSelected(.appoggiatura)
    }

    /// Set the selected note's grace type, or clear it if it already equals
    /// `type` (so each grace button toggles its own kind). Rests can't be graces.
    private func setGraceOnSelected(_ type: GraceType) {
        guard let event = selectedEvent, !event.isRest else { return }
        let newValue: GraceType? = event.grace == type ? nil : type
        mutateSelectedEvent { $0.grace = newValue }
    }

    private func makeDuration() -> Duration {
        Duration(value: selectedDuration, dotted: isDotted, doubleDotted: isDoubleDotted)
    }

    /// MuseScore Q — halve the input duration (quarter → eighth). Operates on the
    /// sticky input pen (`selectedDuration`) only, never the selected event, so the
    /// measure-full invariant can't break. `allCases` runs longest→shortest, so a
    /// shorter value is the next index. Clamped at the shortest (1024th).
    func halveDuration() {
        let all = DurationValue.allCases
        guard let idx = all.firstIndex(of: selectedDuration), idx + 1 < all.count else { return }
        selectedDuration = all[idx + 1]
    }

    /// MuseScore W — double the input duration (eighth → quarter). Longer value is
    /// the previous index in `allCases`. Clamped at the longest (longa).
    func doubleDuration() {
        let all = DurationValue.allCases
        guard let idx = all.firstIndex(of: selectedDuration), idx - 1 >= 0 else { return }
        selectedDuration = all[idx - 1]
    }

    private func insertEvent(_ event: NoteEvent) {
        placeEvent(event)
        score.touch()
    }

    /// MuseScore step-time placement: overwrite `event` at the cursor, keeping the
    /// measure exactly full of real (individually selectable) rests, then advance
    /// the cursor. This is the single source of the "measure always full" invariant
    /// — no placeholder is silently deleted, the remaining beats become real rests.
    private func placeEvent(_ event: NoteEvent) {
        guard isCurrentMeasurePathValid else { return }
        if insertMode {
            insertEventShiftingRight(event)
            return
        }
        let ts = effectiveTimeSignature
        let total = ts.totalBeats
        let evBeats = max(0, event.actualBeats)

        // If the event can't fit from the cursor, move to (or create) the next measure.
        if cursorPosition + evBeats > total + 0.001 {
            advanceMeasure()
            cursorPosition = 0
        }

        let pi = selectedPartIndex, si = selectedStaffIndex, mi = selectedMeasureIndex
        let current = score.parts[pi].staves[si].measures[mi].events
        score.parts[pi].staves[si].measures[mi].events =
            Measure.overwrite(current, with: event, atBeat: cursorPosition, totalBeats: total)
        cursorPosition += evBeats
    }

    /// MuseScore Insert mode (Ctrl+I): insert `event` at the caret, shoving the whole
    /// rest of THIS staff rightward. Everything from the caret to the staff's end is
    /// flattened, the new event spliced in at the caret beat, then re-flowed into full
    /// bars (notes tied across barlines) — growing the staff by however many bars the
    /// added time needs. Other staves/parts are padded with empty bars so all stay
    /// measure-aligned (the render/export path requires equal bar counts).
    func insertEventShiftingRight(_ event: NoteEvent) {
        guard isCurrentMeasurePathValid else { return }
        let pi = selectedPartIndex, si = selectedStaffIndex, mi = selectedMeasureIndex
        let total = effectiveTimeSignature.totalBeats
        let insBeats = max(0, event.actualBeats)
        guard insBeats > 0 else { return }

        let tailMeasures = Array(score.parts[pi].staves[si].measures[mi...])
        let oldTailCount = tailMeasures.count

        // Flatten the tail, splicing the new event in at the caret beat of measure mi.
        var stream: [NoteEvent] = []
        var beat = 0.0
        var spliced = false
        for ev in tailMeasures[0].events {
            if !spliced && beat + 1e-6 >= cursorPosition {
                stream.append(event)
                spliced = true
            }
            stream.append(ev)
            beat += max(0, ev.actualBeats)
        }
        if !spliced { stream.append(event) }
        for m in tailMeasures.dropFirst() { stream.append(contentsOf: m.events) }

        let newBars = Measure.reflow(stream, totalBeats: total)
        guard newBars.count >= oldTailCount else { return }

        saveUndoState()

        // Grow every part/staff so counts stay aligned, then rewrite this staff's tail.
        let delta = newBars.count - oldTailCount
        for _ in 0..<delta { score.appendMeasure() }

        for (j, barEvents) in newBars.enumerated() {
            let target = mi + j
            if j < oldTailCount {
                var m = tailMeasures[j]
                m.events = barEvents
                score.parts[pi].staves[si].measures[target] = m
            } else {
                score.parts[pi].staves[si].measures[target] = Measure(events: barEvents)
            }
        }

        // Park the caret just after the inserted note.
        var mIdx = mi
        var b = cursorPosition + insBeats
        let lastMeasure = score.parts[pi].staves[si].measures.count - 1
        while b >= total - 1e-9 && mIdx < lastMeasure { b -= total; mIdx += 1 }
        selectedMeasureIndex = mIdx
        cursorPosition = b
        selectedEventIndex = nil
        selectedPitchIndex = nil
        score.touch()
    }

    // MARK: - Note Selection & Editing

    var selectedEvent: NoteEvent? {
        guard let idx = selectedEventIndex,
              let measure = currentMeasure,
              idx < measure.events.count else { return nil }
        return measure.events[idx]
    }

    /// The event the note-input caret rides: the explicitly selected event, else
    /// the event whose beat span covers `cursorPosition` on the focused staff — the
    /// element the next entry will overwrite. MuseScore anchors its caret on the
    /// actual drawn note/rest at the insertion point, so exposing its id lets the
    /// caret sit on the rendered element instead of a measure-level indent.
    private var caretEvent: NoteEvent? {
        if let selected = selectedEvent { return selected }
        guard let measure = currentMeasure else { return nil }
        var offset = 0.0
        for event in measure.events {
            let beats = max(0, event.actualBeats)
            // Skip zero-length events (grace notes) — they carry no beat cell.
            if beats > 0, cursorPosition < offset + beats - 1e-6 { return event }
            offset += beats
        }
        return measure.events.last
    }

    /// The Verovio exported id (`e` + dashless-lowercase UUID) of `caretEvent`, or
    /// nil when the focused measure has no events. Matches the `@xml:id` Verovio drew
    /// so the caret can be anchored on that rendered element.
    var caretExportedID: String? {
        guard let event = caretEvent else { return nil }
        return "e" + event.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func selectEvent(at index: Int) {
        guard let measure = currentMeasure, index < measure.events.count else { return }
        clearRangeAnchor()
        selectedEventIndex = index
    }

    func deselectEvent() {
        clearRangeAnchor()
        selectedEventIndex = nil
        selectedPitchIndex = nil
    }

    /// Resolves a note id exported into MusicXML (see `MusicXMLExporter.idAttribute`)
    /// back to its location and selects it. This is the bridge from a tap on a
    /// Verovio-drawn notehead (whose SVG id is our exported id) to our model.
    /// Returns true if found. The id is `e<uuidHex>` with an optional `-N` chord suffix.
    @discardableResult
    func selectEvent(byExportedID exportedID: String) -> Bool {
        clearRangeAnchor()
        var hex = exportedID
        if hex.hasPrefix("e") { hex.removeFirst() }
        // The `-N` suffix (N>0) marks a specific notehead of a chord, so a tap on
        // one note of a chord selects that pitch, not just the whole event.
        var pitchIndex: Int?
        if let dash = hex.firstIndex(of: "-") {
            pitchIndex = Int(hex[hex.index(after: dash)...])
            hex = String(hex[..<dash])
        }
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
                            selectedPitchIndex = pitchIndex
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

    /// Change the selected event's duration the way MuseScore does: overwrite from
    /// the event's own start beat and refill the rest of the measure so it stays
    /// exactly full. In-place mutation of only `duration.value` left the measure
    /// short when shrinking (the freed time vanished) or over-full when growing
    /// past the room to the barline (a 1/4 appearing where only a 1/8 fit). Routing
    /// through `Measure.overwrite` restores the "measure always full of real,
    /// selectable rests" invariant; a duration longer than the room left is clamped
    /// to the largest value that fits, so it can never spill past the barline.
    func updateSelectedEventDuration(_ duration: DurationValue) {
        guard let idx = selectedEventIndex, isCurrentMeasurePathValid,
              let measure = currentMeasure, idx < measure.events.count else { return }
        let events = measure.events
        let total = effectiveTimeSignature.totalBeats
        let startBeat = events.prefix(idx).reduce(0.0) { $0 + max(0, $1.actualBeats) }
        let available = total - startBeat

        var newEvent = events[idx]
        newEvent.duration.value = duration
        // Can't grow past the barline: clamp to the largest value that fits. Dots
        // are dropped when clamping so the event never overshoots the remaining room.
        if newEvent.duration.beats > available + 1e-9 {
            newEvent.duration = Duration(value: largestDurationValue(fitting: available))
        }

        saveUndoState()
        let rebuilt = Measure.overwrite(events, with: newEvent,
                                        atBeat: startBeat, totalBeats: total)
        score.parts[selectedPartIndex].staves[selectedStaffIndex]
            .measures[selectedMeasureIndex].events = rebuilt
        // Keep the edited event selected — its id survives the overwrite.
        selectedEventIndex = rebuilt.firstIndex { $0.id == newEvent.id } ?? idx
        score.touch()
    }

    /// The longest `DurationValue` whose plain (undotted) length is ≤ `beats`.
    /// `DurationValue.allCases` runs longest→shortest, so the first fit wins.
    private func largestDurationValue(fitting beats: Double) -> DurationValue {
        for v in DurationValue.allCases where Duration(value: v).beats <= beats + 1e-9 {
            return v
        }
        return .oneThousandTwentyFourth
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

    /// MuseScore `T`: tie the selected note into a NEW note of the same pitch(es)
    /// and duration placed right after it, and link the two. This differs from
    /// `toggleSelectedEventTie`, which only flips the flag toward an
    /// already-present next note — the common authoring case is "I just wrote a
    /// note and want it tied over", which needs the second note created. Rests
    /// can't be tied. If a real note already follows in the measure, we don't
    /// clobber it: we just set the tie flag (ties to it when pitches match).
    func tieSelectedIntoNewNote() {
        guard let source = selectedEvent, !source.isRest,
              isCurrentMeasurePathValid, let measure = currentMeasure,
              let idx = selectedEventIndex else { return }
        saveUndoState()

        let pi = selectedPartIndex, si = selectedStaffIndex, mi = selectedMeasureIndex

        // If a real (non-rest) note already follows, don't overwrite it — just mark
        // the tie flag and stop (matches toggle behaviour, ties when pitches match).
        let following = measure.events.dropFirst(idx + 1).first { $0.actualBeats > 0 }
        if let f = following, !f.isRest {
            score.parts[pi].staves[si].measures[mi].events[idx].tiedToNext = true
            score.touch()
            return
        }

        // Otherwise create the continuation note over the trailing rests.
        var offset = 0.0
        for e in measure.events.prefix(idx + 1) { offset += max(0, e.actualBeats) }
        score.parts[pi].staves[si].measures[mi].events[idx].tiedToNext = true
        let copy = NoteEvent(
            type: source.type,
            duration: source.duration,
            stemDirection: source.stemDirection,
            voice: source.voice
        )
        cursorPosition = offset
        placeEvent(copy)
        score.touch()
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

    /// MuseScore `Ctrl+C` on a range: copy every event of the current selection (a
    /// single focus or a multi-event span, in order) to the clipboard.
    func copySelection() {
        guard let staff = currentStaff else { return }
        let positions = selectedRangePositions
        var events: [NoteEvent] = []
        for pos in positions where pos.measure < staff.measures.count {
            let evs = staff.measures[pos.measure].events
            if pos.event < evs.count { events.append(evs[pos.event]) }
        }
        guard !events.isEmpty else { return }
        clipboard = events
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

    /// MuseScore `Ctrl+X` on a range: copy the whole selection, then blank it to rests.
    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    /// Paste clipboard contents at the cursor. Every pasted event gets a fresh identity
    /// (`withFreshID`) so a duplicated run never collides with the originals' Verovio
    /// ids — otherwise selection/highlight would jump between the twin glyphs.
    func paste() {
        guard !clipboard.isEmpty, isCurrentMeasurePathValid else { return }
        saveUndoState()
        for event in clipboard {
            placeEvent(event.withFreshID())
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
                event.type = .note(pitch: Pitch.fromMIDI(newMidi, preferFlats: semitones < 0))
            case .chord(let pitches):
                let transposed = pitches.compactMap { p -> Pitch? in
                    let newMidi = p.midiNote + semitones
                    guard newMidi >= 0, newMidi <= 127 else { return nil }
                    return Pitch.fromMIDI(newMidi, preferFlats: semitones < 0)
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
                score.parts[selectedPartIndex].staves[selectedStaffIndex].measures[selectedMeasureIndex].events[i].type = .note(pitch: Pitch.fromMIDI(newMidi, preferFlats: semitones < 0))
            case .chord(let pitches):
                let transposed = pitches.compactMap { p -> Pitch? in
                    let newMidi = p.midiNote + semitones
                    guard newMidi >= 0, newMidi <= 127 else { return nil }
                    return Pitch.fromMIDI(newMidi, preferFlats: semitones < 0)
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

    /// Transpose selected event by diatonic steps (positive = up, negative = down).
    /// MuseScore's Alt+Shift+↑/↓: moves by scale degrees, keeping the note inside the
    /// current key — a step lands on the next letter and takes that letter's accidental
    /// from the key signature (in G major, stepping F→G is natural, D→E natural, but a
    /// note landing on F becomes F♯). This replaces the old fixed C-major table.
    func transposeSelectedEventDiatonic(steps: Int) {
        guard steps != 0 else { return }
        let key = effectiveKeySignature
        mutateSelectedEvent { event in
            switch event.type {
            case .note(let p):
                event.type = .note(pitch: Self.diatonicShift(p, steps: steps, key: key))
            case .chord(let ps):
                event.type = .chord(pitches: ps.map { Self.diatonicShift($0, steps: steps, key: key) })
            case .rest:
                return
            }
        }
    }

    /// Move a pitch by `steps` diatonic degrees along the staff ladder and spell the
    /// result with the accidental the key signature imposes on the landing letter.
    static func diatonicShift(_ pitch: Pitch, steps: Int, key: KeySignature) -> Pitch {
        let landing = Pitch.fromStaffPosition(pitch.staffPosition + steps)
        return Pitch(name: landing.name, octave: landing.octave,
                     accidental: key.accidental(for: landing.name))
    }

    /// MuseScore "J": respell the selected note/chord enharmonically — same sound,
    /// next notation (C♯ → D♭ → C♯). A chord respells every pitch.
    func respellSelectedEnharmonic() {
        mutateSelectedEvent { event in
            switch event.type {
            case .note(let p):
                event.type = .note(pitch: p.respelledEnharmonic())
            case .chord(let ps):
                event.type = .chord(pitches: ps.map { $0.respelledEnharmonic() })
            case .rest:
                return
            }
            event.showNatural = false
        }
    }

    /// MuseScore "add interval above" (Alt+3 = third, etc.): stack a note `steps`
    /// diatonic degrees above the top pitch of the selection, spelled by the key,
    /// turning a note into a chord. `steps` counts staff degrees (a third = 2).
    func addDiatonicIntervalAbove(steps: Int) {
        guard steps > 0 else { return }
        let key = effectiveKeySignature
        guard let event = selectedEvent, !event.isRest else { return }
        let topPitch: Pitch
        switch event.type {
        case .note(let p): topPitch = p
        case .chord(let ps):
            guard let hi = ps.max(by: { $0.staffPosition < $1.staffPosition }) else { return }
            topPitch = hi
        case .rest: return
        }
        addPitchToSelectedEvent(Self.diatonicShift(topPitch, steps: steps, key: key))
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

    /// MuseScore `→`: move the selection one note/rest forward, crossing into the
    /// next measure of the SAME staff at a bar boundary. No-op at the score end.
    /// Plain arrow drops any range — the moving focus becomes a single selection.
    func selectNextEvent() {
        clearRangeAnchor()
        moveFocusForward()
    }

    /// MuseScore `←`: move the selection one note/rest back, crossing into the
    /// previous measure of the SAME staff at a bar boundary. No-op at the score start.
    func selectPreviousEvent() {
        clearRangeAnchor()
        moveFocusBackward()
    }

    private func moveFocusForward() {
        guard let staff = currentStaff else { return }
        guard let idx = selectedEventIndex else {
            if let m = currentMeasure, !m.events.isEmpty {
                selectedEventIndex = 0
                selectedPitchIndex = nil
            }
            return
        }
        if let m = currentMeasure, idx + 1 < m.events.count {
            selectedEventIndex = idx + 1
            selectedPitchIndex = nil
            return
        }
        var mi = selectedMeasureIndex + 1
        while mi < staff.measures.count {
            if !staff.measures[mi].events.isEmpty {
                selectedMeasureIndex = mi
                selectedEventIndex = 0
                selectedPitchIndex = nil
                cursorPosition = 0
                return
            }
            mi += 1
        }
    }

    private func moveFocusBackward() {
        guard let staff = currentStaff else { return }
        guard let idx = selectedEventIndex else {
            if let m = currentMeasure, !m.events.isEmpty {
                selectedEventIndex = m.events.count - 1
                selectedPitchIndex = nil
            }
            return
        }
        if idx > 0 {
            selectedEventIndex = idx - 1
            selectedPitchIndex = nil
            return
        }
        var mi = selectedMeasureIndex - 1
        while mi >= 0 {
            if !staff.measures[mi].events.isEmpty {
                selectedMeasureIndex = mi
                selectedEventIndex = staff.measures[mi].events.count - 1
                selectedPitchIndex = nil
                cursorPosition = 0
                return
            }
            mi -= 1
        }
    }

    // MARK: - Range selection (MuseScore Shift+arrows / Ctrl+A / select measure)

    func clearRangeAnchor() {
        selectionAnchorMeasureIndex = nil
        selectionAnchorEventIndex = nil
    }

    private func ensureRangeAnchorAtFocus() {
        guard selectionAnchorMeasureIndex == nil else { return }
        selectionAnchorMeasureIndex = selectedMeasureIndex
        selectionAnchorEventIndex = selectedEventIndex
    }

    /// MuseScore `Shift+→`: grow the range one event forward, anchoring at the
    /// current focus on the first press. With no focus yet, seeds a selection.
    func extendSelectionForward() {
        guard selectedEventIndex != nil else { moveFocusForward(); return }
        ensureRangeAnchorAtFocus()
        moveFocusForward()
    }

    /// MuseScore `Shift+←`: grow the range one event backward.
    func extendSelectionBackward() {
        guard selectedEventIndex != nil else { moveFocusBackward(); return }
        ensureRangeAnchorAtFocus()
        moveFocusBackward()
    }

    /// MuseScore `Ctrl+Shift+Home/End`-style "select the whole current bar": anchor
    /// the range across every event of the focused measure.
    func selectCurrentMeasure() {
        guard let m = currentMeasure, !m.events.isEmpty else { return }
        selectionAnchorMeasureIndex = selectedMeasureIndex
        selectionAnchorEventIndex = 0
        selectedEventIndex = m.events.count - 1
        selectedPitchIndex = nil
    }

    /// MuseScore `Ctrl+A`: select the whole focused staff from its first event to
    /// its last, so copy/transpose/delete act on everything.
    func selectAll() {
        guard let staff = currentStaff, !staff.measures.isEmpty else { return }
        guard let firstM = staff.measures.firstIndex(where: { !$0.events.isEmpty }),
              let lastM = staff.measures.lastIndex(where: { !$0.events.isEmpty }) else { return }
        selectionAnchorMeasureIndex = firstM
        selectionAnchorEventIndex = 0
        selectedMeasureIndex = lastM
        selectedEventIndex = staff.measures[lastM].events.count - 1
        selectedPitchIndex = nil
    }

    /// Whether a multi-event range is active (not just a single focused event).
    var hasRangeSelection: Bool {
        guard let am = selectionAnchorMeasureIndex, let ae = selectionAnchorEventIndex,
              let fe = selectedEventIndex else { return false }
        return !(am == selectedMeasureIndex && ae == fe)
    }

    /// The `(measure, event)` positions covered by the current selection on the
    /// focused staff, ordered start→end. A single focused event yields one position;
    /// no focus yields none. Foundation for range copy/paste and multi-glyph highlight.
    var selectedRangePositions: [(measure: Int, event: Int)] {
        guard let staff = currentStaff, let fe = selectedEventIndex else { return [] }
        let fm = selectedMeasureIndex
        guard let am = selectionAnchorMeasureIndex, let ae = selectionAnchorEventIndex else {
            return [(fm, fe)]
        }
        // Order the two endpoints (measure-major, then event).
        let ordered = (am, ae) <= (fm, fe) ? ((am, ae), (fm, fe)) : ((fm, fe), (am, ae))
        let (lo, hi) = ordered
        var out: [(measure: Int, event: Int)] = []
        var mi = lo.0
        while mi <= hi.0 && mi < staff.measures.count {
            let count = staff.measures[mi].events.count
            let startE = mi == lo.0 ? lo.1 : 0
            let endE = mi == hi.0 ? hi.1 : count - 1
            if count > 0 {
                for e in max(0, startE)...min(count - 1, endE) { out.append((mi, e)) }
            }
            mi += 1
        }
        return out
    }

    /// Ids of every event in the current selection — used to recolour all selected
    /// glyphs in the Verovio SVG (MuseScore's blue range highlight).
    var selectedEventIDs: Set<UUID> {
        guard let staff = currentStaff else { return [] }
        var ids = Set<UUID>()
        for pos in selectedRangePositions where pos.measure < staff.measures.count {
            let events = staff.measures[pos.measure].events
            if pos.event < events.count { ids.insert(events[pos.event].id) }
        }
        return ids
    }

    /// Apply a mutation to every event in the current selection (a single focus or a
    /// whole range) on the focused staff, under one undo step. Foundation for range
    /// transpose/delete so MuseScore's "act on the blue range" holds.
    func mutateSelectedRange(_ mutate: (inout NoteEvent) -> Void) {
        let positions = selectedRangePositions
        guard !positions.isEmpty, isCurrentMeasurePathValid else { return }
        let p = selectedPartIndex, s = selectedStaffIndex
        saveUndoState()
        for pos in positions {
            guard pos.measure < score.parts[p].staves[s].measures.count,
                  pos.event < score.parts[p].staves[s].measures[pos.measure].events.count else { continue }
            mutate(&score.parts[p].staves[s].measures[pos.measure].events[pos.event])
        }
        score.touch()
    }

    /// MuseScore `↑/↓` on a selection: transpose every note/chord in the range by
    /// semitones together. Single focus falls through to the one-event path.
    func transposeSelection(semitones: Int) {
        guard hasRangeSelection else { transposeSelectedEvent(semitones: semitones); return }
        mutateSelectedRange { event in
            switch event.type {
            case .note(let pitch):
                let newMidi = pitch.midiNote + semitones
                guard newMidi >= 0, newMidi <= 127 else { return }
                event.type = .note(pitch: Pitch.fromMIDI(newMidi, preferFlats: semitones < 0))
            case .chord(let pitches):
                let transposed = pitches.compactMap { p -> Pitch? in
                    let newMidi = p.midiNote + semitones
                    guard newMidi >= 0, newMidi <= 127 else { return nil }
                    return Pitch.fromMIDI(newMidi, preferFlats: semitones < 0)
                }
                guard transposed.count == pitches.count else { return }
                event.type = .chord(pitches: transposed)
            case .rest:
                return
            }
        }
    }

    /// MuseScore `Delete` on a selection: replace every note/chord in the range with a
    /// rest of the same duration (rhythm preserved). Single focus falls through.
    func deleteSelection() {
        guard hasRangeSelection else { deleteSelectedEvent(); return }
        mutateSelectedRange { event in
            guard !event.isRest else { return }
            var rest = NoteEvent(type: .rest, duration: event.duration)
            rest.duration.dotted = event.duration.dotted
            rest.duration.doubleDotted = event.duration.doubleDotted
            event = rest
        }
        clearRangeAnchor()
        selectedEventIndex = nil
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

    /// MuseScore Ctrl+Shift+Delete: превратить текущий такт в полнотактовую паузу.
    /// Всё содержимое такта удаляется и заменяется одной целой паузой, которая
    /// рисуется по центру такта в любом размере (см. `Measure.isFullMeasureRest`).
    /// Голос активного ввода сохраняется. Одно действие вместо ручной очистки.
    func makeFullMeasureRest() {
        guard isCurrentMeasurePathValid else { return }
        saveUndoState()
        let pi = selectedPartIndex, si = selectedStaffIndex, mi = selectedMeasureIndex
        var rest = NoteEvent(type: .rest, duration: .wholeNote)
        rest.voice = selectedVoice
        score.parts[pi].staves[si].measures[mi].events = [rest]
        selectedEventIndex = nil
        selectedPitchIndex = nil
        cursorPosition = 0
        score.touch()
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
