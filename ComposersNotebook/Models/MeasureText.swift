import Foundation

// MARK: - Rehearsal Mark (буквенный/числовой маркер)
//
// Прямоугольный маркер над тактом, помогающий быстро находить место
// в партитуре во время репетиции. Стандарт — буквы A, B, C... или
// номера тактов в больших произведениях.

struct RehearsalMark: Codable, Equatable, Hashable {
    enum Style: String, Codable, Hashable {
        case boxed       // буква/цифра в прямоугольной рамке (стандарт)
        case bold        // жирный текст без рамки
        case plain       // обычный текст
    }

    var text: String      // "A", "B", "1", "Coda" — любая короткая строка
    var style: Style

    init(text: String, style: Style = .boxed) {
        self.text = text
        self.style = style
    }
}

// MARK: - Expression Text (espressivo, dolce, agitato)
//
// Текст над нотами обозначающий настроение / технику исполнения —
// от классического espressivo до современных pointillistic, espressivo.
// Отличается от dynamic тем что не привязан к velocity напрямую.

struct ExpressionText: Codable, Equatable, Hashable {
    var text: String              // "espressivo", "dolce", "agitato"
    var italianTerm: Bool         // курсивом (как принято для итальянской терминологии)
    var attachToBeat: Double      // позиция в долях такта (0 = начало)

    init(text: String, italianTerm: Bool = true, attachToBeat: Double = 0) {
        self.text = text
        self.italianTerm = italianTerm
        self.attachToBeat = attachToBeat
    }

    /// Список самых распространённых выражений — для UI picker'а в Слое 2.
    static let commonExpressions: [String] = [
        "espressivo",
        "dolce",
        "agitato",
        "cantabile",
        "leggiero",
        "marcato",
        "maestoso",
        "scherzando",
        "tranquillo",
        "appassionato",
        "con fuoco",
        "con brio",
        "grazioso",
        "lacrimoso",
        "misterioso",
        "pesante",
        "risoluto",
        "vivace",
    ]
}

// MARK: - Tempo Change (accel, rit, gradual changes)
//
// В отличие от TempoMarking (мгновенная установка темпа на такт),
// TempoChange — это **постепенное** изменение через диапазон тактов.
// Reverse mapping: для плейбека — линейная интерполяция от startBPM к endBPM.

struct TempoChange: Codable, Equatable, Hashable {

    enum Kind: String, Codable, Hashable {
        case accelerando   // ускорение (accel.)
        case ritardando    // замедление (rit.)
        case rallentando   // замедление (rall.) — аналог rit
        case stringendo    // ускорение со сжатием (string.)
        case allargando    // расширение (allarg.)

        var symbol: String {
            switch self {
            case .accelerando: return "accel."
            case .ritardando: return "rit."
            case .rallentando: return "rall."
            case .stringendo: return "string."
            case .allargando: return "allarg."
            }
        }

        var italianName: String {
            switch self {
            case .accelerando: return "accelerando"
            case .ritardando: return "ritardando"
            case .rallentando: return "rallentando"
            case .stringendo: return "stringendo"
            case .allargando: return "allargando"
            }
        }

        /// Направление изменения: -1 замедление, +1 ускорение.
        var direction: Int {
            switch self {
            case .accelerando, .stringendo: return 1
            case .ritardando, .rallentando, .allargando: return -1
            }
        }
    }

    var kind: Kind
    var startBeat: Double      // глобальная позиция (в долях от начала пьесы)
    var endBeat: Double
    var startBPM: Double?      // если nil — взять текущий BPM на startBeat
    var endBPM: Double         // целевой BPM

    init(kind: Kind, startBeat: Double, endBeat: Double, startBPM: Double? = nil, endBPM: Double) {
        self.kind = kind
        self.startBeat = startBeat
        self.endBeat = endBeat
        self.startBPM = startBPM
        self.endBPM = endBPM
    }

    /// Линейная интерполяция BPM для произвольной точки в диапазоне.
    func interpolatedBPM(at beat: Double, defaultStartBPM: Double) -> Double {
        let from = startBPM ?? defaultStartBPM
        guard endBeat > startBeat else { return endBPM }
        let t = (beat - startBeat) / (endBeat - startBeat)
        let clamped = max(0, min(1, t))
        return from + (endBPM - from) * clamped
    }
}
