import Foundation

struct EngravingEngine {

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
        var width: CGFloat = 16 * z

        if index == 0 && isFirstSystem {
            width += 45 * z
        }

        if measure.timeSignature != nil || (index == 0 && isFirstSystem) {
            width += 20 * z
        }

        let noteCount = max(measure.events.count, 1)
        let totalBeats = max(measure.usedBeats, timeSignature.totalBeats)

        let hasAccidentals = measure.events.contains { event in
            switch event.type {
            case .note(let p): return p.accidental != .natural
            case .chord(let ps): return ps.contains { $0.accidental != .natural }
            case .rest: return false
            }
        }

        var noteSpace: CGFloat = 0
        let minNoteWidth = 18 * z
        let accPad: CGFloat = hasAccidentals ? 10 * z : 0

        for event in measure.events {
            let proportional = CGFloat(event.duration.beats / totalBeats) * 160 * z
            noteSpace += max(proportional, minNoteWidth + accPad)
        }

        if measure.events.isEmpty {
            noteSpace = 40 * z
        }

        width += noteSpace
        return width
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

    // MARK: - Duration-Proportional Spacing

    static func proportionalWidths(
        events: [NoteEvent],
        availableWidth: CGFloat,
        minWidth: CGFloat,
        timeSignature: TimeSignature
    ) -> [CGFloat] {
        guard !events.isEmpty else { return [] }

        let totalBeats = max(events.reduce(0.0) { $0 + $1.duration.beats }, timeSignature.totalBeats)

        var widths: [CGFloat] = events.map { event in
            let ratio = CGFloat(event.duration.beats / totalBeats)
            let logScaled = CGFloat(log2(event.duration.beats + 1) / log2(totalBeats + 1))
            let blended = ratio * 0.6 + logScaled * 0.4
            return max(blended * availableWidth, minWidth)
        }

        let total = widths.reduce(0, +)
        if total > availableWidth {
            let scale = availableWidth / total
            widths = widths.map { $0 * scale }
        }

        return widths
    }
}
