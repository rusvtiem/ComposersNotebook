import Foundation

// MARK: - MIDI File Constants

private let midiHeaderChunk: [UInt8] = [0x4D, 0x54, 0x68, 0x64] // "MThd"
private let midiTrackChunk: [UInt8] = [0x4D, 0x54, 0x72, 0x6B] // "MTrk"

// MARK: - MIDI Exporter

class MIDIExporter {

    /// Export Score to Standard MIDI File (Format 1)
    static func export(score: Score) -> Data {
        let ticksPerQuarter: UInt16 = 480
        var tracks: [Data] = []

        // Track 0: tempo map + time signatures
        tracks.append(buildTempoTrack(score: score, tpq: ticksPerQuarter))

        // Track 1+: one per part
        for part in score.parts {
            tracks.append(buildPartTrack(
                part: part,
                score: score,
                tpq: ticksPerQuarter
            ))
        }

        // Assemble SMF
        var data = Data()

        // Header: MThd, length=6, format=1, ntrks, tpq
        data.append(contentsOf: midiHeaderChunk)
        data.append(uint32: 6)
        data.append(uint16: 1) // format 1
        data.append(uint16: UInt16(tracks.count))
        data.append(uint16: ticksPerQuarter)

        // Tracks
        for track in tracks {
            data.append(contentsOf: midiTrackChunk)
            data.append(uint32: UInt32(track.count))
            data.append(track)
        }

        return data
    }

