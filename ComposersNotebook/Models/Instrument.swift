import Foundation

// MARK: - Instrument Group

enum InstrumentGroup: String, Codable, CaseIterable {
    case woodwinds     // Деревянные духовые
    case brass         // Медные духовые
    case percussion    // Ударные
    case strings       // Струнные
    case keyboards     // Клавишные
    case voices        // Вокал

    var displayName: String {
        switch self {
        case .woodwinds: return "Деревянные духовые"
        case .brass: return "Медные духовые"
        case .percussion: return "Ударные"
        case .strings: return "Струнные"
        case .keyboards: return "Клавишные"
        case .voices: return "Вокал"
        }
    }

    /// Sort order in orchestral score (top to bottom)
    var scoreOrder: Int {
        switch self {
        case .woodwinds: return 0
        case .brass: return 1
        case .percussion: return 2
        case .voices: return 3
        case .keyboards: return 4
        case .strings: return 5
        }
    }
}

// MARK: - Instrument

struct Instrument: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String            // "Флейта", "Скрипка", etc.
    var shortName: String       // "Фл.", "Скр.", etc.
    var group: InstrumentGroup
    var defaultClef: Clef
    var staves: Int             // 1 = single staff, 2 = grand staff (piano, organ)
    var clefs: [Clef]           // clef per staff: [treble] or [treble, bass]
    var midiProgram: Int        // General MIDI program number (0-127)
    var lowestNote: Pitch       // нижняя граница диапазона
    var highestNote: Pitch      // верхняя граница диапазона
    var transposition: Int      // semitones (0 = concert pitch, e.g. Bb clarinet = -2)

    init(
        name: String,
        shortName: String,
        group: InstrumentGroup,
        defaultClef: Clef,
        midiProgram: Int,
        lowestNote: Pitch,
        highestNote: Pitch,
        transposition: Int = 0,
        staves: Int = 1,
        clefs: [Clef]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.shortName = shortName
        self.group = group
        self.defaultClef = defaultClef
        self.staves = staves
        self.clefs = clefs ?? [defaultClef]
        self.midiProgram = midiProgram
        self.lowestNote = lowestNote
        self.highestNote = highestNote
        self.transposition = transposition
    }

    /// Check if a pitch is within the instrument's range
    func isInRange(_ pitch: Pitch) -> Bool {
        let midi = pitch.midiNote
        return midi >= lowestNote.midiNote && midi <= highestNote.midiNote
    }

    var rangeDisplayString: String {
        return "\(lowestNote.displayString) — \(highestNote.displayString)"
    }
}

// MARK: - Standard Instruments Library

extension Instrument {

    // MARK: Woodwinds

    static let piccolo = Instrument(
        name: "Пикколо", shortName: "Пик.",
        group: .woodwinds, defaultClef: .treble, midiProgram: 72,
        lowestNote: Pitch(name: .D, octave: 5),
        highestNote: Pitch(name: .C, octave: 8),
        transposition: 12
    )

    static let flute = Instrument(
        name: "Флейта", shortName: "Фл.",
        group: .woodwinds, defaultClef: .treble, midiProgram: 73,
        lowestNote: Pitch(name: .C, octave: 4),
        highestNote: Pitch(name: .D, octave: 7)
    )

    static let oboe = Instrument(
        name: "Гобой", shortName: "Гоб.",
        group: .woodwinds, defaultClef: .treble, midiProgram: 68,
        lowestNote: Pitch(name: .B, octave: 3, accidental: .flat),
        highestNote: Pitch(name: .A, octave: 6)
    )

    static let clarinetBb = Instrument(
        name: "Кларнет (Си-бемоль)", shortName: "Кл.",
        group: .woodwinds, defaultClef: .treble, midiProgram: 71,
        lowestNote: Pitch(name: .D, octave: 3),
        highestNote: Pitch(name: .B, octave: 6, accidental: .flat),
        transposition: -2
    )

    static let bassoon = Instrument(
        name: "Фагот", shortName: "Фаг.",
        group: .woodwinds, defaultClef: .bass, midiProgram: 70,
        lowestNote: Pitch(name: .B, octave: 1, accidental: .flat),
        highestNote: Pitch(name: .E, octave: 5)
    )

