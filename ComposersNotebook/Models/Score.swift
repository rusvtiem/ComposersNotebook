import Foundation

// MARK: - Score (Партитура)

struct Score: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var composer: String
    var parts: [Part]
    var tempo: TempoMarking
    var timeSignature: TimeSignature
    var keySignature: KeySignature
    var createdAt: Date
    var modifiedAt: Date

    init(
        title: String = "Без названия",
        composer: String = "",
        parts: [Part] = [],
        tempo: TempoMarking = TempoMarking(bpm: 120, name: "Allegro"),
        timeSignature: TimeSignature = .fourFour,
        keySignature: KeySignature = .cMajor
    ) {
        self.id = UUID()
        self.title = title
        self.composer = composer
        self.parts = parts
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Add a new instrument part
    mutating func addPart(instrument: Instrument) {
        var part = Part(instrument: instrument)
        // Ensure the new part has the same number of measures as existing parts
        let targetCount = parts.first?.measureCount ?? 1
        while part.measures.count < targetCount {
            part.appendEmptyMeasure()
        }
        parts.append(part)
        touch()
    }

    /// Remove a part by index
    mutating func removePart(at index: Int) {
        guard index < parts.count else { return }
        parts.remove(at: index)
        touch()
    }

    /// Add an empty measure to all parts
    mutating func appendMeasure() {
        for i in parts.indices {
            parts[i].appendEmptyMeasure()
        }
        touch()
    }

    /// Insert a measure at a specific index in all parts
    mutating func insertMeasure(at index: Int) {
        for i in parts.indices {
            parts[i].insertMeasure(.wholeRest(), at: index)
        }
        touch()
    }

    /// Remove a measure at index from all parts
    mutating func removeMeasure(at index: Int) {
        for i in parts.indices {
            parts[i].removeMeasure(at: index)
        }
        touch()
    }

    /// Total number of measures (based on first part, all parts should be equal)
    var measureCount: Int {
        parts.first?.measureCount ?? 0
    }

    /// Update modification timestamp
    mutating func touch() {
        modifiedAt = Date()
    }

    /// Sort parts by orchestral order
    mutating func sortPartsByOrchestralOrder() {
        parts.sort { a, b in
            if a.instrument.group.scoreOrder != b.instrument.group.scoreOrder {
                return a.instrument.group.scoreOrder < b.instrument.group.scoreOrder
            }
            return a.instrument.midiProgram < b.instrument.midiProgram
        }
    }

    // MARK: - Quick constructors

    /// Piano solo score
    static func pianoSolo(title: String = "Без названия") -> Score {
        Score(
            title: title,
            parts: [Part(instrument: .piano)]
        )
    }

    /// Empty score with given instruments
    static func withInstruments(_ instruments: [Instrument], title: String = "Без названия") -> Score {
        var score = Score(title: title)
        for instrument in instruments {
            score.addPart(instrument: instrument)
        }
        score.sortPartsByOrchestralOrder()
        return score
    }
}
