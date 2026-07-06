import Foundation

// MARK: - Stem Direction

enum StemDirection: Int, Codable, Equatable {
    case auto = 0    // Автоматически по позиции ноты
    case up = 1      // Штиль вверх
    case down = 2    // Штиль вниз
}

// MARK: - Note Event (note or rest)

enum NoteEventType: Codable, Equatable {
    case note(pitch: Pitch)
    case chord(pitches: [Pitch])
    case rest
}

// MARK: - Voice Layer

enum VoiceLayer: Int, Codable, Equatable, CaseIterable {
    case voice1 = 1
    case voice2 = 2
    case voice3 = 3
    case voice4 = 4

    var displayName: String {
        switch self {
        case .voice1: return "Голос 1"
        case .voice2: return "Голос 2"
        case .voice3: return "Голос 3"
        case .voice4: return "Голос 4"
        }
    }

    var color: String {
        switch self {
        case .voice1: return "blue"
        case .voice2: return "green"
        case .voice3: return "orange"
        case .voice4: return "purple"
        }
    }
}

// MARK: - Playback Technique

enum PlaybackTechnique: String, Codable, Equatable, CaseIterable {
    // Strings (bowed)
    case arco           // смычком (default)
    case pizzicato      // щипком
    case colLegno       // древком смычка
    case sulPonticello  // у подставки
    case sulTasto       // у грифа
    case tremolo        // тремоло

    // Strings (plucked) / Guitar
    case fingerStyle    // пальцами
    case pickStyle      // медиатором
    case strumDown      // бой вниз
    case strumUp        // бой вверх

    // Percussion
    case sticks         // палочки (default)
    case brushes        // щётки
    case mallets        // молоточки

    var displayName: String {
        switch self {
        case .arco: return "Arco (смычком)"
        case .pizzicato: return "Pizzicato (щипком)"
        case .colLegno: return "Col legno (древком)"
        case .sulPonticello: return "Sul ponticello (у подставки)"
        case .sulTasto: return "Sul tasto (у грифа)"
        case .tremolo: return "Tremolo (тремоло)"
        case .fingerStyle: return "Finger (пальцами)"
        case .pickStyle: return "Pick (медиатором)"
        case .strumDown: return "Strum ↓ (бой вниз)"
        case .strumUp: return "Strum ↑ (бой вверх)"
        case .sticks: return "Sticks (палочки)"
        case .brushes: return "Brushes (щётки)"
        case .mallets: return "Mallets (молоточки)"
        }
    }

    var italianName: String {
        switch self {
        case .arco: return "arco"
        case .pizzicato: return "pizz."
        case .colLegno: return "col legno"
        case .sulPonticello: return "sul pont."
        case .sulTasto: return "sul tasto"
        case .tremolo: return "trem."
        case .fingerStyle: return "finger"
        case .pickStyle: return "pick"
        case .strumDown: return "strum ↓"
        case .strumUp: return "strum ↑"
        case .sticks: return "sticks"
        case .brushes: return "brushes"
        case .mallets: return "mallets"
        }
    }

    /// Which instrument groups this technique applies to
    var applicableGroups: [InstrumentGroup] {
        switch self {
        case .arco, .pizzicato, .colLegno, .sulPonticello, .sulTasto, .tremolo:
            return [.strings]
        case .fingerStyle, .pickStyle, .strumDown, .strumUp:
            return [.strings] // specifically plucked strings
        case .sticks, .brushes, .mallets:
            return [.percussion]
        }
    }
}

// MARK: - Strum Pattern

struct StrumPattern: Codable, Equatable {
    var beats: [StrumBeat]

    struct StrumBeat: Codable, Equatable {
        var direction: StrumDirection
        var strings: [Bool]  // which strings are strummed (6 for guitar)
        var accent: Bool
    }

    enum StrumDirection: String, Codable, Equatable {
        case down
        case up
        case mute  // x — глушение
    }

    static let basicDown = StrumPattern(beats: [
        StrumBeat(direction: .down, strings: [true, true, true, true, true, true], accent: true)
    ])

    static let basicAlternating = StrumPattern(beats: [
        StrumBeat(direction: .down, strings: [true, true, true, true, true, true], accent: true),
        StrumBeat(direction: .up, strings: [true, true, true, true, true, true], accent: false)
    ])
}

struct NoteEvent: Codable, Equatable, Identifiable {
    let id: UUID
    var type: NoteEventType
    var duration: Duration
    var articulations: [Articulation]
    var dynamic: DynamicMarking?
    var tiedToNext: Bool     // залиговка (продление звучания)
    var slurStart: Bool      // начало фразировочной лиги
    var slurEnd: Bool        // конец фразировочной лиги
    var stemDirection: StemDirection  // направление штиля
    var showNatural: Bool             // явный бекар (♮)
    var voice: VoiceLayer            // голосовой слой
    var lyric: String?               // подтекстовка (lyrics)
    var technique: PlaybackTechnique? // исполнительская техника
    var strumPattern: StrumPattern?   // паттерн боя (для гитары)
    var tuplet: Tuplet?              // часть триоли / квинтоли / и т.д.
    var chordSymbol: ChordSymbol?    // аккордовый символ (G7, Am, C/E)
    var fingering: String?           // аппликатура (1-5 или гитарная)

