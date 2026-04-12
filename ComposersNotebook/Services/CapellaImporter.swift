import Foundation

// MARK: - Capella Importer
// Supports .capx format (Capella XML — ZIP archive containing score.xml)
// Reference: capella-software.com

class CapellaImporter {

    enum CapellaError: Error, LocalizedError {
        case invalidFile
        case parseError(String)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Невалидный Capella файл"
            case .parseError(let msg): return "Ошибка разбора Capella: \(msg)"
            case .unsupportedFormat: return "Неподдерживаемый формат Capella"
            }
        }
    }

    // MARK: - Public API

    static func importFile(at url: URL) throws -> Score {
        let ext = url.pathExtension.lowercased()
        guard ext == "capx" else {
            throw CapellaError.unsupportedFormat
        }

        let data = try Data(contentsOf: url)
        return try importCAPX(data: data, filename: url.deletingPathExtension().lastPathComponent)
    }

    // MARK: - CAPX Format (ZIP + XML)

    private static func importCAPX(data: Data, filename: String) throws -> Score {
        // CAPX is a ZIP archive containing score.xml
        guard let xmlData = extractScoreXML(from: data) else {
            // Try plain XML fallback
            if let xmlStr = String(data: data, encoding: .utf8),
               xmlStr.contains("<score") || xmlStr.contains("<capella") {
                return try parseCapellaXML(data: data, filename: filename)
            }
            throw CapellaError.parseError("Cannot extract score.xml from CAPX archive")
        }
        return try parseCapellaXML(data: xmlData, filename: filename)
    }

    private static func extractScoreXML(from zipData: Data) -> Data? {
        // Simple ZIP parsing — find local file header for score.xml
        var offset = 0
        while offset + 30 < zipData.count {
            guard zipData[offset] == 0x50, zipData[offset+1] == 0x4B,
                  zipData[offset+2] == 0x03, zipData[offset+3] == 0x04 else {
                offset += 1
                continue
            }

            let compMethod = UInt16(zipData[offset+8]) | (UInt16(zipData[offset+9]) << 8)
            let compSize = Int(UInt32(zipData[offset+18]) | (UInt32(zipData[offset+19]) << 8) |
                              (UInt32(zipData[offset+20]) << 16) | (UInt32(zipData[offset+21]) << 24))
            let nameLen = Int(UInt16(zipData[offset+26]) | (UInt16(zipData[offset+27]) << 8))
            let extraLen = Int(UInt16(zipData[offset+28]) | (UInt16(zipData[offset+29]) << 8))

            let nameStart = offset + 30
            guard nameStart + nameLen <= zipData.count else { break }
            let fileName = String(data: zipData[nameStart..<nameStart+nameLen], encoding: .utf8) ?? ""

            let dataStart = nameStart + nameLen + extraLen
            guard dataStart + compSize <= zipData.count else { break }

            if fileName.lowercased().contains("score.xml") || fileName.lowercased().hasSuffix(".xml") {
                let fileData = zipData[dataStart..<dataStart+compSize]
                if compMethod == 0 {
                    return Data(fileData) // stored (no compression)
                }
                // Deflate — would need zlib, return nil for fallback
                return nil
            }

            offset = dataStart + compSize
        }
        return nil
    }

    // MARK: - Capella XML Parser

    private static func parseCapellaXML(data: Data, filename: String) throws -> Score {
        let parser = CapellaXMLParser(filename: filename)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldResolveExternalEntities = false
        guard xmlParser.parse() else {
            throw CapellaError.parseError("XML parsing failed")
        }
        return parser.buildScore()
    }
}

// MARK: - Capella XML Parser Delegate

private class CapellaXMLParser: NSObject, XMLParserDelegate {
    private let filename: String
    private var title = ""
    private var composer = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Musical content
    private var voices: [CapVoice] = []
    private var currentVoice: CapVoice?
    private var currentNoteObj: CapNoteObj?
    private var currentChordNotes: [CapNote] = []

    // Time & key
    private var timeBeats = 4
    private var timeUnit = 4
    private var keySig = 0 // fifths

    private struct CapVoice {
        var name: String = ""
        var noteObjects: [CapNoteObj] = []
    }

    private struct CapNoteObj {
        var durValue: Int = 4      // 1=whole, 2=half, 4=quarter, etc.
        var dots: Int = 0
        var isRest: Bool = false
        var notes: [CapNote] = []
        var tie: Bool = false
    }

    private struct CapNote {
        var step: Int = 0          // 0=C, 1=D, 2=E, 3=F, 4=G, 5=A, 6=B
        var octave: Int = 4
        var alter: Int = 0         // -2..+2 semitones
    }

    init(filename: String) {
        self.filename = filename
        super.init()
    }

