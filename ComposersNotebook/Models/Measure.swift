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
        durationPieces(fillingBeats: beats, startBeat: startBeat).map { v in
            var ev = NoteEvent(type: .rest, duration: Duration(value: v))
            ev.voice = voice
            return ev
        }
    }

    /// The binary, individually-notated duration values that exactly fill `beats`
    /// starting at metric position `startBeat`, choosing at each step the longest
    /// value that both fits the remainder and aligns to the current tick (a value of
    /// length L must begin on a multiple of L). Shared by rest fill and note split so
    /// both decompose spans the same MuseScore-correct way. Fractional (tuplet)
    /// remainders round to the 1/64 grid; sub-tick tails drop.
    static func durationPieces(fillingBeats beats: Double, startBeat: Double) -> [DurationValue] {
        var remaining = Int((beats * ticksPerBeat).rounded())
        guard remaining > 0 else { return [] }
        var pos = Int((startBeat * ticksPerBeat).rounded())
        let table: [(Int, DurationValue)] = [
            (64, .whole), (32, .half), (16, .quarter),
            (8, .eighth), (4, .sixteenth), (2, .thirtySecond), (1, .sixtyFourth)
        ]
        var out: [DurationValue] = []
        var safety = 0
        while remaining > 0 && safety < 256 {
            safety += 1
            let align = pos == 0 ? Int.max : (pos & (-pos))
            var chosen: (Int, DurationValue)?
            for (t, v) in table where t <= remaining && t <= align { chosen = (t, v); break }
            guard let (t, v) = chosen else { break }
            out.append(v)
            remaining -= t
            pos += t
        }
        return out
    }

    /// MuseScore Insert-mode reflow: lay a flat stream of events into consecutive
    /// bars of `totalBeats`, splitting any note/rest that crosses a barline into
    /// tied binary pieces so every bar stays exactly full. Notes get tied across the
    /// split (`tiedToNext`); the final piece of a note keeps the source event's own
    /// `tiedToNext`. Rests split without ties. Tuplet events are kept atomic (never
    /// split): if one can't fit the bar's remaining room it starts the next bar and
    /// the gap is filled with rests. The last partial bar is padded with rests.
    static func reflow(_ stream: [NoteEvent], totalBeats: Double) -> [[NoteEvent]] {
        let tpb = ticksPerBeat
        let barTicks = Int((totalBeats * tpb).rounded())
        guard barTicks > 0 else { return [stream] }

        var bars: [[NoteEvent]] = []
        var bar: [NoteEvent] = []
        var pos = 0  // tick position within the current bar

        func closeBar() {
            if pos < barTicks {
                bar.append(contentsOf: restEvents(
                    fillingBeats: Double(barTicks - pos) / tpb,
                    startBeat: Double(pos) / tpb))
            }
            bars.append(bar)
            bar = []
            pos = 0
        }

        for event in stream {
            // Grace notes carry no metric time — ride along with the current bar.
            if event.actualBeats <= 0 {
                bar.append(event)
                continue
            }
            // Tuplets stay atomic: their beat span isn't a binary value we can split.
            if event.tuplet != nil {
                let len = Int((event.actualBeats * tpb).rounded())
                if pos + len > barTicks && pos > 0 { closeBar() }
                bar.append(event)
                pos += len
                if pos >= barTicks { closeBar() }
                continue
            }

            var remaining = Int((event.actualBeats * tpb).rounded())
            var isFirstPieceOfEvent = true
            // Where each notated piece of THIS event landed, so the FINAL piece can
            // inherit the source event's own tie once the whole event is placed.
            // bar == -1 marks the still-open current bar; ≥0 an already-closed bar.
            var placedRefs: [(bar: Int, idx: Int)] = []
            while remaining > 0 {
                let room = barTicks - pos
                let take = min(remaining, room)
                let pieces = durationPieces(fillingBeats: Double(take) / tpb,
                                            startBeat: Double(pos) / tpb)
                for v in pieces {
                    var piece = event.splitPiece(duration: Duration(value: v))
                    // A note's pieces are all provisionally tied onward (repeated
                    // noteheads of one sustained sound); the true final tie is fixed
                    // after the event is fully placed. Rests never tie.
                    piece.tiedToNext = event.isRest ? false : true
                    // Ornaments/lyrics/dynamics belong to the sounding onset only, so
                    // strip them from every piece after the first to avoid duplicates.
                    if !isFirstPieceOfEvent {
                        piece.articulations = []
                        piece.dynamic = nil
                        piece.lyric = nil
                        piece.chordSymbol = nil
                        piece.slurStart = false
                    }
                    isFirstPieceOfEvent = false
                    bar.append(piece)
                    placedRefs.append((bar: -1, idx: bar.count - 1))
                }
                pos += take
                remaining -= take
                if pos >= barTicks {
                    let closingIndex = bars.count
                    for i in placedRefs.indices where placedRefs[i].bar == -1 {
                        placedRefs[i].bar = closingIndex
                    }
                    closeBar()
                }
            }
            // The last piece of a note carries the source event's real onward-tie.
            if !event.isRest, let last = placedRefs.last {
                if last.bar == -1 { bar[last.idx].tiedToNext = event.tiedToNext }
                else { bars[last.bar][last.idx].tiedToNext = event.tiedToNext }
            }
        }
        if !bar.isEmpty || bars.isEmpty { closeBar() }
        return bars
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
