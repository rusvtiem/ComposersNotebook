import Foundation

// MARK: - MEI (Music Encoding Initiative) Importer
// Supports MEI XML format (.mei)
// Reference: https://music-encoding.org/

class MEIImporter {

    enum MEIError: Error, LocalizedError {
        case invalidFile
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Невалидный MEI файл"
            case .parseError(let msg): return "Ошибка разбора MEI: \(msg)"
            }
        }
    }

    // MARK: - Public API

    static func importFile(at url: URL) throws -> Score {
        let data = try Data(contentsOf: url)
        return try importData(data)
    }

    static func importData(_ data: Data) throws -> Score {
        let parser = MEIParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldResolveExternalEntities = false
        guard xmlParser.parse() else {
            throw MEIError.parseError("XML parsing failed")
        }
        return parser.buildScore()
    }
}

// MARK: - MEI XML Parser

private class MEIParser: NSObject, XMLParserDelegate {

    // Score metadata
    private var title = ""
    private var composer = ""

    // Parsing state
    private var currentText = ""
    private var elementStack: [String] = []

    // Musical content
    private var staffDefs: [MEIStaffDef] = []
    private var currentStaffDef: MEIStaffDef?
    private var measures: [MEIMeasure] = []
    private var currentMeasure: MEIMeasure?
    private var currentStaff: MEIStaff?
    private var currentLayer: MEILayer?
    private var currentNote: MEINoteData?
    private var currentChordNotes: [MEINoteData] = []
    private var inChord = false

    // Intermediate structures
    private struct MEIStaffDef {
        var n: Int = 1
        var label: String = ""
        var lines: Int = 5
        var clef: String = "G"
        var meterCount: Int = 4
        var meterUnit: Int = 4
        var keySig: String = ""
    }

    private struct MEIMeasure {
        var n: Int = 0
        var staves: [MEIStaff] = []
    }

    private struct MEIStaff {
        var n: Int = 1
        var layers: [MEILayer] = []
    }

    private struct MEILayer {
        var n: Int = 1
        var events: [MEIEvent] = []
    }

    private enum MEIEvent {
        case note(MEINoteData)
        case rest(MEIRestData)
        case chord([MEINoteData], dur: String)
    }

    private struct MEINoteData {
        var pname: String = "c"  // pitch name: c, d, e, f, g, a, b
        var oct: Int = 4
        var dur: String = "4"    // duration: 1=whole, 2=half, 4=quarter, 8=eighth, 16=sixteenth
        var accid: String = ""   // s=sharp, f=flat, n=natural, ss=double-sharp, ff=double-flat
        var dots: Int = 0
        var tie: String = ""     // i=initial, t=terminal, m=medial
        var artic: String = ""
    }

    private struct MEIRestData {
        var dur: String = "4"
        var dots: Int = 0
    }

    func buildScore() -> Score {
        var score = Score(
            title: title.isEmpty ? "MEI Import" : title,
            composer: composer
        )

        // Time signature from first staffDef
        if let firstDef = staffDefs.first {
            score.timeSignature = TimeSignature(beats: firstDef.meterCount, noteValue: firstDef.meterUnit)
        }

        // Create parts from staff definitions
        if staffDefs.isEmpty {
            score.addPart(instrument: .acousticGuitar)
        } else {
            for def in staffDefs {
                var instrument = Instrument.acousticGuitar
                if !def.label.isEmpty { instrument.name = def.label }
                score.addPart(instrument: instrument)
            }
        }

        // Fill measures
        let measureCount = measures.count
        guard measureCount > 0 else {
            // Add 16 empty measures as fallback
            for _ in 0..<15 { score.appendMeasure() }
            return score
        }

        // Ensure enough measures
        while score.measureCount < measureCount {
            score.appendMeasure()
        }

        for (mIdx, meiMeasure) in measures.enumerated() {
            for staff in meiMeasure.staves {
                let partIdx = staff.n - 1
                guard partIdx >= 0, partIdx < score.parts.count else { continue }

                if let layer = staff.layers.first {
                    let events = layer.events.map { convertEvent($0) }
                    if mIdx < score.parts[partIdx].measureCount {
                        score.parts[partIdx].measures[mIdx].events = events
                    }
                }
            }
        }

        return score
    }

    private func convertEvent(_ event: MEIEvent) -> NoteEvent {
        switch event {
        case .note(let data):
            let pitch = convertPitch(data)
            let duration = convertDuration(dur: data.dur, dots: data.dots)
            var noteEvent = NoteEvent(type: .note, pitches: [pitch], duration: duration)
            if data.tie == "i" || data.tie == "m" { noteEvent.tiedToNext = true }
            if !data.artic.isEmpty { noteEvent.articulations = convertArticulations(data.artic) }
            return noteEvent
        case .rest(let data):
            let duration = convertDuration(dur: data.dur, dots: data.dots)
            return NoteEvent.rest(duration: duration)
        case .chord(let notes, let dur):
            let pitches = notes.map { convertPitch($0) }
            let dots = notes.first?.dots ?? 0
            let duration = convertDuration(dur: dur, dots: dots)
            return NoteEvent(type: .chord, pitches: pitches, duration: duration)
        }
    }

