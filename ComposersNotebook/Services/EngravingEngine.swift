import Foundation

struct EngravingEngine {

    // Логарифмический горизонтальный spacing (см. measureContentWidth).
    // spacingRefBeats — «кратчайшая» опорная длительность (шестнадцатая, 0.25 доли);
    // её ширина = spacingBase; каждое удвоение длительности добавляет spacingIncrement.
    // Подобрано так, что типичный такт из 4 четвертей ≈ 160·zoom (как в прежней линейной
    // модели), но целая больше не в 8 раз шире восьмой.
    static let spacingRefBeats: Double = 0.25
    static let spacingBase: CGFloat = 16
    static let spacingIncrement: CGFloat = 12

    struct SystemLayout {
        let measureRanges: [Range<Int>]
        let measureWidths: [CGFloat]
    }

    static func computeLayout(
        measures: [Measure],
        availableWidth: CGFloat,
        baseSpacing: CGFloat,
        zoomScale: CGFloat,
        timeSignature: TimeSignature,
        isFirstSystem: Bool = true
    ) -> SystemLayout {
        let widths = measures.enumerated().map { idx, m in
            measureContentWidth(m, index: idx, baseSpacing: baseSpacing, zoomScale: zoomScale, timeSignature: timeSignature, isFirstSystem: isFirstSystem)
        }

        var systems: [Range<Int>] = []
        var lineStart = 0
        var lineWidth: CGFloat = 0
        let minMeasuresPerSystem = 1

        for i in 0..<measures.count {
            let w = widths[i]
            if lineWidth + w > availableWidth && i - lineStart >= minMeasuresPerSystem {
                systems.append(lineStart..<i)
                lineStart = i
                lineWidth = w
            } else {
                lineWidth += w
            }
        }
        if lineStart < measures.count {
            systems.append(lineStart..<measures.count)
        }

        return SystemLayout(measureRanges: systems, measureWidths: widths)
    }

    static func measureContentWidth(
        _ measure: Measure,
        index: Int,
        baseSpacing: CGFloat,
        zoomScale: CGFloat,
        timeSignature: TimeSignature,
        isFirstSystem: Bool
    ) -> CGFloat {
        let z = zoomScale

        // Multi-measure rest: фиксированная ширина блока, не зависит от нот.
        if measure.multiMeasureRestCount > 0 {
            return 90 * z
        }

        var width: CGFloat = 16 * z

        if index == 0 && isFirstSystem {
            width += 45 * z
        }

        if measure.timeSignature != nil || (index == 0 && isFirstSystem) {
            width += 20 * z
        }

        // Дополнительное место под repeat barline / Volta bracket / Rehearsal mark
        switch measure.barlineEnd {
        case .repeatEnd, .repeatBoth:
            width += 12 * z
        case .double, .final_:
            width += 6 * z
        case .repeatStart:
            width += 12 * z
        case .regular:
            break
        }
        if measure.volta != nil {
            width += 8 * z
        }
        if measure.rehearsalMark != nil {
            width += 12 * z   // не отнимаем место у нот, но даём раздуть систему
        }

        let hasAccidentals = measure.events.contains { event in
            switch event.type {
            case .note(let p): return p.accidental != .natural
            case .chord(let ps): return ps.contains { $0.accidental != .natural }
            case .rest: return false
            }
        }

        var noteSpace = eventIdealWidths(events: measure.events, zoomScale: z, hasAccidentals: hasAccidentals).reduce(0, +)

        if measure.events.isEmpty {
            noteSpace = 40 * z
        }

        width += noteSpace
        return width
    }

    /// Идеальная ширина каждого события в такте — ЕДИНЫЙ источник ширины для расчёта
    /// ширины такта, hit-test и рендера. Раньше эти три пути считали spacing по-разному
    /// (ширина такта — по actualBeats, позиции нот — линейно по duration.beats), из-за чего
    /// в триолях нотоглавы, зоны тапа и спаннеры разъезжались (E-3/M-3). Теперь один расчёт.
    ///
    /// Логарифмическая модель (LilyPond springs-and-rods / Gould «Behind Bars»): ширина ∝
    /// log2 длительности, не линейно — иначе целая была бы в 8 раз шире восьмой. Anchor —
    /// шестнадцатая (spacingRefBeats): её ширина = spacingBase, каждое удвоение длительности
    /// добавляет spacingIncrement. actualBeats (не duration.beats), чтобы триоль занимала
    /// место по фактическому времени звучания. Возвращает абсолютные ширины; вызывающий
    /// код при необходимости масштабирует их под доступную ширину такта одним коэффициентом.
    static func eventIdealWidths(
        events: [NoteEvent],
        zoomScale z: CGFloat,
        hasAccidentals: Bool
    ) -> [CGFloat] {
        let minNoteWidth = 18 * z
        let accPad: CGFloat = hasAccidentals ? 10 * z : 0
        return events.map { event in
            let doublings = log2(max(event.actualBeats, spacingRefBeats) / spacingRefBeats)
            let proportional = spacingBase * z + CGFloat(doublings) * spacingIncrement * z
            let tupletBonus: CGFloat = event.tuplet != nil ? 4 * z : 0
            let chordBonus: CGFloat = event.chordSymbol != nil ? 6 * z : 0
            return max(proportional + tupletBonus + chordBonus, minNoteWidth + accPad)
        }
    }

    // MARK: - Accidental Collision Avoidance

    struct AccidentalSlot {
        let pitchY: CGFloat
        var xOffset: CGFloat
    }

    static func resolveAccidentalCollisions(
        pitches: [(pitch: Pitch, y: CGFloat)],
        baseX: CGFloat,
        spacing: CGFloat
    ) -> [AccidentalSlot] {
        let accidentalPitches = pitches.filter { $0.pitch.accidental != .natural }
        guard !accidentalPitches.isEmpty else { return [] }

        var slots: [AccidentalSlot] = []
        let minVerticalGap = spacing * 0.8

        for ap in accidentalPitches.sorted(by: { $0.y < $1.y }) {
            var offset = baseX - spacing * 1.5
            for existing in slots {
                if abs(existing.pitchY - ap.y) < minVerticalGap && abs(existing.xOffset - offset) < spacing {
                    offset -= spacing
                }
            }
            slots.append(AccidentalSlot(pitchY: ap.y, xOffset: offset))
        }

        return slots
    }
}
