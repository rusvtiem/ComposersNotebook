import Foundation

// MARK: - Note Duration

enum DurationValue: Int, Codable, CaseIterable {
    case whole = 1          // целая
    case half = 2           // половинная
    case quarter = 4        // четвертная
    case eighth = 8         // восьмая
    case sixteenth = 16     // шестнадцатая
    case thirtySecond = 32  // тридцать вторая

    var displayName: String {
        switch self {
        case .whole: return "Целая"
        case .half: return "Половинная"
        case .quarter: return "Четвертная"
        case .eighth: return "Восьмая"
        case .sixteenth: return "Шестнадцатая"
        case .thirtySecond: return "Тридцать вторая"
        }
    }

    var symbol: String {
        switch self {
        case .whole: return "1"
        case .half: return "½"
        case .quarter: return "¼"
        case .eighth: return "⅛"
        case .sixteenth: return "¹⁄₁₆"
        case .thirtySecond: return "¹⁄₃₂"
        }
    }

    /// Duration in beats (quarter note = 1.0)
    var beats: Double {
        return 4.0 / Double(rawValue)
    }
}

// MARK: - Duration with modifiers

struct Duration: Codable, Equatable {
    var value: DurationValue
    var dotted: Bool          // точка (x1.5 длительности)
    var doubleDotted: Bool    // двойная точка (x1.75 длительности)
    var triplet: Bool         // триоль (x2/3 длительности)

    init(value: DurationValue, dotted: Bool = false, doubleDotted: Bool = false, triplet: Bool = false) {
        self.value = value
        self.dotted = dotted
        self.doubleDotted = doubleDotted
        self.triplet = triplet
    }

    /// Actual duration in beats (quarter note = 1.0)
    var beats: Double {
        var result = value.beats
        if dotted {
            result *= 1.5
        } else if doubleDotted {
            result *= 1.75
        }
        if triplet {
            result *= 2.0 / 3.0
        }
        return result
    }

    /// Duration in seconds at given BPM
    func seconds(atBPM bpm: Double) -> Double {
        return beats * (60.0 / bpm)
    }

    static let quarterNote = Duration(value: .quarter)
    static let halfNote = Duration(value: .half)
    static let wholeNote = Duration(value: .whole)
    static let eighthNote = Duration(value: .eighth)
    static let sixteenthNote = Duration(value: .sixteenth)
}
