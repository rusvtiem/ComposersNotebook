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

// MARK: - MuseScore "measure always full of real rests" invariant

extension Measure {
    /// Tick resolution for rest decomposition: quarter note = 16 ticks
    /// (whole = 64, 64th = 1). Fine enough for every binary duration we support.
    static let ticksPerBeat: Double = 16.0

    /// Decompose a rest span into individually-notated rest events the way
    /// MuseScore does: a rest never crosses a metric boundary stronger than its
    /// own start alignment (a rest of length L must begin on a multiple of L).
    /// Produces plain (undotted) binary rests — always a correct, readable fill.
    /// Fractional spans (from tuplet/dotted remainders) are rounded to the 1/64
    /// grid; anything left below one tick is dropped.
    static func restEvents(fillingBeats beats: Double, startBeat: Double,
                           voice: VoiceLayer = .voice1) -> [NoteEvent] {
        var remaining = Int((beats * ticksPerBeat).rounded())
        guard remaining > 0 else { return [] }
        var pos = Int((startBeat * ticksPerBeat).rounded())
        let table: [(Int, DurationValue)] = [
            (64, .whole), (32, .half), (16, .quarter),
            (8, .eighth), (4, .sixteenth), (2, .thirtySecond), (1, .sixtyFourth)
        ]
        var out: [NoteEvent] = []
        var safety = 0
        while remaining > 0 && safety < 256 {
            safety += 1
            let align = pos == 0 ? Int.max : (pos & (-pos))
            var chosen: (Int, DurationValue)?
            for (t, v) in table where t <= remaining && t <= align { chosen = (t, v); break }
            guard let (t, v) = chosen else { break }
            var ev = NoteEvent(type: .rest, duration: Duration(value: v))
            ev.voice = voice
            out.append(ev)
            remaining -= t
            pos += t
        }
        return out
    }

    /// MuseScore step-time overwrite: place `newEvent` at `startBeat`, removing
    /// whatever occupied that span, and refill the affected region with rests so
    /// the measure stays exactly `totalBeats` long. Grace notes (0 length) are
    /// preserved on the side of the region they fall on. Guarantees the "measure
    /// always full of real, individually selectable rests" invariant.
    static func overwrite(_ events: [NoteEvent], with newEvent: NoteEvent,
                          atBeat startBeat: Double, totalBeats: Double) -> [NoteEvent] {
        let tpb = ticksPerBeat
        let startTick = Int((startBeat * tpb).rounded())
        let newLen = Int((max(0, newEvent.actualBeats) * tpb).rounded())
        let endTick = startTick + newLen
        let totalTick = Int((totalBeats * tpb).rounded())

        struct Span { let ev: NoteEvent; let start: Int; let end: Int; let isGrace: Bool }
        var spans: [Span] = []
        var pos = 0
        for ev in events {
            if ev.actualBeats <= 0 {
                spans.append(Span(ev: ev, start: pos, end: pos, isGrace: true))
            } else {
                let len = Int((ev.actualBeats * tpb).rounded())
                spans.append(Span(ev: ev, start: pos, end: pos + len, isGrace: false))
                pos += len
            }
        }

        var out: [NoteEvent] = []
        // Everything before the overwrite region.
        for s in spans {
            if s.isGrace {
                if s.start <= startTick { out.append(s.ev) }
            } else if s.end <= startTick {
                out.append(s.ev)
            } else if s.start < startTick {
                // Straddles the start — that leftover is a rest span, refill it.
                out.append(contentsOf: restEvents(
                    fillingBeats: Double(startTick - s.start) / tpb,
                    startBeat: Double(s.start) / tpb, voice: newEvent.voice))
            }
        }
        out.append(newEvent)
        // Everything after the overwrite region.
        for s in spans {
            if s.isGrace {
                if s.start >= endTick { out.append(s.ev) }
            } else if s.start >= endTick {
                out.append(s.ev)
            } else if s.end > endTick {
                out.append(contentsOf: restEvents(
                    fillingBeats: Double(s.end - endTick) / tpb,
                    startBeat: Double(endTick) / tpb, voice: newEvent.voice))
            }
        }

        // Refill any tail deficit (e.g. overwriting into a previously empty measure).
        let usedTicks = out.reduce(0) { acc, ev in
            acc + (ev.actualBeats > 0 ? Int((ev.actualBeats * tpb).rounded()) : 0)
        }
        if usedTicks < totalTick {
            out.append(contentsOf: restEvents(
                fillingBeats: Double(totalTick - usedTicks) / tpb,
                startBeat: Double(usedTicks) / tpb, voice: newEvent.voice))
        }
        return out
    }
}