    /// Export Score to .mid file
    static func exportToFile(score: Score, url: URL) throws {
        let data = export(score: score)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Build Tracks

    private static func buildTempoTrack(score: Score, tpq: UInt16) -> Data {
        var events: [(delta: Int, bytes: [UInt8])] = []
        var currentTick = 0

        // Initial tempo
        let initialBPM = score.tempo.bpm
        events.append((delta: 0, bytes: tempoEvent(bpm: initialBPM)))

        // Initial time signature
        events.append((delta: 0, bytes: timeSignatureEvent(score.timeSignature)))

        // Initial key signature
        events.append((delta: 0, bytes: keySignatureEvent(score.keySignature)))

        // Walk measures for tempo/TS changes
        if let firstPart = score.parts.first {
            let ts = score.timeSignature
            let ticksPerMeasure = Int(ts.totalBeats * Double(tpq))

            for (i, measure) in firstPart.measures.enumerated() {
                if i == 0 { continue } // already set initial

                let measureStart = i * ticksPerMeasure
                let delta = measureStart - currentTick

                if let tempo = measure.tempoMarking {
                    events.append((delta: delta, bytes: tempoEvent(bpm: tempo.bpm)))
                    currentTick = measureStart
                }

                if let newTS = measure.timeSignature {
                    let d = measureStart - currentTick
                    events.append((delta: d, bytes: timeSignatureEvent(newTS)))
                    currentTick = measureStart
                }
            }
        }

        // End of track
        events.append((delta: 0, bytes: [0xFF, 0x2F, 0x00]))

        return encodeTrackEvents(events)
    }

    private static func buildPartTrack(part: Part, score: Score, tpq: UInt16) -> Data {
        var events: [(delta: Int, bytes: [UInt8])] = []
        let channel: UInt8 = 0

        // Track name
        let name = part.instrument.name
        let nameBytes = Array(name.utf8)
        events.append((delta: 0, bytes: [0xFF, 0x03] + variableLength(nameBytes.count) + nameBytes))

        // Program change
        events.append((delta: 0, bytes: [0xC0 | channel, UInt8(part.instrument.midiProgram)]))

        var currentTick = 0
        var pendingNoteOffs: [(tick: Int, note: UInt8)] = []

        for (mIdx, measure) in part.measures.enumerated() {
            let ts = measure.timeSignature ?? score.timeSignature
            var beatPosition: Double = 0

            for event in measure.events {
                let eventTick = currentTick + Int(beatPosition * Double(tpq))

                // Flush note-offs that should happen before this event
                pendingNoteOffs.sort { $0.tick < $1.tick }
                var lastTick = events.isEmpty ? 0 : sumDeltas(events)

                for noteOff in pendingNoteOffs.filter({ $0.tick <= eventTick }) {
                    let delta = noteOff.tick - lastTick
                    events.append((delta: max(0, delta), bytes: [0x80 | channel, noteOff.note, 0x40]))
                    lastTick = noteOff.tick
                }
                pendingNoteOffs.removeAll { $0.tick <= eventTick }

                // Add note-on events
                if !event.isRest {
                    let velocity = UInt8(event.velocity)
                    let durationTicks = Int(event.duration.beats * Double(tpq))
                    let delta = eventTick - lastTick

                    for (pIdx, pitch) in event.pitches.enumerated() {
                        let midiNote = UInt8(clamping: pitch.midiNote)
                        let d = pIdx == 0 ? max(0, delta) : 0
                        events.append((delta: d, bytes: [0x90 | channel, midiNote, velocity]))

                        if !event.tiedToNext {
                            pendingNoteOffs.append((tick: eventTick + durationTicks, note: midiNote))
                        }
                    }
                }

                beatPosition += event.duration.beats
            }

            // Advance to next measure
            currentTick += Int(ts.totalBeats * Double(tpq))
        }

        // Flush remaining note-offs
        pendingNoteOffs.sort { $0.tick < $1.tick }
        var lastTick = sumDeltas(events)
        for noteOff in pendingNoteOffs {
            let delta = noteOff.tick - lastTick
            events.append((delta: max(0, delta), bytes: [0x80 | channel, noteOff.note, 0x40]))
            lastTick = noteOff.tick
        }

        // End of track
        events.append((delta: 0, bytes: [0xFF, 0x2F, 0x00]))

        return encodeTrackEvents(events)
    }

    // MARK: - MIDI Meta Events

    private static func tempoEvent(bpm: Double) -> [UInt8] {
        let microsecondsPerBeat = UInt32(60_000_000.0 / bpm)
        return [
            0xFF, 0x51, 0x03,
            UInt8((microsecondsPerBeat >> 16) & 0xFF),
            UInt8((microsecondsPerBeat >> 8) & 0xFF),
            UInt8(microsecondsPerBeat & 0xFF)
        ]
    }

    private static func timeSignatureEvent(_ ts: TimeSignature) -> [UInt8] {
        let denomPower: UInt8 = {
            switch ts.beatValue {
            case 1: return 0
            case 2: return 1
            case 4: return 2
            case 8: return 3
            case 16: return 4
            case 32: return 5
            default: return 2
            }
        }()
        return [0xFF, 0x58, 0x04, UInt8(ts.beats), denomPower, 24, 8]
    }

    private static func keySignatureEvent(_ ks: KeySignature) -> [UInt8] {
        let sf = Int8(clamping: ks.fifths)
        let mi: UInt8 = ks.mode == .minor ? 1 : 0
        return [0xFF, 0x59, 0x02, UInt8(bitPattern: sf), mi]
    }

    // MARK: - Encoding Helpers

    private static func encodeTrackEvents(_ events: [(delta: Int, bytes: [UInt8])]) -> Data {
        var data = Data()
        for event in events {
            data.append(contentsOf: variableLength(event.delta))
            data.append(contentsOf: event.bytes)
        }
        return data
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        var v = value
        var result: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            result.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return result
    }

    private static func sumDeltas(_ events: [(delta: Int, bytes: [UInt8])]) -> Int {
        events.reduce(0) { $0 + $1.delta }
    }
}

// MARK: - MIDI Importer

class MIDIImporter {

    /// Import Standard MIDI File into Score
    static func importFile(at url: URL) throws -> Score {
        let data = try Data(contentsOf: url)
        return try importData(data)
    }

