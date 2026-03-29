import Foundation

// MARK: - Clef

enum Clef: String, Codable, CaseIterable {
    case treble   // скрипичный
    case bass     // басовый
    case alto     // альтовый
    case tenor    // теноровый

    var displayName: String {
        switch self {
        case .treble: return "Скрипичный"
        case .bass: return "Басовый"
        case .alto: return "Альтовый"
        case .tenor: return "Теноровый"
        }
    }

    var symbol: String {
        switch self {
        case .treble: return "𝄞"
        case .bass: return "𝄢"
        case .alto: return "𝄡"
        case .tenor: return "𝄡"
        }
    }

    /// Reference pitch for the middle line of the staff
    var referencePitch: Pitch {
        switch self {
        case .treble: return Pitch(name: .B, octave: 4)  // B4 on middle line
        case .bass: return Pitch(name: .D, octave: 3)    // D3 on middle line
        case .alto: return Pitch(name: .C, octave: 4)    // C4 on middle line
        case .tenor: return Pitch(name: .A, octave: 3)   // A3 on middle line
        }
    }
}

// MARK: - Key Signature

enum KeySignatureType: String, Codable {
    case major
    case minor
}

struct KeySignature: Codable, Equatable {
    let fifths: Int  // -7 to +7 (negative = flats, positive = sharps)
    let mode: KeySignatureType

    var displayName: String {
        let names: [Int: (major: String, minor: String)] = [
            -7: ("До-бемоль мажор", "ля-бемоль минор"),
            -6: ("Соль-бемоль мажор", "ми-бемоль минор"),
            -5: ("Ре-бемоль мажор", "си-бемоль минор"),
            -4: ("Ля-бемоль мажор", "фа минор"),
            -3: ("Ми-бемоль мажор", "до минор"),
            -2: ("Си-бемоль мажор", "соль минор"),
            -1: ("Фа мажор", "ре минор"),
             0: ("До мажор", "ля минор"),
             1: ("Соль мажор", "ми минор"),
             2: ("Ре мажор", "си минор"),
             3: ("Ля мажор", "фа-диез минор"),
             4: ("Ми мажор", "до-диез минор"),
             5: ("Си мажор", "соль-диез минор"),
             6: ("Фа-диез мажор", "ре-диез минор"),
             7: ("До-диез мажор", "ля-диез минор"),
        ]
        if let pair = names[fifths] {
            return mode == .major ? pair.major : pair.minor
        }
        return "Неизвестная тональность"
    }

    static let cMajor = KeySignature(fifths: 0, mode: .major)
    static let aMinor = KeySignature(fifths: 0, mode: .minor)
}

// MARK: - Time Signature

struct TimeSignature: Codable, Equatable {
    let beats: Int       // верхняя цифра (сколько долей в такте)
    let beatValue: Int   // нижняя цифра (какая нота = доля)

    /// Total beats in the measure (in quarter note units)
    var totalBeats: Double {
        return Double(beats) * (4.0 / Double(beatValue))
    }

    var displayString: String {
        return "\(beats)/\(beatValue)"
    }

    static let fourFour = TimeSignature(beats: 4, beatValue: 4)
    static let threeFour = TimeSignature(beats: 3, beatValue: 4)
    static let sixEight = TimeSignature(beats: 6, beatValue: 8)
    static let fiveEight = TimeSignature(beats: 5, beatValue: 8)
    static let twoFour = TimeSignature(beats: 2, beatValue: 4)
    static let threeeEight = TimeSignature(beats: 3, beatValue: 8)
}

// MARK: - Dynamic Marking

enum DynamicMarking: String, Codable, CaseIterable {
    case ppp, pp, p, mp, mf, f, ff, fff
    case sfz, sfp, fp

    var displayName: String { rawValue }

    var velocity: Int {
        switch self {
        case .ppp: return 16
        case .pp: return 33
        case .p: return 49
        case .mp: return 64
        case .mf: return 80
        case .f: return 96
        case .ff: return 112
        case .fff: return 127
        case .sfz: return 127
        case .sfp: return 112
        case .fp: return 96
        }
    }
}

// MARK: - Hairpin (crescendo/diminuendo)

enum HairpinType: String, Codable {
    case crescendo
    case diminuendo
}

struct Hairpin: Codable, Equatable, Identifiable {
    let id: UUID
    var type: HairpinType
    var startBeat: Double
    var endBeat: Double

    init(type: HairpinType, startBeat: Double, endBeat: Double) {
        self.id = UUID()
        self.type = type
        self.startBeat = startBeat
        self.endBeat = endBeat
    }
}

// MARK: - Tempo Marking

struct TempoMarking: Codable, Equatable {
    var bpm: Double
    var name: String?   // "Allegro", "Andante", etc.

    var displayString: String {
        if let name = name {
            return "\(name) (♩= \(Int(bpm)))"
        }
        return "♩= \(Int(bpm))"
    }

    static let commonTempos: [(String, Double)] = [
        ("Grave", 40),
        ("Largo", 46),
        ("Lento", 52),
        ("Adagio", 60),
        ("Andante", 76),
        ("Moderato", 92),
        ("Allegretto", 108),
        ("Allegro", 120),
        ("Vivace", 140),
        ("Presto", 168),
        ("Prestissimo", 200),
    ]
}

// MARK: - Repeat / Barline

enum BarlineType: String, Codable {
    case regular
    case double
    case final_          // двойная жирная (конец)
    case repeatStart     // реприза начало
    case repeatEnd       // реприза конец
    case repeatBoth      // реприза обе стороны
}

// MARK: - Volta (1st/2nd ending)

struct Volta: Codable, Equatable, Identifiable {
    let id: UUID
    var number: Int          // 1, 2, etc.
    var startMeasure: Int
    var endMeasure: Int

    init(number: Int, startMeasure: Int, endMeasure: Int) {
        self.id = UUID()
        self.number = number
        self.startMeasure = startMeasure
        self.endMeasure = endMeasure
    }
}

// MARK: - Navigation marks

enum NavigationMark: String, Codable {
    case segno          // сеньо
    case coda           // кода
    case dcAlFine       // D.C. al Fine
    case dcAlCoda       // D.C. al Coda
    case dsAlFine       // D.S. al Fine
    case dsAlCoda       // D.S. al Coda
    case fine           // Fine

    var displayString: String {
        switch self {
        case .segno: return "𝄋"
        case .coda: return "𝄌"
        case .dcAlFine: return "D.C. al Fine"
        case .dcAlCoda: return "D.C. al Coda"
        case .dsAlFine: return "D.S. al Fine"
        case .dsAlCoda: return "D.S. al Coda"
        case .fine: return "Fine"
        }
    }
}

// MARK: - Articulation

enum Articulation: String, Codable, CaseIterable {
    case staccato
    case legato
    case accent
    case tenuto
    case marcato
    case fermata

    var displaySymbol: String {
        switch self {
        case .staccato: return "•"
        case .legato: return "⁀"
        case .accent: return ">"
        case .tenuto: return "–"
        case .marcato: return "^"
        case .fermata: return "𝄐"
        }
    }

    var displayName: String {
        switch self {
        case .staccato: return "Стаккато"
        case .legato: return "Легато"
        case .accent: return "Акцент"
        case .tenuto: return "Тенуто"
        case .marcato: return "Маркато"
        case .fermata: return "Фермата"
        }
    }
}
