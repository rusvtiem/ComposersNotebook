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

    init(actualCount: Int, normalCount: Int, groupID: UUID = UUID(), positionInGroup: Int = 0) {
        self.actualCount = actualCount
        self.normalCount = normalCount
        self.groupID = groupID
        self.positionInGroup = positionInGroup
    }

    /// Множитель длительности (например, 2/3 для триоли = 0.666...).
    var durationMultiplier: Double {
        guard actualCount > 0 else { return 1.0 }
        return Double(normalCount) / Double(actualCount)
    }

    /// Отображаемая надпись (3, 5, 6, 7:8, и т.д.).
    /// Для классических соотношений (3:2, 5:4) показываем только actual.
    /// Для нестандартных (7:8, 11:8) — пара.
    var displayLabel: String {
        let isClassic = (actualCount == 3 && normalCount == 2) ||
                        (actualCount == 5 && normalCount == 4) ||
                        (actualCount == 6 && normalCount == 4) ||
                        (actualCount == 7 && normalCount == 4) ||
                        (actualCount == 9 && normalCount == 8)
        if isClassic {
            return "\(actualCount)"
        }
        return "\(actualCount):\(normalCount)"
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
