import Foundation

// MARK: - Part (Партия одного инструмента)

struct Part: Codable, Equatable, Identifiable {
    let id: UUID
    var instrument: Instrument
    var measures: [Measure]
    var clef: Clef              // текущий ключ (может меняться в мерах)

    init(instrument: Instrument, measures: [Measure] = []) {
        self.id = UUID()
        self.instrument = instrument
        self.measures = measures.isEmpty ? [.wholeRest()] : measures
        self.clef = instrument.defaultClef
    }

    /// Add an empty measure at the end
    mutating func appendEmptyMeasure() {
        measures.append(.wholeRest())
    }

    /// Insert a measure at a specific index
    mutating func insertMeasure(_ measure: Measure, at index: Int) {
        let safeIndex = min(index, measures.count)
        measures.insert(measure, at: safeIndex)
    }

    /// Remove a measure at a specific index
    mutating func removeMeasure(at index: Int) {
        guard measures.count > 1, index < measures.count else { return }
        measures.remove(at: index)
    }

    /// Total number of measures
    var measureCount: Int { measures.count }
}
