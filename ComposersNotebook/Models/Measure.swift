import Foundation

// MARK: - Measure (Такт)

struct Measure: Codable, Equatable, Identifiable {
    let id: UUID
    var events: [NoteEvent]
    var timeSignature: TimeSignature?       // nil = наследуется от предыдущего
    var keySignature: KeySignature?         // nil = наследуется от предыдущего
    var clefChange: Clef?                   // nil = без смены ключа
    var tempoMarking: TempoMarking?         // nil = без смены темпа
    var barlineEnd: BarlineType             // тип тактовой черты в конце
    var navigationMark: NavigationMark?     // D.C., D.S., Fine, etc.
    var hairpins: [Hairpin]
    var volta: Volta?
    // --- Phase 2c extensions ---
    var octaveShifts: [OctaveShift]         // 8va/15ma spanners в пределах такта
    var rehearsalMark: RehearsalMark?       // буквенный/числовой маркер для оркестра
    var expressionTexts: [ExpressionText]   // espressivo, dolce, agitato и т.д.
    var tempoChange: TempoChange?           // accel./rit. начинающийся в этом такте
    var multiMeasureRestCount: Int          // > 0 — пауза N тактов, рисуется одним блоком

    init(
        events: [NoteEvent] = [],
        timeSignature: TimeSignature? = nil,
        keySignature: KeySignature? = nil,
        clefChange: Clef? = nil,
        tempoMarking: TempoMarking? = nil,
        barlineEnd: BarlineType = .regular,
        navigationMark: NavigationMark? = nil,
        hairpins: [Hairpin] = [],
        volta: Volta? = nil,
        octaveShifts: [OctaveShift] = [],
        rehearsalMark: RehearsalMark? = nil,
        expressionTexts: [ExpressionText] = [],
        tempoChange: TempoChange? = nil,
        multiMeasureRestCount: Int = 0
    ) {
        self.id = UUID()
        self.events = events
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.clefChange = clefChange
        self.tempoMarking = tempoMarking
        self.barlineEnd = barlineEnd
        self.navigationMark = navigationMark
        self.hairpins = hairpins
        self.volta = volta
        self.octaveShifts = octaveShifts
        self.rehearsalMark = rehearsalMark
        self.expressionTexts = expressionTexts
        self.tempoChange = tempoChange
        self.multiMeasureRestCount = multiMeasureRestCount
    }

    // Backward compatibility: старые .cnb файлы без новых полей.
    private enum CodingKeys: String, CodingKey {
        case id, events, timeSignature, keySignature, clefChange, tempoMarking
        case barlineEnd, navigationMark, hairpins, volta
        case octaveShifts, rehearsalMark, expressionTexts, tempoChange, multiMeasureRestCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.events = try c.decodeIfPresent([NoteEvent].self, forKey: .events) ?? []
        self.timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature)
        self.keySignature = try c.decodeIfPresent(KeySignature.self, forKey: .keySignature)
        self.clefChange = try c.decodeIfPresent(Clef.self, forKey: .clefChange)
        self.tempoMarking = try c.decodeIfPresent(TempoMarking.self, forKey: .tempoMarking)
        self.barlineEnd = try c.decodeIfPresent(BarlineType.self, forKey: .barlineEnd) ?? .regular
        self.navigationMark = try c.decodeIfPresent(NavigationMark.self, forKey: .navigationMark)
        self.hairpins = try c.decodeIfPresent([Hairpin].self, forKey: .hairpins) ?? []
        self.volta = try c.decodeIfPresent(Volta.self, forKey: .volta)
        self.octaveShifts = try c.decodeIfPresent([OctaveShift].self, forKey: .octaveShifts) ?? []
        self.rehearsalMark = try c.decodeIfPresent(RehearsalMark.self, forKey: .rehearsalMark)
        self.expressionTexts = try c.decodeIfPresent([ExpressionText].self, forKey: .expressionTexts) ?? []
        self.tempoChange = try c.decodeIfPresent(TempoChange.self, forKey: .tempoChange)
        self.multiMeasureRestCount = try c.decodeIfPresent(Int.self, forKey: .multiMeasureRestCount) ?? 0
    }

    /// Такт содержит только один целый rest — плейсхолдер «пустой такт»
    /// (полнотактовая пауза). Рисуется как целая пауза в любом размере.
    var isFullMeasureRest: Bool {
        events.count == 1
            && events[0].isRest
            && events[0].duration.value == .whole
            && !events[0].duration.dotted
            && !events[0].duration.doubleDotted
            && !events[0].duration.triplet
    }

    /// Total beats used in this measure (учитывает tuplet'ы).
    /// Внимание: полнотактовая пауза здесь считается фиксированными 4 долями
    /// (целая нота). Для проверок вместимости используй `usedBeats(timeSignature:)`.
    var usedBeats: Double {
        events.reduce(0) { $0 + $1.actualBeats }
    }

    /// Занятые доли с учётом размера: полнотактовая пауза = длина такта,
    /// а не фиксированные 4 доли. Иначе в не-4/4 (3/4, 6/8, …) пустой такт
    /// давал ложное переполнение (4 доли против 3).
    func usedBeats(timeSignature ts: TimeSignature) -> Double {
        if isFullMeasureRest { return ts.totalBeats }
        return usedBeats
    }

    /// Check if measure is full (no more room for notes)
    func isFull(timeSignature ts: TimeSignature) -> Bool {
        return usedBeats(timeSignature: ts) >= ts.totalBeats
    }

    /// Remaining beats in measure
    func remainingBeats(timeSignature ts: TimeSignature) -> Double {
        return max(0, ts.totalBeats - usedBeats(timeSignature: ts))
    }

    /// Create an empty measure
    static func empty() -> Measure {
        Measure()
    }

    /// Create a measure filled with a whole rest
    static func wholeRest() -> Measure {
        Measure(events: [.rest(duration: .wholeNote)])
    }
}
