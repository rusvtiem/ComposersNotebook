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

    init(
        events: [NoteEvent] = [],
        timeSignature: TimeSignature? = nil,
        keySignature: KeySignature? = nil,
        clefChange: Clef? = nil,
        tempoMarking: TempoMarking? = nil,
        barlineEnd: BarlineType = .regular,
        navigationMark: NavigationMark? = nil,
        hairpins: [Hairpin] = [],
        volta: Volta? = nil
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
    }

    /// Total beats used in this measure
    var usedBeats: Double {
        events.reduce(0) { $0 + $1.duration.beats }
    }

    /// Check if measure is full (no more room for notes)
    func isFull(timeSignature ts: TimeSignature) -> Bool {
        return usedBeats >= ts.totalBeats
    }

    /// Remaining beats in measure
    func remainingBeats(timeSignature ts: TimeSignature) -> Double {
        return max(0, ts.totalBeats - usedBeats)
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