    func buildScore() -> Score {
        var score = Score(
            title: title.isEmpty ? filename : title,
            composer: composer,
            tempo: TempoMarking(bpm: 120, name: "Allegro"),
            timeSignature: TimeSignature(beats: timeBeats, noteValue: timeUnit),
            keySignature: keyFromFifths(keySig)
        )

        if voices.isEmpty {
            score.addPart(instrument: .acousticGuitar)
            for _ in 0..<15 { score.appendMeasure() }
            return score
        }

        // Create parts
        for voice in voices {
            var instrument = Instrument.acousticGuitar
            if !voice.name.isEmpty { instrument.name = voice.name }
            score.addPart(instrument: instrument)
        }

        // Distribute note objects into measures
        let beatsPerMeasure = Double(timeBeats)
        let beatUnit = Double(timeUnit)
        let measureCapacity = beatsPerMeasure * (4.0 / beatUnit) // in quarter-note units

        for (partIdx, voice) in voices.enumerated() {
            var measureIdx = 0
            var currentBeat = 0.0
            var measureEvents: [NoteEvent] = []

            for noteObj in voice.noteObjects {
                let event = convertNoteObj(noteObj)
                let eventBeats = event.duration.totalBeats
                measureEvents.append(event)
                currentBeat += eventBeats

                if currentBeat >= measureCapacity - 0.001 {
                    while score.measureCount <= measureIdx { score.appendMeasure() }
                    if measureIdx < score.parts[partIdx].measureCount {
                        score.parts[partIdx].measures[measureIdx].events = measureEvents
                    }
                    measureIdx += 1
                    measureEvents = []
                    currentBeat = 0.0
                }
            }

            // Remaining events
            if !measureEvents.isEmpty {
                while score.measureCount <= measureIdx { score.appendMeasure() }
                if measureIdx < score.parts[partIdx].measureCount {
                    score.parts[partIdx].measures[measureIdx].events = measureEvents
                }
            }
        }

        return score
    }

    private func convertNoteObj(_ obj: CapNoteObj) -> NoteEvent {
        let duration = durationFromValue(obj.durValue, dots: obj.dots)

        if obj.isRest {
            return NoteEvent.rest(duration: duration)
        }

        let pitches = obj.notes.map { note -> Pitch in
            let pitchName = stepToPitchName(note.step)
            let accidental = alterToAccidental(note.alter)
            return Pitch(name: pitchName, octave: note.octave, accidental: accidental)
        }

        guard !pitches.isEmpty else {
            return NoteEvent.rest(duration: duration)
        }

        var event = NoteEvent(
            type: pitches.count > 1 ? .chord : .note,
            pitches: pitches,
            duration: duration
        )
        event.tiedToNext = obj.tie
        return event
    }

    private func durationFromValue(_ value: Int, dots: Int) -> Duration {
        let durValue: DurationValue
        switch value {
        case 1: durValue = .whole
        case 2: durValue = .half
        case 4: durValue = .quarter
        case 8: durValue = .eighth
        case 16: durValue = .sixteenth
        case 32: durValue = .thirtySecond
        default: durValue = .quarter
        }
        return Duration(value: durValue, isDotted: dots >= 1, isDoubleDotted: dots >= 2)
    }

    private func stepToPitchName(_ step: Int) -> PitchName {
        switch step {
        case 0: return .C
        case 1: return .D
        case 2: return .E
        case 3: return .F
        case 4: return .G
        case 5: return .A
        case 6: return .B
        default: return .C
        }
    }

    private func alterToAccidental(_ alter: Int) -> Accidental {
        switch alter {
        case -2: return .doubleFlat
        case -1: return .flat
        case 0: return .natural
        case 1: return .sharp
        case 2: return .doubleSharp
        default: return .natural
        }
    }

    private func keyFromFifths(_ fifths: Int) -> KeySignature {
        switch fifths {
        case -7: return .gFlatMajor
        case -6: return .dFlatMajor
        case -5: return .aFlatMajor
        case -4: return .eFlatMajor
        case -3: return .bFlatMajor
        case -2: return .bFlatMajor
        case -1: return .fMajor
        case 0: return .cMajor
        case 1: return .gMajor
        case 2: return .dMajor
        case 3: return .aMajor
        case 4: return .eMajor
        case 5: return .bMajor
        case 6: return .fSharpMajor
        default: return .cMajor
        }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "voice":
            var v = CapVoice()
            if let name = attributes["name"] { v.name = name }
            currentVoice = v

        case "timeSign":
            if let beats = attributes["beats"] { timeBeats = Int(beats) ?? 4 }
            if let unit = attributes["beatUnit"] { timeUnit = Int(unit) ?? 4 }

        case "keySign":
            if let fifths = attributes["fifths"] { keySig = Int(fifths) ?? 0 }

        case "rest":
            var obj = CapNoteObj()
            obj.isRest = true
            if let dur = attributes["dur"] { obj.durValue = Int(dur) ?? 4 }
            if let dots = attributes["dots"] { obj.dots = Int(dots) ?? 0 }
            currentVoice?.noteObjects.append(obj)

        case "chord":
            var obj = CapNoteObj()
            if let dur = attributes["dur"] { obj.durValue = Int(dur) ?? 4 }
            if let dots = attributes["dots"] { obj.dots = Int(dots) ?? 0 }
            if let tie = attributes["tie"] { obj.tie = (tie == "true" || tie == "1") }
            currentNoteObj = obj
            currentChordNotes = []

        case "head":
            var note = CapNote()
            if let step = attributes["step"] { note.step = Int(step) ?? 0 }
            if let octave = attributes["octave"] { note.octave = Int(octave) ?? 4 }
            if let alter = attributes["alter"] { note.alter = Int(alter) ?? 0 }
            currentChordNotes.append(note)

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
            if title.isEmpty { title = currentText.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "creator":
            if composer.isEmpty { composer = currentText.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "chord":
            if var obj = currentNoteObj {
                obj.notes = currentChordNotes
                currentVoice?.noteObjects.append(obj)
                currentNoteObj = nil
            }
        case "voice":
            if let voice = currentVoice {
                voices.append(voice)
                currentVoice = nil
            }
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
    }
}