    // MARK: Brass

    static let hornF = Instrument(
        name: "Валторна (Фа)", shortName: "Влт.",
        group: .brass, defaultClef: .treble, midiProgram: 60,
        lowestNote: Pitch(name: .B, octave: 1),
        highestNote: Pitch(name: .F, octave: 5),
        transposition: -7
    )

    static let trumpet = Instrument(
        name: "Труба (Си-бемоль)", shortName: "Тр.",
        group: .brass, defaultClef: .treble, midiProgram: 56,
        lowestNote: Pitch(name: .F, octave: 3, accidental: .sharp),
        highestNote: Pitch(name: .D, octave: 6),
        transposition: -2
    )

    static let trombone = Instrument(
        name: "Тромбон", shortName: "Трб.",
        group: .brass, defaultClef: .bass, midiProgram: 57,
        lowestNote: Pitch(name: .E, octave: 2),
        highestNote: Pitch(name: .B, octave: 4, accidental: .flat)
    )

    static let tuba = Instrument(
        name: "Туба", shortName: "Туб.",
        group: .brass, defaultClef: .bass, midiProgram: 58,
        lowestNote: Pitch(name: .D, octave: 1),
        highestNote: Pitch(name: .F, octave: 4)
    )

    // MARK: Percussion

    static let timpani = Instrument(
        name: "Литавры", shortName: "Лит.",
        group: .percussion, defaultClef: .bass, midiProgram: 47,
        lowestNote: Pitch(name: .C, octave: 2),
        highestNote: Pitch(name: .C, octave: 4)
    )

    static let xylophone = Instrument(
        name: "Ксилофон", shortName: "Ксл.",
        group: .percussion, defaultClef: .treble, midiProgram: 13,
        lowestNote: Pitch(name: .F, octave: 4),
        highestNote: Pitch(name: .C, octave: 8)
    )

    static let glockenspiel = Instrument(
        name: "Глокеншпиль", shortName: "Глк.",
        group: .percussion, defaultClef: .treble, midiProgram: 9,
        lowestNote: Pitch(name: .G, octave: 5),
        highestNote: Pitch(name: .C, octave: 8)
    )

    static let snare = Instrument(
        name: "Малый барабан", shortName: "М.б.",
        group: .percussion, defaultClef: .treble, midiProgram: 115,
        lowestNote: Pitch(name: .C, octave: 4),
        highestNote: Pitch(name: .C, octave: 5)
    )

    static let bassDrum = Instrument(
        name: "Большой барабан", shortName: "Б.б.",
        group: .percussion, defaultClef: .bass, midiProgram: 116,
        lowestNote: Pitch(name: .C, octave: 2),
        highestNote: Pitch(name: .C, octave: 3)
    )

    static let cymbals = Instrument(
        name: "Тарелки", shortName: "Тар.",
        group: .percussion, defaultClef: .treble, midiProgram: 119,
        lowestNote: Pitch(name: .C, octave: 4),
        highestNote: Pitch(name: .C, octave: 5)
    )

    // MARK: Strings

    static let violin = Instrument(
        name: "Скрипка", shortName: "Скр.",
        group: .strings, defaultClef: .treble, midiProgram: 40,
        lowestNote: Pitch(name: .G, octave: 3),
        highestNote: Pitch(name: .A, octave: 7)
    )

    static let viola = Instrument(
        name: "Альт", shortName: "Альт",
        group: .strings, defaultClef: .alto, midiProgram: 41,
        lowestNote: Pitch(name: .C, octave: 3),
        highestNote: Pitch(name: .E, octave: 6)
    )

    static let cello = Instrument(
        name: "Виолончель", shortName: "Влч.",
        group: .strings, defaultClef: .bass, midiProgram: 42,
        lowestNote: Pitch(name: .C, octave: 2),
        highestNote: Pitch(name: .C, octave: 6)
    )

