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

    /// Create pitch from MIDI note number
    static func fromMIDI(_ note: Int) -> Pitch {
        let octave = (note / 12) - 1
        let semitone = note % 12
        let mapping: [(PitchName, Accidental)] = [
            (.C, .natural), (.C, .sharp), (.D, .natural), (.D, .sharp),
            (.E, .natural), (.F, .natural), (.F, .sharp), (.G, .natural),
            (.G, .sharp), (.A, .natural), (.A, .sharp), (.B, .natural)
        ]
        let (name, accidental) = mapping[semitone]
        return Pitch(name: name, octave: octave, accidental: accidental)
    }

    var displayString: String {
        let acc = accidental == .natural ? "" : accidental.displaySymbol
        return "\(name.displayName)\(acc)\(octave)"
    }
}