    static func importData(_ data: Data) throws -> Score {
        var offset = 0

        // Parse header
        guard data.count > 14 else { throw MIDIImportError.invalidFile }
        guard Array(data[0..<4]) == midiHeaderChunk else { throw MIDIImportError.invalidFile }

        let headerLength = data.uint32(at: 4)
        let format = data.uint16(at: 8)
        let numTracks = Int(data.uint16(at: 10))
        let division = data.uint16(at: 12)

        guard format <= 1 else { throw MIDIImportError.unsupportedFormat(Int(format)) }
        guard division & 0x8000 == 0 else { throw MIDIImportError.smpteNotSupported }

        let ticksPerQuarter = Int(division)
        offset = 8 + Int(headerLength)

        // Parse tracks
        var tempoMap: [(tick: Int, bpm: Double)] = [(0, 120)]
        var timeSignatures: [(tick: Int, ts: TimeSignature)] = [(0, .fourFour)]
        var keySignatures: [(tick: Int, ks: KeySignature)] = []
        var trackNotes: [[(tick: Int, note: Int, velocity: Int, duration: Int, channel: Int)]] = []
        var trackNames: [String] = []
        var trackPrograms: [Int] = []

        for _ in 0..<numTracks {
            guard offset + 8 <= data.count else { break }
            guard Array(data[offset..<offset+4]) == midiTrackChunk else {
                throw MIDIImportError.invalidTrackHeader
            }

            let trackLength = Int(data.uint32(at: offset + 4))
            offset += 8
            let trackEnd = offset + trackLength
            guard trackEnd <= data.count else { throw MIDIImportError.invalidFile }

            var tick = 0
            var runningStatus: UInt8 = 0
            var noteOns: [Int: (tick: Int, velocity: Int)] = [:] // note -> (startTick, vel)
            var notes: [(tick: Int, note: Int, velocity: Int, duration: Int, channel: Int)] = []
            var trackName = ""
            var program = 0

            while offset < trackEnd {
                // Read delta time
                let (delta, deltaBytes) = readVariableLength(data: data, offset: offset)
                offset += deltaBytes
                tick += delta

                guard offset < trackEnd else { break }
                var status = data[offset]

                // Running status
                if status < 0x80 {
                    status = runningStatus
                } else {
                    offset += 1
                }

                let channel = Int(status & 0x0F)
                let messageType = status & 0xF0

                switch messageType {
                case 0x90: // Note On
                    guard offset + 1 < trackEnd else { break }
                    let note = Int(data[offset])
                    let vel = Int(data[offset + 1])
                    offset += 2
                    runningStatus = status

                    if vel > 0 {
                        noteOns[note] = (tick, vel)
                    } else {
                        // Note On with vel=0 = Note Off
                        if let start = noteOns[note] {
                            notes.append((start.tick, note, start.velocity, tick - start.tick, channel))
                            noteOns.removeValue(forKey: note)
                        }
                    }

                case 0x80: // Note Off
                    guard offset + 1 < trackEnd else { break }
                    let note = Int(data[offset])
                    offset += 2
                    runningStatus = status

                    if let start = noteOns[note] {
                        notes.append((start.tick, note, start.velocity, tick - start.tick, channel))
                        noteOns.removeValue(forKey: note)
                    }

                case 0xA0: // Aftertouch
                    offset += 2; runningStatus = status
                case 0xB0: // Control Change
                    offset += 2; runningStatus = status
                case 0xC0: // Program Change
                    guard offset < trackEnd else { break }
                    program = Int(data[offset])
                    offset += 1; runningStatus = status
                case 0xD0: // Channel Pressure
                    offset += 1; runningStatus = status
                case 0xE0: // Pitch Bend
                    offset += 2; runningStatus = status

                case 0xF0:
                    if status == 0xFF { // Meta event
                        guard offset + 1 < trackEnd else { break }
                        let metaType = data[offset]
                        offset += 1
                        let (metaLen, lenBytes) = readVariableLength(data: data, offset: offset)
                        offset += lenBytes

                        guard offset + metaLen <= trackEnd else { break }
                        let metaData = Array(data[offset..<offset+metaLen])
                        offset += metaLen

                        switch metaType {
                        case 0x03: // Track name
                            trackName = String(bytes: metaData, encoding: .utf8) ?? ""
                        case 0x51: // Tempo
                            if metaData.count >= 3 {
                                let microsPerBeat = (Int(metaData[0]) << 16) | (Int(metaData[1]) << 8) | Int(metaData[2])
                                let bpm = 60_000_000.0 / Double(microsPerBeat)
                                tempoMap.append((tick, bpm))
                            }
                        case 0x58: // Time Signature
                            if metaData.count >= 2 {
                                let beats = Int(metaData[0])
                                let beatValue = Int(pow(2.0, Double(metaData[1])))
                                timeSignatures.append((tick, TimeSignature(beats: beats, beatValue: beatValue)))
                            }
                        case 0x59: // Key Signature
                            if metaData.count >= 2 {
                                let sf = Int(Int8(bitPattern: metaData[0]))
                                let mode: KeySignatureType = metaData[1] == 1 ? .minor : .major
                                keySignatures.append((tick, KeySignature(fifths: sf, mode: mode)))
                            }
                        case 0x2F: // End of Track
                            break
                        default:
                            break
                        }
                    } else if status == 0xF0 || status == 0xF7 { // SysEx
                        let (sysLen, lenBytes) = readVariableLength(data: data, offset: offset)
                        offset += lenBytes + sysLen
                    }

                default:
                    break
                }
            }

            offset = trackEnd

            if !notes.isEmpty {
                trackNotes.append(notes)
                trackNames.append(trackName)
                trackPrograms.append(program)
            }
        }

        // Build Score
        return buildScore(
            trackNotes: trackNotes,
            trackNames: trackNames,
            trackPrograms: trackPrograms,
            tempoMap: tempoMap,
            timeSignatures: timeSignatures,
            keySignatures: keySignatures,
            ticksPerQuarter: ticksPerQuarter
        )
    }

