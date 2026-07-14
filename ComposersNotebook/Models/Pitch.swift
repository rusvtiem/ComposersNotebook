import Foundation

// MARK: - Pitch Name (C, D, E, F, G, A, B)

enum PitchName: Int, Codable, CaseIterable, Comparable {
    case C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6

    var displayName: String {
        switch self {
        case .C: return "До"
        case .D: return "Ре"
        case .E: return "Ми"
        case .F: return "Фа"
        case .G: return "Соль"
        case .A: return "Ля"
        case .B: return "Си"
        }
    }

    var englishName: String {
        switch self {
        case .C: return "C"
        case .D: return "D"
        case .E: return "E"
        case .F: return "F"
        case .G: return "G"
        case .A: return "A"
        case .B: return "B"
        }
    }

    static func < (lhs: PitchName, rhs: PitchName) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Semitone offset within an octave from C (C=0, D=2, E=4, F=5, G=7, A=9, B=11).
    /// Used by ChordSymbol, parsers, exporters.
    var semitoneOffset: Int {
        switch self {
        case .C: return 0
        case .D: return 2
        case .E: return 4
        case .F: return 5
        case .G: return 7
        case .A: return 9
        case .B: return 11
        }
    }

    /// Parse pitch name from "A".."G".
    static func fromEnglishName(_ letter: String) -> PitchName? {
        switch letter.uppercased() {
        case "C": return .C
        case "D": return .D
        case "E": return .E
        case "F": return .F
        case "G": return .G
        case "A": return .A
        case "B": return .B
        default: return nil
        }
    }
}

// MARK: - Accidental

enum Accidental: Int, Codable, CaseIterable {
    case doubleFlat = -2
    case flat = -1
    case natural = 0
    case sharp = 1
    case doubleSharp = 2

    var displaySymbol: String {
        switch self {
        case .doubleFlat: return "𝄫"
        case .flat: return "♭"
        case .natural: return "♮"
        case .sharp: return "♯"
        case .doubleSharp: return "𝄪"
        }
    }

    var semitoneOffset: Int { rawValue }
}

// MARK: - Pitch

struct Pitch: Codable, Equatable, Hashable {
    let name: PitchName
    let octave: Int // 0-9 (middle C = C4)
    var accidental: Accidental

    init(name: PitchName, octave: Int, accidental: Accidental = .natural) {
        self.name = name
        self.octave = octave
        self.accidental = accidental
    }

    /// MIDI note number (0-127). Middle C (C4) = 60
    var midiNote: Int {
        let baseSemitones: [PitchName: Int] = [
            .C: 0, .D: 2, .E: 4, .F: 5, .G: 7, .A: 9, .B: 11
        ]
        let base = (octave + 1) * 12 + (baseSemitones[name] ?? 0)
        return base + accidental.semitoneOffset
    }

    /// Staff position relative to middle C (C4 = 0, D4 = 1, etc.)
    var staffPosition: Int {
        return (octave - 4) * 7 + name.rawValue
    }

    /// Create a natural pitch from a diatonic staff position (inverse of
    /// `staffPosition`; C4 = 0, D4 = 1, …). Used when a tap on an engraved staff
    /// is resolved to a line/space and must become a concrete note; the caller
    /// adds any accidental afterwards.
    static func fromStaffPosition(_ position: Int) -> Pitch {
        let nameRaw = ((position % 7) + 7) % 7
        let octave = 4 + (position - nameRaw) / 7
        return Pitch(name: PitchName(rawValue: nameRaw) ?? .C, octave: octave)
    }

    /// Create pitch from MIDI note number. Black keys default to sharp spelling.
    static func fromMIDI(_ note: Int) -> Pitch {
        fromMIDI(note, preferFlats: false)
    }

    /// Create pitch from MIDI note number, choosing the spelling of the five black
    /// keys. MuseScore spells a chromatic step down with flats and up with sharps
    /// (Down-arrow on E gives E♭, Up-arrow gives D♯) — pass `preferFlats: true`
    /// when the motion is downward so the accidental matches the direction.
    static func fromMIDI(_ note: Int, preferFlats: Bool) -> Pitch {
        let octave = (note / 12) - 1
        let semitone = ((note % 12) + 12) % 12
        let sharpMap: [(PitchName, Accidental)] = [
            (.C, .natural), (.C, .sharp), (.D, .natural), (.D, .sharp),
            (.E, .natural), (.F, .natural), (.F, .sharp), (.G, .natural),
            (.G, .sharp), (.A, .natural), (.A, .sharp), (.B, .natural)
        ]
        let flatMap: [(PitchName, Accidental)] = [
            (.C, .natural), (.D, .flat), (.D, .natural), (.E, .flat),
            (.E, .natural), (.F, .natural), (.G, .flat), (.G, .natural),
            (.A, .flat), (.A, .natural), (.B, .flat), (.B, .natural)
        ]
        let (name, accidental) = (preferFlats ? flatMap : sharpMap)[semitone]
        return Pitch(name: name, octave: octave, accidental: accidental)
    }

    /// Musically-useful enharmonic spellings of the same sounding pitch (same
    /// `midiNote`), sorted by letter so cycling is deterministic. Candidates are
    /// limited to single accidentals (♭ ♮ ♯) — double-flat/double-sharp respellings
    /// (C → D𝄫) are noise for a respell command — but `self` is always included so
    /// a note that already carries a double accidental can be respelled out of it.
    /// Drives the "respell" (MuseScore J) command.
    func enharmonicSpellings() -> [Pitch] {
        let target = midiNote
        var out: [Pitch] = []
        for raw in 0..<7 {
            let letter = PitchName(rawValue: raw) ?? .C
            for oct in (octave - 1)...(octave + 1) {
                let natural = Pitch(name: letter, octave: oct, accidental: .natural).midiNote
                let need = target - natural
                guard need >= -1, need <= 1, let acc = Accidental(rawValue: need) else { continue }
                let candidate = Pitch(name: letter, octave: oct, accidental: acc)
                if !out.contains(candidate) { out.append(candidate) }
            }
        }
        if !out.contains(self) { out.append(self) }
        return out.sorted { ($0.name.rawValue, $0.octave) < ($1.name.rawValue, $1.octave) }
    }

    /// Next enharmonic spelling after `self` (wraps). Same sound, different
    /// notation — e.g. C♯4 → D♭4 → C♯4. Returns `self` if no alternative exists.
    func respelledEnharmonic() -> Pitch {
        let spellings = enharmonicSpellings()
        guard spellings.count > 1,
              let idx = spellings.firstIndex(of: self) else { return self }
        return spellings[(idx + 1) % spellings.count]
    }

    var displayString: String {
        let acc = accidental == .natural ? "" : accidental.displaySymbol
        return "\(name.displayName)\(acc)\(octave)"
    }
}