    init(
        type: NoteEventType,
        duration: Duration,
        articulations: [Articulation] = [],
        dynamic: DynamicMarking? = nil,
        tiedToNext: Bool = false,
        slurStart: Bool = false,
        slurEnd: Bool = false,
        stemDirection: StemDirection = .auto,
        showNatural: Bool = false,
        voice: VoiceLayer = .voice1,
        lyric: String? = nil,
        technique: PlaybackTechnique? = nil,
        strumPattern: StrumPattern? = nil,
        tuplet: Tuplet? = nil,
        chordSymbol: ChordSymbol? = nil,
        fingering: String? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.duration = duration
        self.articulations = articulations
        self.dynamic = dynamic
        self.tiedToNext = tiedToNext
        self.slurStart = slurStart
        self.slurEnd = slurEnd
        self.stemDirection = stemDirection
        self.showNatural = showNatural
        self.voice = voice
        self.lyric = lyric
        self.technique = technique
        self.strumPattern = strumPattern
        self.tuplet = tuplet
        self.chordSymbol = chordSymbol
        self.fingering = fingering
    }

    // Backward compatibility: старые .cnb файлы без новых полей -> nil по умолчанию.
    // Codable optional обеспечивает миграцию.
    private enum CodingKeys: String, CodingKey {
        case id, type, duration, articulations, dynamic, tiedToNext, slurStart, slurEnd
        case stemDirection, showNatural, voice, lyric, technique, strumPattern
        case tuplet, chordSymbol, fingering
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try c.decode(NoteEventType.self, forKey: .type)
        self.duration = try c.decode(Duration.self, forKey: .duration)
        self.articulations = try c.decodeIfPresent([Articulation].self, forKey: .articulations) ?? []
        self.dynamic = try c.decodeIfPresent(DynamicMarking.self, forKey: .dynamic)
        self.tiedToNext = try c.decodeIfPresent(Bool.self, forKey: .tiedToNext) ?? false
        self.slurStart = try c.decodeIfPresent(Bool.self, forKey: .slurStart) ?? false
        self.slurEnd = try c.decodeIfPresent(Bool.self, forKey: .slurEnd) ?? false
        self.stemDirection = try c.decodeIfPresent(StemDirection.self, forKey: .stemDirection) ?? .auto
        self.showNatural = try c.decodeIfPresent(Bool.self, forKey: .showNatural) ?? false
        self.voice = try c.decodeIfPresent(VoiceLayer.self, forKey: .voice) ?? .voice1
        self.lyric = try c.decodeIfPresent(String.self, forKey: .lyric)
        self.technique = try c.decodeIfPresent(PlaybackTechnique.self, forKey: .technique)
        self.strumPattern = try c.decodeIfPresent(StrumPattern.self, forKey: .strumPattern)
        self.tuplet = try c.decodeIfPresent(Tuplet.self, forKey: .tuplet)
        self.chordSymbol = try c.decodeIfPresent(ChordSymbol.self, forKey: .chordSymbol)
        self.fingering = try c.decodeIfPresent(String.self, forKey: .fingering)
    }

    var isRest: Bool {
        if case .rest = type { return true }
        return false
    }

    var pitches: [Pitch] {
        switch type {
        case .note(let pitch): return [pitch]
        case .chord(let pitches): return pitches
        case .rest: return []
        }
    }

    /// MIDI velocity based on dynamic marking
    var velocity: Int {
        dynamic?.velocity ?? DynamicMarking.mf.velocity
    }

    /// Фактическая длительность в долях с учётом tuplet'а.
    /// Если ноты нет в tuplet — равна `duration.beats` (включая legacy triplet-флаг).
    /// Если в tuplet 3:2 — `duration.beatsIgnoringTriplet * 2/3`.
    ///
    /// Явный `Tuplet` — единственный источник триольного тайминга: он берёт
    /// базу БЕЗ triplet-флага, иначе старые .cnb с обоими признаками звучали
    /// как ×4/9 вместо ×2/3.
    var actualBeats: Double {
        guard let tuplet = tuplet else { return duration.beats }
        return duration.beatsIgnoringTriplet * tuplet.durationMultiplier
    }

    // Convenience constructors

    static func note(_ pitch: Pitch, duration: Duration) -> NoteEvent {
        NoteEvent(type: .note(pitch: pitch), duration: duration)
    }

    static func rest(duration: Duration) -> NoteEvent {
        NoteEvent(type: .rest, duration: duration)
    }

    static func chord(_ pitches: [Pitch], duration: Duration) -> NoteEvent {
        NoteEvent(type: .chord(pitches: pitches), duration: duration)
    }
}
