import Foundation

// MARK: - Tuplet (триоли, квинтоли, септоли и т.д.)
//
// Группа нот, играющая на месте другого количества нот той же длительности.
// Классическая триоль 3:2 — три восьмых на месте двух восьмых.
// Квинтоль 5:4, септоль 7:4 или 7:8, секстоль 6:4 и т.д.
//
// Все ноты одной группы должны иметь одинаковый `groupID`.
// `Duration.beats` под tuplet'ом вычисляется через множитель
// `normalCount / actualCount`.

/// Показ скобки над группой (MuseScore Tuplet Properties → Bracket).
/// `nil`/`.auto` = как решит движок гравировки (скобка на небитованных, без — на
/// битованных). `.shown`/`.hidden` — принудительно.
enum TupletBracket: String, Codable, Hashable {
    case auto, shown, hidden
}

/// Что печатать над группой (MuseScore Tuplet Properties → Number).
/// `nil`/`.count` = только actual (3, 5). `.ratio` = пара actual:normal (3:2).
/// `.noNumber` = ничего. Кейс НЕ называем `none`: в контексте `TupletNumberStyle?`
/// литерал `.none` резолвится в `Optional.none` (nil), а не в кейс enum — молчаливая
/// ловушка, из-за которой любой вызов `numberStyle: .none` терял выбор пользователя.
enum TupletNumberStyle: String, Codable, Hashable {
    case count, ratio, noNumber
}

struct Tuplet: Codable, Equatable, Hashable {
    /// Количество нот в фактическом исполнении (3 для триоли, 5 для квинтоли).
    var actualCount: Int

    /// На месте скольких "нормальных" нот того же значения (2 для триоли, 4 для квинтоли).
    var normalCount: Int

    /// Общий идентификатор группы — для всех нот одной триоли/квинтоли совпадает.
    var groupID: UUID

    /// Позиция этой ноты в группе (0..<actualCount). Нужно для рендеринга
    /// (рисовать скобку только над первой/последней, цифру над средней).
    var positionInGroup: Int

    /// Стиль скобки. Опционально — старые .cnb без ключа декодируются как nil (= auto),
    /// поэтому синтезированный Decodable не падает на файлах до этого поля.
    var bracket: TupletBracket?

    /// Стиль числа над группой. Опционально по той же причине совместимости.
    var numberStyle: TupletNumberStyle?

    init(actualCount: Int, normalCount: Int, groupID: UUID = UUID(), positionInGroup: Int = 0,
         bracket: TupletBracket? = nil, numberStyle: TupletNumberStyle? = nil) {
        self.actualCount = actualCount
        self.normalCount = normalCount
        self.groupID = groupID
        self.positionInGroup = positionInGroup
        self.bracket = bracket
        self.numberStyle = numberStyle
    }

    /// Множитель длительности (например, 2/3 для триоли = 0.666...).
    var durationMultiplier: Double {
        guard actualCount > 0 else { return 1.0 }
        return Double(normalCount) / Double(actualCount)
    }

    /// Отображаемая надпись (3, 5, 6, 7:8, и т.д.).
    /// Явный `numberStyle` побеждает автоматику: `.noNumber` → пусто, `.ratio` → пара,
    /// `.count` → только actual. При nil (наследие) — авто: классические соотношения
    /// (3:2, 5:4) показывают только actual, нестандартные (7:8, 11:8) — пару.
    var displayLabel: String {
        switch numberStyle {
        case .some(.noNumber): return ""
        case .some(.ratio): return "\(actualCount):\(normalCount)"
        case .some(.count): return "\(actualCount)"
        case .none:  // no explicit style — auto
            let isClassic = (actualCount == 3 && normalCount == 2) ||
                            (actualCount == 5 && normalCount == 4) ||
                            (actualCount == 6 && normalCount == 4) ||
                            (actualCount == 7 && normalCount == 4) ||
                            (actualCount == 9 && normalCount == 8)
            return isClassic ? "\(actualCount)" : "\(actualCount):\(normalCount)"
        }
    }

    /// MusicXML `bracket` attribute value for `<tuplet>`, or nil to omit (auto —
    /// let Verovio's default engraving rule decide).
    var musicXMLBracketAttr: String? {
        switch bracket {
        case .shown: return "yes"
        case .hidden: return "no"
        case .auto, nil: return nil
        }
    }

    /// MusicXML `show-number` attribute value for `<tuplet>`, or nil to omit.
    /// count → "actual", ratio → "both", none → "none".
    var musicXMLShowNumberAttr: String? {
        switch numberStyle {
        case .some(.count): return "actual"
        case .some(.ratio): return "both"
        case .some(.noNumber): return "none"
        case .none: return nil
        }
    }

    var isFirstInGroup: Bool { positionInGroup == 0 }
    var isLastInGroup: Bool { positionInGroup == actualCount - 1 }
}

// MARK: - Common factory helpers

extension Tuplet {
    /// Триоль 3:2 — три ноты на месте двух того же значения.
    static func triplet(groupID: UUID = UUID(), positionInGroup: Int = 0) -> Tuplet {
        Tuplet(actualCount: 3, normalCount: 2, groupID: groupID, positionInGroup: positionInGroup)
    }

    /// Квинтоль 5:4.
    static func quintuplet(groupID: UUID = UUID(), positionInGroup: Int = 0) -> Tuplet {
        Tuplet(actualCount: 5, normalCount: 4, groupID: groupID, positionInGroup: positionInGroup)
    }

    /// Секстоль 6:4.
    static func sextuplet(groupID: UUID = UUID(), positionInGroup: Int = 0) -> Tuplet {
        Tuplet(actualCount: 6, normalCount: 4, groupID: groupID, positionInGroup: positionInGroup)
    }

    /// Септоль 7:4 (классическая) или 7:8 (по выбору).
    static func septuplet(over normalCount: Int = 4, groupID: UUID = UUID(), positionInGroup: Int = 0) -> Tuplet {
        Tuplet(actualCount: 7, normalCount: normalCount, groupID: groupID, positionInGroup: positionInGroup)
    }

    /// Девять-в-восьми (9:8).
    static func nonuplet(groupID: UUID = UUID(), positionInGroup: Int = 0) -> Tuplet {
        Tuplet(actualCount: 9, normalCount: 8, groupID: groupID, positionInGroup: positionInGroup)
    }
}

// MARK: - Group construction helpers

extension Tuplet {
    /// Создать массив `Tuplet`'ов для группы из `actualCount` нот с общим groupID.
    /// Использовать так:
    /// ```
    /// let trips = Tuplet.makeGroup(actualCount: 3, normalCount: 2)
    /// for (i, t) in trips.enumerated() { events[i].tuplet = t }
    /// ```
    static func makeGroup(actualCount: Int, normalCount: Int) -> [Tuplet] {
        let id = UUID()
        return (0..<actualCount).map { idx in
            Tuplet(actualCount: actualCount, normalCount: normalCount, groupID: id, positionInGroup: idx)
        }
    }
}