    // MARK: - Build Score from MIDI data

    private static func buildScore(
        trackNotes: [[(tick: Int, note: Int, velocity: Int, duration: Int, channel: Int)]],
        trackNames: [String],
        trackPrograms: [Int],
        tempoMap: [(tick: Int, bpm: Double)],
        timeSignatures: [(tick: Int, ts: TimeSignature)],
        keySignatures: [(tick: Int, ks: KeySignature)],
        ticksPerQuarter: Int
    ) -> Score {
        let initialTempo = tempoMap.first?.bpm ?? 120
        let initialTS = timeSignatures.first?.ts ?? .fourFour
        let initialKS = keySignatures.first?.ks ?? .cMajor

        var score = Score(
            title: "Imported MIDI",
            composer: "",
            parts: [],
            tempo: TempoMarking(bpm: initialTempo),
            timeSignature: initialTS,
            keySignature: initialKS
        )

        let ticksPerMeasure = Int(initialTS.totalBeats) * ticksPerQuarter

        for (tIdx, notes) in trackNotes.enumerated() {
            let name = tIdx < trackNames.count ? trackNames[tIdx] : ""
            let program = tIdx < trackPrograms.count ? trackPrograms[tIdx] : 0
            let instrument = instrumentFromProgram(program, name: name)

            // Determine number of measures needed
            let maxTick = notes.map { $0.tick + $0.duration }.max() ?? ticksPerMeasure
            let numMeasures = max(1, (maxTick + ticksPerMeasure - 1) / ticksPerMeasure)

            var part = Part(instrument: instrument, measures: [])

            for mIdx in 0..<numMeasures {
                let measureStart = mIdx * ticksPerMeasure
                let measureEnd = measureStart + ticksPerMeasure

                // Get notes in this measure
                let measureNotes = notes.filter { $0.tick >= measureStart && $0.tick < measureEnd }

                var measure = Measure.empty()
                measure.events = []

                if measureNotes.isEmpty {
                    measure.events = [NoteEvent.rest(duration: .wholeNote)]
                } else {
                    // Quantize notes into events
                    var currentBeat: Double = 0
                    let sortedNotes = measureNotes.sorted { $0.tick < $1.tick }

                    // Group simultaneous notes into chords
                    var groups: [[(tick: Int, note: Int, velocity: Int, duration: Int, channel: Int)]] = []
                    for note in sortedNotes {
                        if let last = groups.last, let lastNote = last.first,
                           abs(note.tick - lastNote.tick) < ticksPerQuarter / 8 {
                            groups[groups.count - 1].append(note)
                        } else {
                            groups.append([note])
                        }
                    }

                    for group in groups {
                        guard let first = group.first else { continue }

                        // Calculate beat position and fill rests
                        let noteBeat = Double(first.tick - measureStart) / Double(ticksPerQuarter)
                        if noteBeat > currentBeat + 0.1 {
                            let restBeats = noteBeat - currentBeat
                            if let restDuration = bestDuration(for: restBeats) {
                                measure.events.append(NoteEvent.rest(duration: restDuration))
                            }
                        }

                        // Determine note duration
                        let durationBeats = Double(first.duration) / Double(ticksPerQuarter)
                        let duration = bestDuration(for: durationBeats) ?? .quarterNote

                        if group.count == 1 {
                            let pitch = Pitch.fromMIDI(first.note)
                            var event = NoteEvent.note(pitch, duration: duration)
                            event.dynamic = dynamicFromVelocity(first.velocity)
                            measure.events.append(event)
                        } else {
                            let pitches = group.map { Pitch.fromMIDI($0.note) }
                            var event = NoteEvent.chord(pitches, duration: duration)
                            event.dynamic = dynamicFromVelocity(first.velocity)
                            measure.events.append(event)
                        }

                        currentBeat = noteBeat + durationBeats
                    }
                }

                part.measures.append(measure)
            }

            score.parts.append(part)
        }

        if score.parts.isEmpty {
            score.parts.append(Part(instrument: .piano, measures: [Measure.empty()]))
        }

        return score
    }