    private func convertPitch(_ data: MEINoteData) -> Pitch {
        let name: PitchName
        switch data.pname.lowercased() {
        case "c": name = .C
        case "d": name = .D
        case "e": name = .E
        case "f": name = .F
        case "g": name = .G
        case "a": name = .A
        case "b": name = .B
        default: name = .C
        }

        let accidental: Accidental
        switch data.accid {
        case "s": accidental = .sharp
        case "f": accidental = .flat
        case "n": accidental = .natural
        case "ss", "x": accidental = .doubleSharp
        case "ff": accidental = .doubleFlat
        default: accidental = .natural
        }

        return Pitch(name: name, octave: data.oct, accidental: accidental)
    }

    private func convertDuration(dur: String, dots: Int) -> Duration {
        let value: DurationValue
        switch dur {
        case "1", "breve": value = .whole
        case "2": value = .half
        case "4": value = .quarter
        case "8": value = .eighth
        case "16": value = .sixteenth
        case "32": value = .thirtySecond
        default: value = .quarter
        }
        return Duration(value: value, isDotted: dots >= 1, isDoubleDotted: dots >= 2)
    }

    private func convertArticulations(_ artic: String) -> [Articulation] {
        var result: [Articulation] = []
        for a in artic.split(separator: " ") {
            switch a {
            case "stacc": result.append(.staccato)
            case "acc": result.append(.accent)
            case "ten": result.append(.tenuto)
            case "marc": result.append(.marcato)
            case "leg": result.append(.legato)
            case "fermata": result.append(.fermata)
            default: break
            }
        }
        return result
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "staffDef":
            var def = MEIStaffDef()
            if let n = attributes["n"] { def.n = Int(n) ?? 1 }
            if let label = attributes["label"] { def.label = label }
            if let lines = attributes["lines"] { def.lines = Int(lines) ?? 5 }
            if let count = attributes["meter.count"] { def.meterCount = Int(count) ?? 4 }
            if let unit = attributes["meter.unit"] { def.meterUnit = Int(unit) ?? 4 }
            if let keySig = attributes["key.sig"] { def.keySig = keySig }
            currentStaffDef = def

        case "measure":
            var m = MEIMeasure()
            if let n = attributes["n"] { m.n = Int(n) ?? 0 }
            currentMeasure = m

        case "staff":
            var s = MEIStaff()
            if let n = attributes["n"] { s.n = Int(n) ?? 1 }
            currentStaff = s

        case "layer":
            var l = MEILayer()
            if let n = attributes["n"] { l.n = Int(n) ?? 1 }
            currentLayer = l

        case "note":
            var note = MEINoteData()
            if let pname = attributes["pname"] { note.pname = pname }
            if let oct = attributes["oct"] { note.oct = Int(oct) ?? 4 }
            if let dur = attributes["dur"] { note.dur = dur }
            if let accid = attributes["accid"] { note.accid = accid }
            if let dots = attributes["dots"] { note.dots = Int(dots) ?? 0 }
            if let tie = attributes["tie"] { note.tie = tie }
            if let artic = attributes["artic"] { note.artic = artic }
            if inChord {
                currentChordNotes.append(note)
            } else {
                currentNote = note
            }

        case "rest":
            var rest = MEIRestData()
            if let dur = attributes["dur"] { rest.dur = dur }
            if let dots = attributes["dots"] { rest.dots = Int(dots) ?? 0 }
            currentLayer?.events.append(.rest(rest))

        case "chord":
            inChord = true
            currentChordNotes = []

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "title":
            if elementStack.contains("titleStmt") && title.isEmpty {
                title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "persName":
            if elementStack.contains("titleStmt") && composer.isEmpty {
                composer = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "staffDef":
            if let def = currentStaffDef {
                staffDefs.append(def)
                currentStaffDef = nil
            }
        case "note":
            if !inChord, let note = currentNote {
                currentLayer?.events.append(.note(note))
                currentNote = nil
            }
        case "chord":
            if !currentChordNotes.isEmpty {
                let dur = currentChordNotes.first?.dur ?? "4"
                currentLayer?.events.append(.chord(currentChordNotes, dur: dur))
            }
            currentChordNotes = []
            inChord = false
        case "layer":
            if let layer = currentLayer {
                currentStaff?.layers.append(layer)
                currentLayer = nil
            }
        case "staff":
            if let staff = currentStaff {
                currentMeasure?.staves.append(staff)
                currentStaff = nil
            }
        case "measure":
            if let measure = currentMeasure {
                measures.append(measure)
                currentMeasure = nil
            }
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
    }
}
