import Foundation

// MARK: - ABC Notation Importer
// Supports ABC notation format (.abc)
// Reference: https://abcnotation.com/wiki/abc:standard:v2.1

class ABCNotationImporter {

    enum ABCError: Error, LocalizedError {
        case invalidFile
        case parseError(String)
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Невалидный ABC файл"
            case .parseError(let msg): return "Ошибка разбора ABC: \(msg)"
            case .emptyContent: return "Пустой ABC файл"
            }
        }
    }

    // MARK: - Public API

    static func importFile(at url: URL) throws -> Score {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try importString(content)
    }

    static func importString(_ abc: String) throws -> Score {
        let lines = abc.components(separatedBy: .newlines)
        guard !lines.isEmpty else { throw ABCError.emptyContent }

        var header = ABCHeader()
        var musicLines: [String] = []
        var inBody = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("%") { continue }

            if !inBody, let field = parseHeaderField(trimmed) {
                switch field.key {
                case "X": header.referenceNumber = Int(field.value) ?? 1
                case "T": header.title = field.value
                case "C": header.composer = field.value
                case "M": header.meter = field.value
                case "L": header.defaultLength = field.value
                case "Q": header.tempo = field.value
                case "K":
                    header.key = field.value
                    inBody = true // K: is always last header field
                default: break
                }
            } else {
                inBody = true
                musicLines.append(trimmed)
            }
        }

        let musicBody = musicLines.joined(separator: " ")
        return try buildScore(header: header, music: musicBody)
    }

    // MARK: - Header Parsing

    private struct ABCHeader {
        var referenceNumber: Int = 1
        var title: String = ""
        var composer: String = ""
        var meter: String = "4/4"
        var defaultLength: String = "1/8"
        var tempo: String = ""
        var key: String = "C"
    }

    private static func parseHeaderField(_ line: String) -> (key: String, value: String)? {
        guard line.count >= 2,
              line[line.index(line.startIndex, offsetBy: 1)] == ":" else { return nil }
        let key = String(line.prefix(1))
        let value = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    // MARK: - Music Parsing

    private static func buildScore(header: ABCHeader, music: String) throws -> Score {
        var score = Score(
            title: header.title.isEmpty ? "ABC Import" : header.title,
            composer: header.composer
        )

        // Parse key signature
        score.keySignature = parseKeySignature(header.key)

        // Parse time signature
        if let ts = parseTimeSignature(header.meter) {
            score.timeSignature = ts
        }

        // Parse tempo
        if let bpm = parseTempo(header.tempo) {
            score.tempo = TempoMarking(bpm: Double(bpm), name: tempoName(for: bpm))
        }

        // Default note length
        let defaultDuration = parseFraction(header.defaultLength) ?? (1, 8)

        // Add a single part (melody)
        score.addPart(instrument: .acousticGuitar)

        // Parse notes from music body
        var events: [NoteEvent] = []
        var i = music.startIndex

        while i < music.endIndex {
            let ch = music[i]

            // Bar line
            if ch == "|" {
                i = music.index(after: i)
                // Double bar, repeat, etc. — skip
                if i < music.endIndex && (music[i] == "|" || music[i] == ":" || music[i] == "]") {
                    i = music.index(after: i)
                }
                continue
            }

            // Rest
            if ch == "z" || ch == "x" {
                i = music.index(after: i)
                let (dur, newIdx) = parseDurationModifier(music, from: i, defaultFraction: defaultDuration)
                i = newIdx
                let event = NoteEvent.rest(duration: dur)
                events.append(event)
                continue
            }

            // Note: accidental + pitch + octave + duration
            if ch.isLetter && "ABCDEFGabcdefg".contains(ch) {
                let (event, newIdx) = try parseNote(music, from: i, defaultFraction: defaultDuration)
                i = newIdx
                events.append(event)
                continue
            }

            // Chord group [CEG]
            if ch == "[" {
                let (event, newIdx) = try parseChord(music, from: i, defaultFraction: defaultDuration)
                i = newIdx
                if let event = event {
                    events.append(event)
                }
                continue
            }

            // Decorations, slurs, ties — skip for basic import
            i = music.index(after: i)
        }

        // Distribute events into measures
        if !events.isEmpty, score.parts.count > 0 {
            let beatsPerMeasure = Double(score.timeSignature.beats)
            let beatValue = Double(score.timeSignature.beatValue)
            let measureCapacity = beatsPerMeasure / beatValue * 4.0 // in quarter note units

            var currentMeasureEvents: [NoteEvent] = []
            var currentBeats = 0.0
            var measureIndex = 0

            for event in events {
                let eventBeats = event.duration.beats
                currentMeasureEvents.append(event)
                currentBeats += eventBeats

                if currentBeats >= measureCapacity - 0.001 {
                    // Fill measure
                    if measureIndex < score.parts[0].measureCount {
                        score.parts[0].measures[measureIndex].events = currentMeasureEvents
                    } else {
                        score.appendMeasure()
                        score.parts[0].measures[measureIndex].events = currentMeasureEvents
                    }
                    measureIndex += 1
                    currentMeasureEvents = []
                    currentBeats = 0.0
                }
            }

            // Remaining events
            if !currentMeasureEvents.isEmpty {
                if measureIndex < score.parts[0].measureCount {
                    score.parts[0].measures[measureIndex].events = currentMeasureEvents
                } else {
                    score.appendMeasure()
                    score.parts[0].measures[measureIndex].events = currentMeasureEvents
                }
            }
        }

        return score
    }

    // MARK: - Note Parsing

    private static func parseNote(_ music: String, from startIdx: String.Index,
                                   defaultFraction: (Int, Int)) throws -> (NoteEvent, String.Index) {
        var i = startIdx

        // Accidental
        var accidental: Accidental? = nil
        if i < music.endIndex {
            if music[i] == "^" {
                accidental = .sharp
                i = music.index(after: i)
                if i < music.endIndex && music[i] == "^" {
                    accidental = .doubleSharp
                    i = music.index(after: i)
                }
            } else if music[i] == "_" {
                accidental = .flat
                i = music.index(after: i)
                if i < music.endIndex && music[i] == "_" {
                    accidental = .doubleFlat
                    i = music.index(after: i)
                }
            } else if music[i] == "=" {
                accidental = .natural
                i = music.index(after: i)
            }
        }

        guard i < music.endIndex else {
            throw ABCError.parseError("Unexpected end of note")
        }

        let ch = music[i]
        guard ch.isLetter else {
            throw ABCError.parseError("Expected note letter, got '\(ch)'")
        }

        // Uppercase = octave 4, lowercase = octave 5
        let isLower = ch.isLowercase
        let noteLetter = ch.uppercased()
        var octave = isLower ? 5 : 4
        i = music.index(after: i)

        // Octave modifiers: ' raises, , lowers
        while i < music.endIndex {
            if music[i] == "'" { octave += 1; i = music.index(after: i) }
            else if music[i] == "," { octave -= 1; i = music.index(after: i) }
            else { break }
        }

        // Duration modifier
        let (duration, newIdx) = parseDurationModifier(music, from: i, defaultFraction: defaultFraction)
        i = newIdx

        // Build pitch
        let pitchName = pitchNameFromLetter(noteLetter)
        let pitch = Pitch(name: pitchName, octave: octave, accidental: accidental ?? .natural)

        let event = NoteEvent(
            type: .note(pitch: pitch),
            duration: duration
        )

        return (event, i)
    }

    private static func parseChord(_ music: String, from startIdx: String.Index,
                                    defaultFraction: (Int, Int)) throws -> (NoteEvent?, String.Index) {
        var i = music.index(after: startIdx) // skip [
        var pitches: [Pitch] = []

        while i < music.endIndex && music[i] != "]" {
            let ch = music[i]
            if "ABCDEFGabcdefg".contains(ch) || ch == "^" || ch == "_" || ch == "=" {
                let (event, newIdx) = try parseNote(music, from: i, defaultFraction: defaultFraction)
                pitches.append(contentsOf: event.pitches)
                i = newIdx
            } else {
                i = music.index(after: i)
            }
        }

        if i < music.endIndex { i = music.index(after: i) } // skip ]

        // Duration for the whole chord
        let (duration, newIdx) = parseDurationModifier(music, from: i, defaultFraction: defaultFraction)

        guard !pitches.isEmpty else { return (nil, newIdx) }

        let event: NoteEvent
        if pitches.count > 1 {
            event = NoteEvent(type: .chord(pitches: pitches), duration: duration)
        } else {
            event = NoteEvent(type: .note(pitch: pitches[0]), duration: duration)
        }

        return (event, newIdx)
    }

    // MARK: - Duration Parsing

    private static func parseDurationModifier(_ music: String, from startIdx: String.Index,
                                               defaultFraction: (Int, Int)) -> (Duration, String.Index) {
        var i = startIdx
        var numerator = defaultFraction.0
        var denominator = defaultFraction.1

        // Multiplier number (e.g., "2" doubles default length)
        if i < music.endIndex && music[i].isNumber {
            var numStr = ""
            while i < music.endIndex && music[i].isNumber {
                numStr.append(music[i])
                i = music.index(after: i)
            }
            if let n = Int(numStr) { numerator = defaultFraction.0 * n }
        }

        // Slash halves (e.g., "/" halves, "/2" same, "///" = /8)
        if i < music.endIndex && music[i] == "/" {
            i = music.index(after: i)
            if i < music.endIndex && music[i].isNumber {
                var denStr = ""
                while i < music.endIndex && music[i].isNumber {
                    denStr.append(music[i])
                    i = music.index(after: i)
                }
                if let d = Int(denStr) { denominator = defaultFraction.1 * d }
            } else {
                denominator = defaultFraction.1 * 2
                // Additional slashes
                while i < music.endIndex && music[i] == "/" {
                    denominator *= 2
                    i = music.index(after: i)
                }
            }
        }

        let duration = fractionToDuration(numerator: numerator, denominator: denominator)
        return (duration, i)
    }

    private static func fractionToDuration(numerator: Int, denominator: Int) -> Duration {
        // Convert fraction to closest DurationValue
        let ratio = Double(numerator) / Double(denominator)
        let value: DurationValue
        let isDotted: Bool

        // Map to standard durations (in whole notes)
        if ratio >= 0.75 {       // dotted half or whole
            if ratio >= 1.0 { value = .whole; isDotted = false }
            else { value = .half; isDotted = true }
        } else if ratio >= 0.375 {
            if ratio >= 0.5 { value = .half; isDotted = false }
            else { value = .quarter; isDotted = true }
        } else if ratio >= 0.1875 {
            if ratio >= 0.25 { value = .quarter; isDotted = false }
            else { value = .eighth; isDotted = true }
        } else if ratio >= 0.09375 {
            if ratio >= 0.125 { value = .eighth; isDotted = false }
            else { value = .sixteenth; isDotted = true }
        } else if ratio >= 0.046875 {
            if ratio >= 0.0625 { value = .sixteenth; isDotted = false }
            else { value = .thirtySecond; isDotted = true }
        } else {
            value = .thirtySecond; isDotted = false
        }

        return Duration(value: value, dotted: isDotted)
    }

    // MARK: - Helpers

    private static func pitchNameFromLetter(_ letter: String) -> PitchName {
        switch letter {
        case "C": return .C
        case "D": return .D
        case "E": return .E
        case "F": return .F
        case "G": return .G
        case "A": return .A
        case "B": return .B
        default: return .C
        }
    }

    private static func parseKeySignature(_ key: String) -> KeySignature {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        let isMinor = trimmed.hasSuffix("m") && trimmed.count > 1
        let mode: KeySignatureType = isMinor ? .minor : .major
        let root = isMinor ? String(trimmed.dropLast()) : trimmed

        let fifths: Int
        switch root {
        case "C": fifths = isMinor ? -3 : 0
        case "G": fifths = isMinor ? -6 : 1
        case "D": fifths = isMinor ? -1 : 2
        case "A": fifths = isMinor ? -4 : 3
        case "E": fifths = isMinor ? 4 : 4
        case "B": fifths = isMinor ? -2 : 5
        case "F#": fifths = isMinor ? 3 : 6
        case "F": fifths = isMinor ? -4 : -1
        case "Bb": fifths = isMinor ? -5 : -2
        case "Eb": fifths = isMinor ? -6 : -3
        case "Ab": fifths = isMinor ? -7 : -4
        case "Db": fifths = isMinor ? -4 : -5
        case "Gb": fifths = isMinor ? -3 : -6
        case "C#": fifths = isMinor ? 4 : 7
        case "G#": fifths = isMinor ? 5 : 8
        case "D#": fifths = isMinor ? 6 : 9
        default: fifths = 0
        }
        return KeySignature(fifths: fifths, mode: mode)
    }

    private static func parseTimeSignature(_ meter: String) -> TimeSignature? {
        if meter == "C" { return .fourFour }
        if meter == "C|" { return TimeSignature(beats: 2, beatValue: 2) }
        let parts = meter.split(separator: "/")
        guard parts.count == 2,
              let beats = Int(parts[0]),
              let beatValue = Int(parts[1]) else { return nil }
        return TimeSignature(beats: beats, beatValue: beatValue)
    }

    private static func parseTempo(_ tempo: String) -> Int? {
        // Format: "1/4=120" or just "120"
        if let bpm = Int(tempo) { return bpm }
        if let eqIdx = tempo.lastIndex(of: "=") {
            let bpmStr = tempo[tempo.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
            return Int(bpmStr)
        }
        return nil
    }

    private static func parseFraction(_ str: String) -> (Int, Int)? {
        let parts = str.split(separator: "/")
        guard parts.count == 2,
              let num = Int(parts[0]),
              let den = Int(parts[1]) else { return nil }
        return (num, den)
    }

    private static func tempoName(for bpm: Int) -> String {
        switch bpm {
        case 0..<40: return "Grave"
        case 40..<55: return "Largo"
        case 55..<65: return "Adagio"
        case 65..<73: return "Adagietto"
        case 73..<86: return "Andante"
        case 86..<98: return "Andantino"
        case 98..<109: return "Moderato"
        case 109..<120: return "Allegretto"
        case 120..<156: return "Allegro"
        case 156..<176: return "Vivace"
        case 176..<200: return "Presto"
        default: return "Prestissimo"
        }
    }
}
