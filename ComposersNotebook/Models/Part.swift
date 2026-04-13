import Foundation

// MARK: - Staff (один нотный стан)

struct Staff: Codable, Equatable, Identifiable {
    let id: UUID
    var clef: Clef
    var measures: [Measure]

    init(clef: Clef, measures: [Measure] = []) {
        self.id = UUID()
        self.clef = clef
        self.measures = measures.isEmpty ? [.wholeRest()] : measures
    }

    mutating func appendEmptyMeasure() {
        measures.append(.wholeRest())
    }

    mutating func insertMeasure(_ measure: Measure, at index: Int) {
        let safeIndex = min(index, measures.count)
        measures.insert(measure, at: safeIndex)
    }

    mutating func removeMeasure(at index: Int) {
        guard measures.count > 1, index < measures.count else { return }
        measures.remove(at: index)
    }
}

// MARK: - Part (Партия одного инструмента)

struct Part: Codable, Equatable, Identifiable {
    let id: UUID
    var instrument: Instrument
    var staves: [Staff]
    var voiceType: VoiceType

    var effectiveMidiProgram: Int {
        instrument.effectiveMidiProgram(for: voiceType)
    }

    enum CodingKeys: String, CodingKey {
        case id, instrument, staves, voiceType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        instrument = try c.decode(Instrument.self, forKey: .instrument)
        staves = try c.decode([Staff].self, forKey: .staves)
        voiceType = try c.decodeIfPresent(VoiceType.self, forKey: .voiceType) ?? .section
    }

    init(instrument: Instrument, measures: [Measure] = [], voiceType: VoiceType = .section) {
        self.id = UUID()
        self.instrument = instrument
        self.voiceType = voiceType

        // Create staves based on instrument (1 or 2)
        var staffList: [Staff] = []
        for i in 0..<instrument.staves {
            let clef = i < instrument.clefs.count ? instrument.clefs[i] : instrument.defaultClef
            staffList.append(Staff(clef: clef, measures: measures.isEmpty ? [.wholeRest()] : measures))
        }
        self.staves = staffList
    }

    // MARK: - Convenience accessors (backwards compatible, operate on first staff)

    /// Primary staff measures (treble for grand staff)
    var measures: [Measure] {
        get { staves.first?.measures ?? [] }
        set {
            guard !staves.isEmpty else { return }
            staves[0].measures = newValue
        }
    }

    /// Current clef of primary staff
    var clef: Clef {
        get { staves.first?.clef ?? instrument.defaultClef }
        set {
            guard !staves.isEmpty else { return }
            staves[0].clef = newValue
        }
    }

    /// Whether this part has a grand staff (2 staves)
    var isGrandStaff: Bool { staves.count >= 2 }

    /// Total number of measures (same across all staves)
    var measureCount: Int { staves.first?.measures.count ?? 0 }

    // MARK: - Operations (apply to ALL staves)

    mutating func appendEmptyMeasure() {
        for i in staves.indices {
            staves[i].appendEmptyMeasure()
        }
    }

    mutating func insertMeasure(_ measure: Measure, at index: Int) {
        for i in staves.indices {
            staves[i].insertMeasure(measure, at: index)
        }
    }

    mutating func removeMeasure(at index: Int) {
        for i in staves.indices {
            staves[i].removeMeasure(at: index)
        }
    }
}
