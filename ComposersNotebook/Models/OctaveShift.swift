import Foundation

// MARK: - Octave Shift (8va / 8vb / 15ma / 15mb)
//
// Графический знак октавного переноса — нота записана в одной октаве,
// но звучит на октаву / две октавы выше или ниже.
// Spanner живёт на уровне Measure (как Hairpin) — диапазон долей.

enum OctaveShiftKind: String, Codable, Equatable, Hashable {
    case ottavaAlta         // 8va  — на октаву выше
    case ottavaBassa        // 8vb  — на октаву ниже
    case quindicesimaAlta   // 15ma — на две октавы выше
    case quindicesimaBassa  // 15mb — на две октавы ниже

    var symbol: String {
        switch self {
        case .ottavaAlta: return "8va"
        case .ottavaBassa: return "8vb"
        case .quindicesimaAlta: return "15ma"
        case .quindicesimaBassa: return "15mb"
        }
    }

    /// Полутоны, добавляемые к midiNote при плейбеке.
    var semitones: Int {
        switch self {
        case .ottavaAlta: return 12
        case .ottavaBassa: return -12
        case .quindicesimaAlta: return 24
        case .quindicesimaBassa: return -24
        }
    }
}

struct OctaveShift: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: OctaveShiftKind
    var startBeat: Double
    var endBeat: Double

    init(kind: OctaveShiftKind, startBeat: Double, endBeat: Double) {
        self.id = UUID()
        self.kind = kind
        self.startBeat = startBeat
        self.endBeat = endBeat
    }
}