    static let doubleBass = Instrument(
        name: "Контрабас", shortName: "Кб.",
        group: .strings, defaultClef: .bass, midiProgram: 43,
        lowestNote: Pitch(name: .E, octave: 1),
        highestNote: Pitch(name: .C, octave: 5),
        transposition: -12
    )

    // MARK: Plucked Strings

    static let acousticGuitar = Instrument(
        name: "Акустическая гитара", shortName: "Ак.г.",
        group: .strings, defaultClef: .treble, midiProgram: 25,
        lowestNote: Pitch(name: .E, octave: 2),
        highestNote: Pitch(name: .E, octave: 6),
        transposition: -12
    )

    static let classicalGuitar = Instrument(
        name: "Классическая гитара", shortName: "Кл.г.",
        group: .strings, defaultClef: .treble, midiProgram: 24,
        lowestNote: Pitch(name: .E, octave: 2),
        highestNote: Pitch(name: .B, octave: 5),
        transposition: -12
    )

    static let harp = Instrument(
        name: "Арфа", shortName: "Арф.",
        group: .strings, defaultClef: .treble, midiProgram: 46,
        lowestNote: Pitch(name: .C, octave: 1),
        highestNote: Pitch(name: .G, octave: 7)
    )

    // MARK: Keyboards

    static let piano = Instrument(
        name: "Фортепиано", shortName: "Ф-но",
        group: .keyboards, defaultClef: .treble, midiProgram: 0,
        lowestNote: Pitch(name: .A, octave: 0),
        highestNote: Pitch(name: .C, octave: 8),
        staves: 2, clefs: [.treble, .bass]
    )

    static let organ = Instrument(
        name: "Орган", shortName: "Орг.",
        group: .keyboards, defaultClef: .treble, midiProgram: 19,
        lowestNote: Pitch(name: .C, octave: 2),
        highestNote: Pitch(name: .C, octave: 7),
        staves: 3, clefs: [.treble, .bass, .bass]
    )

    static let celesta = Instrument(
        name: "Челеста", shortName: "Чел.",
        group: .keyboards, defaultClef: .treble, midiProgram: 8,
        lowestNote: Pitch(name: .C, octave: 4),
        highestNote: Pitch(name: .C, octave: 8)
    )

    // MARK: Voices

    static let soprano = Instrument(
        name: "Сопрано", shortName: "С.",
        group: .voices, defaultClef: .treble, midiProgram: 52,
        lowestNote: Pitch(name: .C, octave: 4),
        highestNote: Pitch(name: .C, octave: 6)
    )

    static let alto = Instrument(
        name: "Контральто", shortName: "А.",
        group: .voices, defaultClef: .treble, midiProgram: 52,
        lowestNote: Pitch(name: .F, octave: 3),
        highestNote: Pitch(name: .F, octave: 5)
    )

    static let tenorVoice = Instrument(
        name: "Тенор", shortName: "Т.",
        group: .voices, defaultClef: .treble, midiProgram: 52,
        lowestNote: Pitch(name: .C, octave: 3),
        highestNote: Pitch(name: .C, octave: 5)
    )

    static let bassVoice = Instrument(
        name: "Бас", shortName: "Б.",
        group: .voices, defaultClef: .bass, midiProgram: 52,
        lowestNote: Pitch(name: .E, octave: 2),
        highestNote: Pitch(name: .E, octave: 4)
    )

    // MARK: All instruments

    static let allInstruments: [Instrument] = [
        // Woodwinds
        .piccolo, .flute, .oboe, .clarinetBb, .bassoon,
        // Brass
        .hornF, .trumpet, .trombone, .tuba,
        // Percussion
        .timpani, .xylophone, .glockenspiel, .snare, .bassDrum, .cymbals,
        // Strings (bowed)
        .violin, .viola, .cello, .doubleBass,
        // Strings (plucked)
        .acousticGuitar, .classicalGuitar, .harp,
        // Keyboards
        .piano, .organ, .celesta,
        // Voices
        .soprano, .alto, .tenorVoice, .bassVoice,
    ]

    static func instruments(for group: InstrumentGroup) -> [Instrument] {
        allInstruments.filter { $0.group == group }
    }
}