    // MARK: - Helpers

    private static func readVariableLength(data: Data, offset: Int) -> (value: Int, bytesRead: Int) {
        var value = 0
        var bytesRead = 0
        var byte: UInt8

        repeat {
            guard offset + bytesRead < data.count else { return (value, bytesRead) }
            byte = data[offset + bytesRead]
            value = (value << 7) | Int(byte & 0x7F)
            bytesRead += 1
        } while byte & 0x80 != 0

        return (value, bytesRead)
    }

    private static func bestDuration(for beats: Double) -> Duration? {
        let candidates: [(Duration, Double)] = [
            (.init(value: .whole, dotted: true), 6.0),
            (.init(value: .whole), 4.0),
            (.init(value: .half, dotted: true), 3.0),
            (.init(value: .half), 2.0),
            (.init(value: .quarter, dotted: true), 1.5),
            (.init(value: .quarter), 1.0),
            (.init(value: .eighth, dotted: true), 0.75),
            (.init(value: .eighth), 0.5),
            (.init(value: .sixteenth), 0.25),
            (.init(value: .thirtySecond), 0.125),
        ]

        var best: Duration?
        var bestDiff = Double.infinity
        for (dur, durBeats) in candidates {
            let diff = abs(durBeats - beats)
            if diff < bestDiff {
                bestDiff = diff
                best = dur
            }
        }
        return best
    }

    private static func dynamicFromVelocity(_ velocity: Int) -> DynamicMarking? {
        switch velocity {
        case 0..<24: return .ppp
        case 24..<40: return .pp
        case 40..<56: return .p
        case 56..<72: return .mp
        case 72..<88: return .mf
        case 88..<104: return .f
        case 104..<120: return .ff
        default: return .fff
        }
    }

    private static func instrumentFromProgram(_ program: Int, name: String) -> Instrument {
        let presets: [Instrument] = [
            .piano, .violin, .viola, .cello, .doubleBass,
            .flute, .oboe, .clarinetBb, .bassoon,
            .hornF, .trumpet, .trombone, .tuba,
            .timpani, .piccolo
        ]

        if let match = presets.first(where: { $0.midiProgram == program }) {
            return match
        }

        let lowerName = name.lowercased()
        if let match = presets.first(where: {
            lowerName.contains($0.name.lowercased())
        }) {
            return match
        }

        return .piano
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16 |
        UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }
}

// MARK: - Errors

enum MIDIImportError: LocalizedError {
    case invalidFile
    case unsupportedFormat(Int)
    case smpteNotSupported
    case invalidTrackHeader

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Invalid MIDI file."
        case .unsupportedFormat(let f): return "MIDI format \(f) is not supported. Only format 0 and 1 are supported."
        case .smpteNotSupported: return "SMPTE time division is not supported."
        case .invalidTrackHeader: return "Invalid track header in MIDI file."
        }
    }
}
