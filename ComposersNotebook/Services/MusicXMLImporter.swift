import Foundation

// MARK: - MusicXML Importer
// Parses MusicXML 4.0 partwise format into Score model.
//
// Supports Phase 2c round-trip:
//   <harmony>          → NoteEvent.chordSymbol (attached to next non-chord note)
//   <time-modification> + <notations><tuplet> → NoteEvent.tuplet (with groupID)
//   <wedge>            → Measure.hairpins
//   <octave-shift>     → Measure.octaveShifts
//   <rehearsal>        → Measure.rehearsalMark
//   <words>            → Measure.expressionTexts | tempoChange | navigationMark (by text)
//   <ending>           → Measure.volta
//   <sound dacapo/dalsegno/coda/segno/fine> → Measure.navigationMark
//   <barline><repeat>  → Measure.barlineEnd (.repeatStart/.repeatEnd)
//   <technical><fingering> → NoteEvent.fingering
//
// Limitations:
// - Spanners (hairpin, octave-shift) crossing measure boundaries are clipped
//   to the measure where their <stop> appears (start beat = 0 in that measure).
// - Tempo change endBPM is estimated from current tempo ± direction*20 BPM when
//   not provided by the source — MusicXML does not encode the target BPM directly.

class MusicXMLImporter: NSObject, XMLParserDelegate {

    // MARK: - Public API

    static func importFile(at url: URL) throws -> Score {
        let data = try Data(contentsOf: url)
        return try importData(data)
    }

    static func importString(_ xml: String) throws -> Score {
        guard let data = xml.data(using: .utf8) else {
            throw MusicXMLImportError.invalidData
        }
        return try importData(data)
    }

    static func importData(_ data: Data) throws -> Score {
        let importer = MusicXMLImporter()
        let parser = XMLParser(data: data)
        parser.delegate = importer
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw importer.parseError ?? MusicXMLImportError.parseFailed
        }

