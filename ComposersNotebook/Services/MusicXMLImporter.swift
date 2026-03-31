import Foundation

// MARK: - MusicXML Importer
// Parses MusicXML 4.0 partwise format into Score model

class MusicXMLImporter: NSObject, XMLParserDelegate {

    // MARK: - Public API

    /// Import MusicXML from file URL
    static func importFile(at url: URL) throws -> Score {
        let data = try Data(contentsOf: url)
        return try importData(data)
    }

    /// Import MusicXML from string
    static func importString(_ xml: String) throws -> Score {
        guard let data = xml.data(using: .utf8) else {
            throw MusicXMLImportError.invalidData
        }
        return try importData(data)
    }

    /// Import MusicXML from Data
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
        var events: [NoteInfo]
        var timeSignature: TimeSignature?
        var keySignature: KeySignature?
        var clef: Clef?
        var tempo: Double?
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

        case "measure":
            currentMeasure = MeasureInfo(events: [])

        case "note":
            currentNote = NoteInfo()
            isChordNote = false

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
            if let id = currentPartId {
                parts.append(PartInfo(id: id, measures: currentMeasures))
            }

        // Measure
        case "measure":
            if var m = currentMeasure {
                // Apply accumulated attributes
                if m.timeSignature == nil && currentMeasures.isEmpty {
                    m.timeSignature = TimeSignature(beats: currentBeats, beatValue: currentBeatType)
                }
                if m.keySignature == nil && currentMeasures.isEmpty {
                    m.keySignature = KeySignature(fifths: currentFifths, mode: currentMode == "minor" ? .minor : .major)
                }
                if m.clef == nil && currentMeasures.isEmpty {
                    m.clef = currentClef
                }
                currentMeasures.append(m)
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
                    // Will be refined by line element
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
            currentNote?.step = text
        case "octave":
            if elementStack.contains("pitch") {
                currentNote?.octave = Int(text) ?? 4
            }
        case "alter":
            currentNote?.alter = Int(Double(text) ?? 0)
        case "type":
            if elementStack.contains("note") {
                currentNote?.type = text
            }

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

        // Tempo
        case "per-minute":
            if let bpm = Double(text) {
                currentTempo = bpm
                currentMeasure?.tempo = bpm
            }

        // Note end
        case "note":
            if var note = currentNote {
                if note.hasFermata {
                    note.articulations.append(.fermata)
                }
                currentMeasure?.events.append(note)
            }
            currentNote = nil

        default:
            break
        }

        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
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

                // Group chord notes
                var events: [NoteEvent] = []
                var chordPitches: [Pitch] = []
                var chordBase: NoteInfo?

                for noteInfo in measureInfo.events {
                    if noteInfo.isChord, let base = chordBase {
                        // Add to existing chord
                        let pitch = pitchFromNote(noteInfo)
                        chordPitches.append(pitch)
                        _ = base // keep reference
                    } else {
                        // Flush previous chord if any
                        if let base = chordBase, !chordPitches.isEmpty {
                            let event = buildChordEvent(base: base, pitches: chordPitches)
                            events.append(event)
                            chordPitches = []
                            chordBase = nil
                        }

                        if noteInfo.isRest {
                            let event = buildRestEvent(noteInfo)
                            events.append(event)
                        } else {
                            // Start potential chord
                            chordBase = noteInfo
                            chordPitches = [pitchFromNote(noteInfo)]
                        }
                    }
                }

                // Flush last chord/note
                if let base = chordBase {
                    if chordPitches.count > 1 {
                        events.append(buildChordEvent(base: base, pitches: chordPitches))
                    } else if let pitch = chordPitches.first {
                        events.append(buildNoteEvent(base, pitch: pitch))
                    }
                }

                measure.events = events
                part.measures.append(measure)
            }

            // Ensure at least one measure
            if part.measures.isEmpty {
                part.measures.append(Measure.empty())
            }

            score.parts.append(part)
        }

        // Ensure at least one part
        if score.parts.isEmpty {
            score.parts.append(Part(instrument: .piano, measures: [Measure.empty()]))
        }

        return score
    }

    // MARK: - Helpers

    private func pitchFromNote(_ note: NoteInfo) -> Pitch {
        let name: PitchName = {
            switch note.step {
            case "C": return .C
            case "D": return .D
            case "E": return .E
            case "F": return .F
            case "G": return .G
            case "A": return .A
            case "B": return .B
            default: return .C
            }
        }()

        let accidental: Accidental = {
            switch note.alter {
            case -2: return .doubleFlat
            case -1: return .flat
            case 1: return .sharp
            case 2: return .doubleSharp
            default: return .natural
            }
        }()

        return Pitch(name: name, octave: note.octave, accidental: accidental)
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

    private func buildNoteEvent(_ info: NoteInfo, pitch: Pitch) -> NoteEvent {
        let duration = durationFromType(info.type, dotted: info.isDotted, doubleDotted: info.isDoubleDotted)
        var event = NoteEvent.note(pitch, duration: duration)
        event.articulations = info.articulations
        event.dynamic = info.dynamic
        event.tiedToNext = info.tiedStart
        event.slurStart = info.slurStart
        event.slurEnd = info.slurStop
        return event
    }

    private func buildRestEvent(_ info: NoteInfo) -> NoteEvent {
        let duration = durationFromType(info.type, dotted: info.isDotted, doubleDotted: info.isDoubleDotted)
        return NoteEvent.rest(duration: duration)
    }

    private func buildChordEvent(base: NoteInfo, pitches: [Pitch]) -> NoteEvent {
        let duration = durationFromType(base.type, dotted: base.isDotted, doubleDotted: base.isDoubleDotted)
        var event = NoteEvent.chord(pitches, duration: duration)
        event.articulations = base.articulations
        event.dynamic = base.dynamic
        event.tiedToNext = base.tiedStart
        event.slurStart = base.slurStart
        event.slurEnd = base.slurStop
        return event
    }

    private func instrumentFromMIDIProgram(_ program: Int, name: String) -> Instrument {
        // Try to match known instruments by MIDI program
        let presets: [Instrument] = [
            .piano, .violin, .viola, .cello, .doubleBass,
            .flute, .oboe, .clarinetBb, .bassoon,
            .hornF, .trumpet, .trombone, .tuba,
            .timpani, .piccolo,
            .soprano, .alto, .tenorVoice, .bassVoice
        ]

        // Match by MIDI program number
        if let match = presets.first(where: { $0.midiProgram == program }) {
            return match
        }

        // Match by name (case-insensitive partial match)
        let lowerName = name.lowercased()
        if let match = presets.first(where: {
            lowerName.contains($0.name.lowercased()) ||
            lowerName.contains($0.shortName.lowercased())
        }) {
            return match
        }

        // Default to piano
        return .piano
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
