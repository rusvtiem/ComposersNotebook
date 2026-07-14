import Foundation

// MARK: - Note Duration

enum DurationValue: Int, Codable, CaseIterable {
    // rawValue для целых и дробных нот — делитель целой (beats = 4/rawValue).
    // Для нот ДЛИННЕЕ целой (бревис = 2 целые, лонга = 4 целые) делитель не
    // выражается целым числом, поэтому им даны отрицательные rawValue-множители
    // (−2 = ×2 целой, −4 = ×4 целой), а `beats` считается через switch, а не
    // формулой. Порядок объявления = порядок кнопок в тулбаре (ForEach allCases):
    // от самых длинных к самым коротким, как в палитре длительностей MuseScore.
    case longa = -4         // лонга (4 целые, 16 долей)
    case breve = -2         // бревис / двойная целая (2 целые, 8 долей)
    case whole = 1          // целая
    case half = 2           // половинная
    case quarter = 4        // четвертная
    case eighth = 8         // восьмая
    case sixteenth = 16     // шестнадцатая
    case thirtySecond = 32  // тридцать вторая
    case sixtyFourth = 64   // шестьдесят четвёртая
    case oneHundredTwentyEighth = 128   // сто двадцать восьмая
    case twoHundredFiftySixth = 256     // двести пятьдесят шестая
    case fiveHundredTwelfth = 512       // пятьсот двенадцатая
    case oneThousandTwentyFourth = 1024 // тысяча двадцать четвёртая (предел MusicXML/MuseScore)

    var displayName: String {
        switch self {
        case .longa: return "Лонга"
        case .breve: return "Бревис"
        case .whole: return "Целая"
        case .half: return "Половинная"
        case .quarter: return "Четвертная"
        case .eighth: return "Восьмая"
        case .sixteenth: return "Шестнадцатая"
        case .thirtySecond: return "Тридцать вторая"
        case .sixtyFourth: return "Шестьдесят четвёртая"
        case .oneHundredTwentyEighth: return "Сто двадцать восьмая"
        case .twoHundredFiftySixth: return "Двести пятьдесят шестая"
        case .fiveHundredTwelfth: return "Пятьсот двенадцатая"
        case .oneThousandTwentyFourth: return "Тысяча двадцать четвёртая"
        }
    }

    var symbol: String {
        switch self {
        case .longa: return "𝆷"
        case .breve: return "𝅜"
        case .whole: return "1"
        case .half: return "½"
        case .quarter: return "¼"
        case .eighth: return "⅛"
        case .sixteenth: return "¹⁄₁₆"
        case .thirtySecond: return "¹⁄₃₂"
        case .sixtyFourth: return "¹⁄₆₄"
        case .oneHundredTwentyEighth: return "¹⁄₁₂₈"
        case .twoHundredFiftySixth: return "¹⁄₂₅₆"
        case .fiveHundredTwelfth: return "¹⁄₅₁₂"
        case .oneThousandTwentyFourth: return "¹⁄₁₀₂₄"
        }
    }

    /// Duration in beats (quarter note = 1.0)
    var beats: Double {
        switch self {
        case .longa: return 16.0
        case .breve: return 8.0
        default: return 4.0 / Double(rawValue)
        }
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
    ///
    /// doubleDotted проверяется раньше dotted: импортёры (Capella, MusicXML)
    /// для двойной точки выставляют ОБА флага (dotted=true, doubleDotted=true).
    /// При обратном порядке двойная точка ошибочно звучала как ×1.5 вместо ×1.75.
    var beats: Double {
        var result = value.beats
        if doubleDotted {
            result *= 1.75
        } else if dotted {
            result *= 1.5
        }
        if triplet {
            result *= 2.0 / 3.0
        }
        return result
    }

    /// Доли без учёта триольного флага (точки учитываются).
    /// Нужно чтобы явный `Tuplet` на событии не умножался повторно на 2/3:
    /// при выставленных ОБОИХ (legacy `triplet` + `NoteEvent.tuplet`) наивный
    /// `beats * multiplier` давал ×4/9 вместо ×2/3.
    var beatsIgnoringTriplet: Double {
        var result = value.beats
        if doubleDotted {
            result *= 1.75
        } else if dotted {
            result *= 1.5
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