        return importer.buildScore()
    }

    // MARK: - Parser State

    private var parseError: Error?

    // Score-level
    private var title = ""
    private var composer = ""
    private var parts: [PartInfo] = []
    private var currentPartId: String?

    // Part list
    private var partListEntries: [PartListEntry] = []
    private var currentPartListId: String?
    private var currentPartName = ""
    private var currentMidiProgram: Int = 0

    // Measure parsing
    private var currentMeasures: [MeasureInfo] = []
    private var currentMeasure: MeasureInfo?

    // Position inside current measure (in beats from start of measure)
    private var currentBeatInMeasure: Double = 0

    // Note parsing
    private var currentNote: NoteInfo?
    private var isChordNote = false

    // Attributes
    private var currentDivisions: Int = 4
    private var currentFifths: Int = 0
    private var currentMode: String = "major"
    private var currentBeats: Int = 4
    private var currentBeatType: Int = 4
    private var currentClef: Clef = .treble
    private var currentTempo: Double = 120

    // Element text
    private var currentText = ""
    private var elementStack: [String] = []

    // --- Phase 2c parsing state ---

    // Harmony accumulator (<harmony> appears before the note it attaches to)
    private var inHarmony = false
    private var pendingHarmonyRoot: PitchName?
    private var pendingHarmonyRootAcc: Accidental = .natural
    private var pendingHarmonyKindText: String = ""
    private var pendingHarmonyBass: PitchName?
    private var pendingHarmonyBassAcc: Accidental?
    private var pendingChordSymbol: ChordSymbol?

    // Tuplet accumulator for current note
    private var currentTupletActual: Int?
    private var currentTupletNormal: Int?
    private var currentTupletStartType = false
    private var currentTupletStopType = false

    // Active tuplet group (across notes)
    private var activeTupletGroupID: UUID?
    private var activeTupletActualCount: Int = 0
    private var activeTupletNormalCount: Int = 2
    private var activeTupletPositionInGroup: Int = -1

    // Fingering for current note
    private var currentNoteFingering: String?

    // Direction accumulator
    private var inDirection = false
    private var currentWordsText: String = ""
    private var currentWordsIsItalic = false
    private var pendingWedgeType: String = ""        // "crescendo" / "diminuendo" / "stop"
    private var pendingOctaveShiftType: String = ""  // "up" / "down" / "stop"
    private var pendingOctaveShiftSize: Int = 8
    private var pendingRehearsalText: String = ""
    private var pendingRehearsalIsBoxed = true
    // Sound element attributes (can appear inside direction or standalone)
    private var pendingSoundDacapo = false
    private var pendingSoundDalsegno = false
    private var pendingSoundCoda = false
    private var pendingSoundSegno = false
    private var pendingSoundFine = false

    // Open spanners (live across measures until <stop> seen)
    private var openHairpinType: HairpinType?
    private var openHairpinStartMeasureIdx: Int = -1
    private var openHairpinStartBeat: Double = 0
    private var openOctaveShiftKind: OctaveShiftKind?
    private var openOctaveShiftStartMeasureIdx: Int = -1
    private var openOctaveShiftStartBeat: Double = 0

    // Volta tracking — open ending span across measures
    private var openVoltaNumber: Int?
    private var openVoltaStartMeasureIdx: Int = -1
    private var pendingVoltaEndAfterMeasure = false  // set when type="stop" seen

    // Barline accumulator (for current <barline> element)
    private var currentBarlineLocation: String = "right"
    private var currentBarStyle: String = ""
    private var currentRepeatDirection: String = ""

    // MARK: - Data Structures

    private struct PartListEntry {
        let id: String
        let name: String
        let midiProgram: Int
    }

    private struct PartInfo {
        let id: String
        var measures: [MeasureInfo]
    }

    private struct MeasureInfo {
        var events: [NoteInfo] = []
        var timeSignature: TimeSignature?
        var keySignature: KeySignature?
        var clef: Clef?
        var tempo: Double?
        var hairpins: [Hairpin] = []
        var octaveShifts: [OctaveShift] = []
        var rehearsalMark: RehearsalMark?
        var expressionTexts: [ExpressionText] = []
        var tempoChange: TempoChange?
        var navigationMark: NavigationMark?
        var barlineEnd: BarlineType = .regular
        var volta: Volta?
    }

    private struct NoteInfo {
        var isRest: Bool = false
        var isChord: Bool = false
        var step: String = "C"
        var octave: Int = 4
        var alter: Int = 0
        var duration: Int = 4 // in divisions
        var type: String = "quarter"
        var isDotted: Bool = false
        var isDoubleDotted: Bool = false
        var tiedStart: Bool = false
        var tiedStop: Bool = false
        var slurStart: Bool = false
        var slurStop: Bool = false
        var articulations: [Articulation] = []
        var dynamic: DynamicMarking?
        var hasFermata: Bool = false
        // Phase 2c
        var tuplet: Tuplet?
        var chordSymbol: ChordSymbol?
        var fingering: String?
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "score-part":
            currentPartListId = attributes["id"]
            currentPartName = ""
            currentMidiProgram = 0

        case "part":
            currentPartId = attributes["id"]
            currentMeasures = []
            // Reset per-part open spanners — they don't cross parts.
            closeAllOpenSpanners()

        case "measure":
            currentMeasure = MeasureInfo()
            currentBeatInMeasure = 0

        case "harmony":
            inHarmony = true
            pendingHarmonyRoot = nil
            pendingHarmonyRootAcc = .natural
            pendingHarmonyKindText = ""
            pendingHarmonyBass = nil
            pendingHarmonyBassAcc = nil

        case "direction":
            inDirection = true
            currentWordsText = ""
            currentWordsIsItalic = false
            pendingWedgeType = ""
            pendingOctaveShiftType = ""
            pendingOctaveShiftSize = 8
            pendingRehearsalText = ""
            pendingRehearsalIsBoxed = true
            pendingSoundDacapo = false
            pendingSoundDalsegno = false
            pendingSoundCoda = false
            pendingSoundSegno = false
            pendingSoundFine = false

        case "words":
            currentWordsIsItalic = (attributes["font-style"] == "italic")

        case "wedge":
            pendingWedgeType = attributes["type"] ?? ""

        case "octave-shift":
            pendingOctaveShiftType = attributes["type"] ?? ""
            pendingOctaveShiftSize = Int(attributes["size"] ?? "8") ?? 8

        case "rehearsal":
            pendingRehearsalIsBoxed = (attributes["enclosure"] != "none")

        case "sound":
            if attributes["dacapo"] == "yes" { pendingSoundDacapo = true }
            if let ds = attributes["dalsegno"], !ds.isEmpty { pendingSoundDalsegno = true }
            if let c = attributes["coda"], !c.isEmpty { pendingSoundCoda = true }
            if let s = attributes["segno"], !s.isEmpty { pendingSoundSegno = true }
            if attributes["fine"] == "yes" { pendingSoundFine = true }
            // Some files put <sound tempo="120"> — fold into measure tempo.
            if let t = attributes["tempo"], let bpm = Double(t) {
                currentTempo = bpm
                currentMeasure?.tempo = bpm
            }

        case "ending":
            if let numStr = attributes["number"], let num = Int(numStr.split(separator: ",").first ?? "1") {
                let type = attributes["type"] ?? ""
                if type == "start" {
                    openVoltaNumber = num
                    openVoltaStartMeasureIdx = currentMeasures.count
                } else if type == "stop" || type == "discontinue" {
                    pendingVoltaEndAfterMeasure = true
                }
            }

        case "barline":
            currentBarlineLocation = attributes["location"] ?? "right"
            currentBarStyle = ""
            currentRepeatDirection = ""

        case "repeat":
            currentRepeatDirection = attributes["direction"] ?? ""

        case "note":
            currentNote = NoteInfo()
            isChordNote = false
            currentTupletActual = nil
            currentTupletNormal = nil
            currentTupletStartType = false
            currentTupletStopType = false
            currentNoteFingering = nil

        case "rest":
            currentNote?.isRest = true

        case "chord":
            currentNote?.isChord = true
            isChordNote = true

        case "dot":
            if currentNote?.isDotted == true {
                currentNote?.isDoubleDotted = true
            } else {
                currentNote?.isDotted = true
            }

        case "tied":
            if let type = attributes["type"] {
                if type == "start" { currentNote?.tiedStart = true }
                if type == "stop" { currentNote?.tiedStop = true }
            }

        case "slur":
            if let type = attributes["type"] {
                if type == "start" { currentNote?.slurStart = true }
                if type == "stop" { currentNote?.slurStop = true }
            }

        case "tuplet":
            // <notations><tuplet number="1" type="start|stop"/>
            if let type = attributes["type"] {
                if type == "start" { currentTupletStartType = true }
                if type == "stop" { currentTupletStopType = true }
            }

        case "staccato": currentNote?.articulations.append(.staccato)
        case "accent": currentNote?.articulations.append(.accent)
        case "tenuto": currentNote?.articulations.append(.tenuto)
        case "strong-accent": currentNote?.articulations.append(.marcato)
        case "fermata": currentNote?.hasFermata = true

        case "dynamics":
            break // child element will set the value

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        // Score metadata
        case "work-title":
            title = text
        case "creator":
            if elementStack.contains("identification") {
                composer = text
            }

        // Part list
        case "part-name":
            currentPartName = text
        case "midi-program":
            currentMidiProgram = Int(text) ?? 1
        case "score-part":
            if let id = currentPartListId {
                partListEntries.append(PartListEntry(
                    id: id,
                    name: currentPartName,
                    midiProgram: max(0, currentMidiProgram - 1) // MusicXML is 1-based
                ))
            }

        // Part
        case "part":
            // Close any spanners still open at end of part.
            closeAllOpenSpanners()
            if let id = currentPartId {
                parts.append(PartInfo(id: id, measures: currentMeasures))
            }

        // Measure
        case "measure":
            if var m = currentMeasure {
                if m.timeSignature == nil && currentMeasures.isEmpty {
                    m.timeSignature = TimeSignature(beats: currentBeats, beatValue: currentBeatType)
                }
                if m.keySignature == nil && currentMeasures.isEmpty {
                    m.keySignature = KeySignature(fifths: currentFifths, mode: currentMode == "minor" ? .minor : .major)
                }
                if m.clef == nil && currentMeasures.isEmpty {
                    m.clef = currentClef
                }
                // Apply volta on this measure if span is open.
                if let voltaNum = openVoltaNumber {
                    m.volta = Volta(
                        number: voltaNum,
                        startMeasure: openVoltaStartMeasureIdx,
                        endMeasure: currentMeasures.count
                    )
                }
                currentMeasures.append(m)
                // Close volta after the measure that contained <ending type="stop">.
                if pendingVoltaEndAfterMeasure {
                    openVoltaNumber = nil
                    openVoltaStartMeasureIdx = -1
                    pendingVoltaEndAfterMeasure = false
                }
                currentMeasure = nil
            }

        // Attributes
        case "divisions":
            currentDivisions = Int(text) ?? 4
        case "fifths":
            currentFifths = Int(text) ?? 0
            currentMeasure?.keySignature = KeySignature(
                fifths: currentFifths,
                mode: currentMode == "minor" ? .minor : .major
            )
        case "mode":
            currentMode = text
            if let ks = currentMeasure?.keySignature {
                currentMeasure?.keySignature = KeySignature(
                    fifths: ks.fifths,
                    mode: text == "minor" ? .minor : .major
                )
            }
        case "beats":
            if elementStack.contains("time") {
                currentBeats = Int(text) ?? 4
            }
        case "beat-type":
            currentBeatType = Int(text) ?? 4
            currentMeasure?.timeSignature = TimeSignature(
                beats: currentBeats, beatValue: currentBeatType
            )
        case "sign":
            if elementStack.contains("clef") {
                switch text {
                case "G": currentClef = .treble
                case "F": currentClef = .bass
                case "C":
                    currentClef = .alto
                default: break
                }
                currentMeasure?.clef = currentClef
            }
        case "line":
            if elementStack.contains("clef") {
                if currentClef == .alto, text == "4" {
                    currentClef = .tenor
                    currentMeasure?.clef = .tenor
                }
            }

        // Note elements
        case "step":
            if inHarmony && elementStack.contains("root") {
                pendingHarmonyRoot = PitchName.fromEnglishName(text) ?? .C
            } else if inHarmony && elementStack.contains("bass") {
                pendingHarmonyBass = PitchName.fromEnglishName(text) ?? .C
            } else {
                currentNote?.step = text
            }
        case "root-step":
            pendingHarmonyRoot = PitchName.fromEnglishName(text) ?? .C
        case "bass-step":
            pendingHarmonyBass = PitchName.fromEnglishName(text) ?? .C
        case "octave":
            if elementStack.contains("pitch") {
                currentNote?.octave = Int(text) ?? 4
            }
        case "alter":
            if inHarmony && elementStack.contains("root") {
                pendingHarmonyRootAcc = accidentalFromAlter(Int(Double(text) ?? 0))
            } else if inHarmony && elementStack.contains("bass") {
                pendingHarmonyBassAcc = accidentalFromAlter(Int(Double(text) ?? 0))
            } else {
                currentNote?.alter = Int(Double(text) ?? 0)
            }
        case "root-alter":
            pendingHarmonyRootAcc = accidentalFromAlter(Int(Double(text) ?? 0))
        case "bass-alter":
            pendingHarmonyBassAcc = accidentalFromAlter(Int(Double(text) ?? 0))
        case "kind":
            if inHarmony {
                pendingHarmonyKindText = text
            }
        case "type":
            if elementStack.contains("note") {
                currentNote?.type = text
            }

        case "actual-notes":
            if elementStack.contains("time-modification") {
                currentTupletActual = Int(text)
            }
        case "normal-notes":
            if elementStack.contains("time-modification") {
                currentTupletNormal = Int(text)
            }

        case "fingering":
            if elementStack.contains("technical") {
                currentNoteFingering = text
            }

        // Words / rehearsal text
        case "words":
            // Multiple <words> may appear in one direction — concatenate with space.
            if !currentWordsText.isEmpty { currentWordsText += " " }
            currentWordsText += text
        case "rehearsal":
            pendingRehearsalText = text

        // Barline children
        case "bar-style":
            currentBarStyle = text

        case "barline":
            applyBarline()

        // Dynamics
        case "ppp": currentNote?.dynamic = .ppp
        case "pp": currentNote?.dynamic = .pp
        case "p":
            if elementStack.contains("dynamics") { currentNote?.dynamic = .p }
        case "mp": currentNote?.dynamic = .mp
        case "mf": currentNote?.dynamic = .mf
        case "f":
            if elementStack.contains("dynamics") { currentNote?.dynamic = .f }
        case "ff": currentNote?.dynamic = .ff
        case "fff": currentNote?.dynamic = .fff
        case "sfz": currentNote?.dynamic = .sfz

        // Tempo (from <metronome><per-minute>)
        case "per-minute":
            if let bpm = Double(text) {
                currentTempo = bpm
                currentMeasure?.tempo = bpm
            }

        case "harmony":
            inHarmony = false
            if let root = pendingHarmonyRoot {
                pendingChordSymbol = ChordSymbol(
                    root: root,
                    rootAccidental: pendingHarmonyRootAcc,
                    quality: chordQualityFromKindText(pendingHarmonyKindText),
                    bassNote: pendingHarmonyBass,
                    bassAccidental: pendingHarmonyBassAcc
                )
            }

        case "direction":
            applyDirection()
            inDirection = false

        // Note end
        case "note":
            if var note = currentNote {
                if note.hasFermata {
                    note.articulations.append(.fermata)
                }
                // Apply tuplet info if present.
                applyTuplet(to: &note)
                // Attach chord symbol if pending (only to first note of a chord stack).
                if !note.isChord, let cs = pendingChordSymbol {
                    note.chordSymbol = cs
                    pendingChordSymbol = nil
                }
                // Fingering.
                if let f = currentNoteFingering {
                    note.fingering = f
                }
                currentMeasure?.events.append(note)

                // Advance beat counter ONLY for the head of a stack (not chord additions).
                if !note.isChord {
                    let baseBeats = beatsForType(note.type, dotted: note.isDotted, doubleDotted: note.isDoubleDotted)
                    let multiplier = note.tuplet?.durationMultiplier ?? 1.0
                    currentBeatInMeasure += baseBeats * multiplier
                }
            }
            currentNote = nil

        default:
            break
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Direction Application

    private func applyDirection() {
        guard var m = currentMeasure else { return }
        let words = currentWordsText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Navigation marks via <words> text (highest priority).
        if let nav = navigationMarkFromWords(words) {
            m.navigationMark = nav
        }
        // 2. Tempo change via <words> text (accel., rit., rall., string., allarg.).
        else if let kind = tempoChangeKindFromWords(words) {
            let startBeat = currentBeatInMeasure
            let totalBeats = Double(currentBeats)
            let endBeat = max(startBeat + 1, totalBeats)
            let targetBPM = currentTempo + Double(kind.direction) * 20
            m.tempoChange = TempoChange(
                kind: kind,
                startBeat: startBeat,
                endBeat: endBeat,
                startBPM: currentTempo,
                endBPM: targetBPM
            )
        }
        // 3. Plain expression text.
        else if !words.isEmpty {
            m.expressionTexts.append(ExpressionText(
                text: words,
                italianTerm: currentWordsIsItalic,
                attachToBeat: currentBeatInMeasure
            ))
        }

        // 4. Rehearsal mark.
        let rehearsalText = pendingRehearsalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rehearsalText.isEmpty {
            m.rehearsalMark = RehearsalMark(
                text: rehearsalText,
                style: pendingRehearsalIsBoxed ? .boxed : .plain
            )
        }

        // 5. Wedge → Hairpin spanner.
        switch pendingWedgeType {
        case "crescendo":
            openHairpinType = .crescendo
            openHairpinStartMeasureIdx = currentMeasures.count
            openHairpinStartBeat = currentBeatInMeasure
        case "diminuendo":
            openHairpinType = .diminuendo
            openHairpinStartMeasureIdx = currentMeasures.count
            openHairpinStartBeat = currentBeatInMeasure
        case "stop":
            if let type = openHairpinType {
                let startBeat: Double
                if openHairpinStartMeasureIdx == currentMeasures.count {
                    startBeat = openHairpinStartBeat
                } else {
                    // Crossed boundary — record only the slice in this measure.
                    startBeat = 0
                }
                m.hairpins.append(Hairpin(
                    type: type,
                    startBeat: startBeat,
                    endBeat: currentBeatInMeasure
                ))
                openHairpinType = nil
            }
        default:
            break
        }

        // 6. Octave-shift → OctaveShift spanner.
        if !pendingOctaveShiftType.isEmpty {
            switch pendingOctaveShiftType {
            case "up", "down":
                let kind = octaveShiftKindFrom(type: pendingOctaveShiftType, size: pendingOctaveShiftSize)
                openOctaveShiftKind = kind
                openOctaveShiftStartMeasureIdx = currentMeasures.count
                openOctaveShiftStartBeat = currentBeatInMeasure
            case "stop":
                if let kind = openOctaveShiftKind {
                    let startBeat: Double
                    if openOctaveShiftStartMeasureIdx == currentMeasures.count {
                        startBeat = openOctaveShiftStartBeat
                    } else {
                        startBeat = 0
                    }
                    m.octaveShifts.append(OctaveShift(
                        kind: kind,
                        startBeat: startBeat,
                        endBeat: currentBeatInMeasure
                    ))
                    openOctaveShiftKind = nil
                }
            default:
                break
            }
        }

        // 7. Sound flags → NavigationMark (only if words didn't already set one).
        if m.navigationMark == nil {
            if pendingSoundFine {
                m.navigationMark = .fine
            } else if pendingSoundDacapo {
                m.navigationMark = .dcAlFine
            } else if pendingSoundDalsegno {
                m.navigationMark = .dsAlFine
            } else if pendingSoundCoda {
                m.navigationMark = .coda
            } else if pendingSoundSegno {
                m.navigationMark = .segno
            }
        }

        currentMeasure = m
    }

    private func applyBarline() {
        guard var m = currentMeasure else { return }

        // Repeat takes priority.
        if currentRepeatDirection == "forward" {
            // Reprise opens at left side of this measure.
            m.barlineEnd = .repeatStart
        } else if currentRepeatDirection == "backward" {
            // Reprise closes at right side of this measure.
            m.barlineEnd = .repeatEnd
        } else {
            // Plain bar-style — only set if not regular.
            switch currentBarStyle {
            case "light-light": m.barlineEnd = .double
            case "light-heavy": m.barlineEnd = .final_
            case "heavy-light": m.barlineEnd = .repeatStart
            default: break
            }
        }

        currentMeasure = m
    }

    // MARK: - Tuplet Application

    private func applyTuplet(to note: inout NoteInfo) {
        guard let actual = currentTupletActual, let normal = currentTupletNormal else {
            return
        }

        if currentTupletStartType || activeTupletGroupID == nil {
            activeTupletGroupID = UUID()
            activeTupletActualCount = actual
            activeTupletNormalCount = normal
            activeTupletPositionInGroup = 0
        } else {
            activeTupletPositionInGroup += 1
        }

        if let gid = activeTupletGroupID {
            note.tuplet = Tuplet(
                actualCount: activeTupletActualCount,
                normalCount: activeTupletNormalCount,
                groupID: gid,
                positionInGroup: min(activeTupletPositionInGroup, activeTupletActualCount - 1)
            )
        }

        if currentTupletStopType || activeTupletPositionInGroup >= activeTupletActualCount - 1 {
            activeTupletGroupID = nil
            activeTupletPositionInGroup = -1
        }
    }

    private func closeAllOpenSpanners() {
        openHairpinType = nil
        openHairpinStartMeasureIdx = -1
        openOctaveShiftKind = nil
        openOctaveShiftStartMeasureIdx = -1
        openVoltaNumber = nil
        openVoltaStartMeasureIdx = -1
        pendingVoltaEndAfterMeasure = false
        activeTupletGroupID = nil
        activeTupletPositionInGroup = -1
        pendingChordSymbol = nil
    }

    // MARK: - Build Score

    private func buildScore() -> Score {
        var score = Score(
            title: title.isEmpty ? "Imported Score" : title,
            composer: composer,
            parts: [],
            tempo: TempoMarking(bpm: currentTempo),
            timeSignature: TimeSignature(beats: currentBeats, beatValue: currentBeatType),
            keySignature: KeySignature(fifths: currentFifths, mode: currentMode == "minor" ? .minor : .major)
        )

        for partInfo in parts {
            let entry = partListEntries.first { $0.id == partInfo.id }
            let instrument = instrumentFromMIDIProgram(
                entry?.midiProgram ?? 0,
                name: entry?.name ?? "Piano"
            )

            var part = Part(instrument: instrument, measures: [])
            let defaultClef = partInfo.measures.first?.clef ?? instrument.defaultClef
            part.clef = defaultClef

            for measureInfo in partInfo.measures {
                var measure = Measure.empty()
                measure.timeSignature = measureInfo.timeSignature
                measure.keySignature = measureInfo.keySignature
                measure.clefChange = measureInfo.clef

                if let bpm = measureInfo.tempo {
                    measure.tempoMarking = TempoMarking(bpm: bpm)
                }

                // Measure-level Phase 2c data.
                measure.hairpins = measureInfo.hairpins
                measure.octaveShifts = measureInfo.octaveShifts
                measure.rehearsalMark = measureInfo.rehearsalMark
                measure.expressionTexts = measureInfo.expressionTexts
                measure.tempoChange = measureInfo.tempoChange
                measure.navigationMark = measureInfo.navigationMark
                measure.barlineEnd = measureInfo.barlineEnd
                measure.volta = measureInfo.volta

                // Group chord notes.
                var events: [NoteEvent] = []
                var chordPitches: [Pitch] = []
                var chordBase: NoteInfo?

                for noteInfo in measureInfo.events {
                    if noteInfo.isChord, let base = chordBase {
                        let pitch = pitchFromNote(noteInfo)
                        chordPitches.append(pitch)
                        _ = base
                    } else {
                        // Flush previous chord/note.
                        if let base = chordBase, !chordPitches.isEmpty {
                            let event = buildChordOrNoteEvent(base: base, pitches: chordPitches)
                            events.append(event)
                            chordPitches = []
                            chordBase = nil
                        }

                        if noteInfo.isRest {
                            events.append(buildRestEvent(noteInfo))
                        } else {
                            chordBase = noteInfo
                            chordPitches = [pitchFromNote(noteInfo)]
                        }
                    }
                }

                // Flush trailing chord/note.
                if let base = chordBase {
                    events.append(buildChordOrNoteEvent(base: base, pitches: chordPitches))
                }

                measure.events = events
                part.measures.append(measure)
            }

            if part.measures.isEmpty {
                part.measures.append(Measure.empty())
            }

            score.parts.append(part)
        }

        if score.parts.isEmpty {
            score.parts.append(Part(instrument: .piano, measures: [Measure.empty()]))
        }

        return score
    }

    // MARK: - Helpers

    private func pitchFromNote(_ note: NoteInfo) -> Pitch {
        let name = PitchName.fromEnglishName(note.step) ?? .C
        let accidental = accidentalFromAlter(note.alter)
        return Pitch(name: name, octave: note.octave, accidental: accidental)
    }

    private func accidentalFromAlter(_ alter: Int) -> Accidental {
        switch alter {
        case -2: return .doubleFlat
        case -1: return .flat
        case 1: return .sharp
        case 2: return .doubleSharp
        default: return .natural
        }
    }

    private func durationFromType(_ type: String, dotted: Bool, doubleDotted: Bool) -> Duration {
        let value: DurationValue = {
            switch type {
            case "whole": return .whole
            case "half": return .half
            case "quarter": return .quarter
            case "eighth": return .eighth
            case "16th": return .sixteenth
            case "32nd": return .thirtySecond
            default: return .quarter
            }
        }()
        return Duration(value: value, dotted: dotted, doubleDotted: doubleDotted)
    }

    private func beatsForType(_ type: String, dotted: Bool, doubleDotted: Bool) -> Double {
        return durationFromType(type, dotted: dotted, doubleDotted: doubleDotted).beats
    }

    private func buildNoteEvent(_ info: NoteInfo, pitch: Pitch) -> NoteEvent {
        let duration = durationFromType(info.type, dotted: info.isDotted, doubleDotted: info.isDoubleDotted)
        var event = NoteEvent.note(pitch, duration: duration)
        event.articulations = info.articulations
        event.dynamic = info.dynamic
        event.tiedToNext = info.tiedStart
        event.slurStart = info.slurStart
        event.slurEnd = info.slurStop
        event.tuplet = info.tuplet
        event.chordSymbol = info.chordSymbol
        event.fingering = info.fingering
        return event
    }

    private func buildRestEvent(_ info: NoteInfo) -> NoteEvent {
        let duration = durationFromType(info.type, dotted: info.isDotted, doubleDotted: info.isDoubleDotted)
        return NoteEvent.rest(duration: duration)
    }

    private func buildChordOrNoteEvent(base: NoteInfo, pitches: [Pitch]) -> NoteEvent {
        let duration = durationFromType(base.type, dotted: base.isDotted, doubleDotted: base.isDoubleDotted)
        var event: NoteEvent
        if pitches.count > 1 {
            event = NoteEvent.chord(pitches, duration: duration)
        } else if let pitch = pitches.first {
            event = NoteEvent.note(pitch, duration: duration)
        } else {
            event = NoteEvent.rest(duration: duration)
        }
        event.articulations = base.articulations
        event.dynamic = base.dynamic
        event.tiedToNext = base.tiedStart
        event.slurStart = base.slurStart
        event.slurEnd = base.slurStop
        event.tuplet = base.tuplet
        event.chordSymbol = base.chordSymbol
        event.fingering = base.fingering
        return event
    }

    private func instrumentFromMIDIProgram(_ program: Int, name: String) -> Instrument {
        let presets: [Instrument] = [
            .piano, .violin, .viola, .cello, .doubleBass,
            .flute, .oboe, .clarinetBb, .bassoon,
            .hornF, .trumpet, .trombone, .tuba,
            .timpani, .piccolo,
            .soprano, .alto, .tenorVoice, .bassVoice
        ]

        if let match = presets.first(where: { $0.midiProgram == program }) {
            return match
        }

        let lowerName = name.lowercased()
        if let match = presets.first(where: {
            lowerName.contains($0.name.lowercased()) ||
            lowerName.contains($0.shortName.lowercased())
        }) {
            return match
        }

        return .piano
    }

    // MARK: - Chord quality mapping (MusicXML <kind> → ChordSymbol.Quality)

    private func chordQualityFromKindText(_ kind: String) -> ChordSymbol.Quality {
        switch kind {
        case "major": return .major
        case "minor": return .minor
        case "diminished": return .diminished
        case "augmented": return .augmented
        case "dominant", "dominant-seventh": return .dominant7
        case "major-seventh": return .major7
        case "minor-seventh": return .minor7
        case "minor-major-seventh", "major-minor": return .minorMajor7
        case "diminished-seventh": return .diminished7
        case "half-diminished": return .halfDiminished
        case "dominant-ninth", "dominant-9th": return .dominant9
        case "major-ninth", "major-9th": return .major9
        case "minor-ninth", "minor-9th": return .minor9
        case "dominant-11th": return .dominant11
        case "dominant-13th": return .dominant13
        case "sixth", "major-sixth": return .sixth
        case "minor-sixth": return .minorSixth
        case "suspended-second": return .sus2
        case "suspended-fourth": return .sus4
        case "power": return .fifth
        default: return .major
        }
    }

    // MARK: - Direction text → semantic mapping

    private func navigationMarkFromWords(_ text: String) -> NavigationMark? {
        // Exact symbol match.
        switch text {
        case "𝄋": return .segno
        case "𝄌": return .coda
        case "D.C. al Fine": return .dcAlFine
        case "D.C. al Coda": return .dcAlCoda
        case "D.S. al Fine": return .dsAlFine
        case "D.S. al Coda": return .dsAlCoda
        case "Fine": return .fine
        default:
            break
        }
        // Loose matches (case-insensitive prefix) — handles slight typography variants.
        let lower = text.lowercased()
        if lower == "d.c." || lower == "da capo" { return .dcAlFine }
        if lower == "d.s." || lower == "dal segno" { return .dsAlFine }
        if lower == "segno" { return .segno }
        if lower == "coda" { return .coda }
        if lower == "fine" { return .fine }
        return nil
    }

    private func tempoChangeKindFromWords(_ text: String) -> TempoChange.Kind? {
        let lower = text.lowercased()
        if lower.hasPrefix("accel") { return .accelerando }
        if lower.hasPrefix("rit") { return .ritardando }
        if lower.hasPrefix("rall") { return .rallentando }
        if lower.hasPrefix("string") { return .stringendo }
        if lower.hasPrefix("allarg") { return .allargando }
        return nil
    }

    private func octaveShiftKindFrom(type: String, size: Int) -> OctaveShiftKind {
        switch (type, size) {
        case ("up", 8): return .ottavaAlta
        case ("down", 8): return .ottavaBassa
        case ("up", 15): return .quindicesimaAlta
        case ("down", 15): return .quindicesimaBassa
        default: return .ottavaAlta
        }
    }
}

// MARK: - Errors

enum MusicXMLImportError: LocalizedError {
    case invalidData
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid MusicXML data."
        case .parseFailed: return "Failed to parse MusicXML file."
        }
    }
}
