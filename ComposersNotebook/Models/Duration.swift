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
    /// Количество точек увеличения (0…4). Источник истины для точек — MuseScore/
    /// MusicXML держат до 4 (¼.. = ×1.9375). Булевы `dotted`/`doubleDotted` —
    /// вычисляемые обёртки поверх этого поля для обратной совместимости.
    var dots: Int
    var triplet: Bool         // триоль (x2/3 длительности)

    /// Точка (≥1). get/set совместимы со старым кодом: set true → минимум 1 точка,
    /// set false → 0 точек.
    var dotted: Bool {
        get { dots >= 1 }
        set { dots = newValue ? max(dots, 1) : 0 }
    }
    /// Двойная точка (≥2). set true → ровно 2, set false → срезать до 1.
    var doubleDotted: Bool {
        get { dots >= 2 }
        set { dots = newValue ? 2 : min(dots, 1) }
    }

    init(value: DurationValue, dots: Int, triplet: Bool = false) {
        self.value = value
        self.dots = min(max(dots, 0), 4)
        self.triplet = triplet
    }

    init(value: DurationValue, dotted: Bool = false, doubleDotted: Bool = false, triplet: Bool = false) {
        self.value = value
        self.dots = doubleDotted ? 2 : (dotted ? 1 : 0)
        self.triplet = triplet
    }

    /// Множитель длительности для n точек: ×(2 − 2^(−n)).
    /// 0 → 1, 1 → 1.5, 2 → 1.75, 3 → 1.875, 4 → 1.9375.
    static func dotMultiplier(_ dots: Int) -> Double {
        guard dots > 0 else { return 1.0 }
        return 2.0 - pow(2.0, Double(-dots))
    }

    /// Actual duration in beats (quarter note = 1.0)
    var beats: Double {
        var result = value.beats * Duration.dotMultiplier(dots)
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
        value.beats * Duration.dotMultiplier(dots)
    }

    // Хранится `dots: Int`; читаем и старые документы (bool-флаги `dotted`/
    // `doubleDotted`), и пишем оба представления для forward-совместимости.
    enum CodingKeys: String, CodingKey {
        case value, dots, dotted, doubleDotted, triplet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(DurationValue.self, forKey: .value)
        triplet = try c.decodeIfPresent(Bool.self, forKey: .triplet) ?? false
        if let storedDots = try c.decodeIfPresent(Int.self, forKey: .dots) {
            dots = min(max(storedDots, 0), 4)
        } else {
            let legacyDouble = try c.decodeIfPresent(Bool.self, forKey: .doubleDotted) ?? false
            let legacySingle = try c.decodeIfPresent(Bool.self, forKey: .dotted) ?? false
            dots = legacyDouble ? 2 : (legacySingle ? 1 : 0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(dots, forKey: .dots)
        try c.encode(triplet, forKey: .triplet)
        try c.encode(dots >= 1, forKey: .dotted)
        try c.encode(dots >= 2, forKey: .doubleDotted)
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
