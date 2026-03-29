import SwiftUI

// MARK: - Staff Area (all visible measures)

struct StaffAreaView: View {
    @ObservedObject var viewModel: ScoreViewModel

    private let staffLineSpacing: CGFloat = 10
    private let measureWidth: CGFloat = 200
    private let staffHeight: CGFloat = 60  // 4 spaces × 10 + some padding
    private let partSpacing: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.score.parts.enumerated()), id: \.offset) { partIndex, part in
                partRow(part: part, partIndex: partIndex)
            }
        }
    }

    // MARK: - Part Row

    private func partRow(part: Part, partIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Instrument name
            Text(part.instrument.shortName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(part.measures.enumerated()), id: \.offset) { measureIndex, measure in
                    MeasureView(
                        measure: measure,
                        measureIndex: measureIndex,
                        isSelected: partIndex == viewModel.selectedPartIndex
                            && measureIndex == viewModel.selectedMeasureIndex,
                        timeSignature: effectiveTimeSignature(partIndex: partIndex, measureIndex: measureIndex),
                        clef: effectiveClef(partIndex: partIndex, measureIndex: measureIndex),
                        staffLineSpacing: staffLineSpacing
                    )
                    .frame(width: measureWidth, height: staffHeight + 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectPart(at: partIndex)
                        viewModel.selectedMeasureIndex = measureIndex
                        viewModel.cursorPosition = 0
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                partIndex == viewModel.selectedPartIndex
                                    && measureIndex == viewModel.selectedMeasureIndex
                                    ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                }
            }

            Spacer().frame(height: partSpacing - staffHeight)
        }
    }

    private func effectiveTimeSignature(partIndex: Int, measureIndex: Int) -> TimeSignature {
        let part = viewModel.score.parts[partIndex]
        for i in stride(from: measureIndex, through: 0, by: -1) {
            if let ts = part.measures[i].timeSignature {
                return ts
            }
        }
        return viewModel.score.timeSignature
    }

    private func effectiveClef(partIndex: Int, measureIndex: Int) -> Clef {
        let part = viewModel.score.parts[partIndex]
        for i in stride(from: measureIndex, through: 0, by: -1) {
            if let clef = part.measures[i].clefChange {
                return clef
            }
        }
        return part.instrument.defaultClef
    }
}

// MARK: - Single Measure View

struct MeasureView: View {
    let measure: Measure
    let measureIndex: Int
    let isSelected: Bool
    let timeSignature: TimeSignature
    let clef: Clef
    let staffLineSpacing: CGFloat

    var body: some View {
        Canvas { context, size in
            let startX: CGFloat = 8
            let staffTop: CGFloat = 20

            // Draw 5 staff lines
            for line in 0..<5 {
                let y = staffTop + CGFloat(line) * staffLineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.primary.opacity(0.4)), lineWidth: 0.5)
            }

            // Draw barline at end
            var barline = Path()
            let barlineX = size.width - 1
            barline.move(to: CGPoint(x: barlineX, y: staffTop))
            barline.addLine(to: CGPoint(x: barlineX, y: staffTop + 4 * staffLineSpacing))
            context.stroke(barline, with: .color(.primary.opacity(0.6)), lineWidth: 1)

            // Draw clef symbol at start of first measure
            if measureIndex == 0 {
                let clefText = Text(clef.symbol).font(.system(size: 28))
                context.draw(clefText, at: CGPoint(x: startX + 10, y: staffTop + 2 * staffLineSpacing))
            }

            // Draw time signature at start of first measure
            if measureIndex == 0 || measure.timeSignature != nil {
                let tsX: CGFloat = measureIndex == 0 ? startX + 30 : startX + 5
                let topNum = Text("\(timeSignature.beats)").font(.system(size: 14, weight: .bold))
                let botNum = Text("\(timeSignature.beatValue)").font(.system(size: 14, weight: .bold))
                context.draw(topNum, at: CGPoint(x: tsX, y: staffTop + staffLineSpacing))
                context.draw(botNum, at: CGPoint(x: tsX, y: staffTop + 3 * staffLineSpacing))
            }

            // Draw notes
            let noteStartX: CGFloat = measureIndex == 0 ? startX + 45 : startX + 15
            let availableWidth = size.width - noteStartX - 10
            let totalBeats = measure.usedBeats
            guard totalBeats > 0 else { return }

            var currentX = noteStartX
            for event in measure.events {
                let eventWidth = availableWidth * CGFloat(event.duration.beats / max(totalBeats, timeSignature.totalBeats))

                switch event.type {
                case .note(let pitch):
                    let y = noteY(pitch: pitch, staffTop: staffTop)
                    drawNoteHead(context: context, x: currentX + eventWidth / 2, y: y, duration: event.duration.value)
                    drawLedgerLines(context: context, pitch: pitch, x: currentX + eventWidth / 2, staffTop: staffTop)
                    if !event.articulations.isEmpty {
                        let artText = Text(event.articulations.first!.displaySymbol)
                            .font(.system(size: 10))
                        context.draw(artText, at: CGPoint(x: currentX + eventWidth / 2, y: y - 15))
                    }

                case .chord(let pitches):
                    for pitch in pitches {
                        let y = noteY(pitch: pitch, staffTop: staffTop)
                        drawNoteHead(context: context, x: currentX + eventWidth / 2, y: y, duration: event.duration.value)
                        drawLedgerLines(context: context, pitch: pitch, x: currentX + eventWidth / 2, staffTop: staffTop)
                    }

                case .rest:
                    let restText = Text(restSymbol(for: event.duration.value))
                        .font(.system(size: 18))
                    context.draw(restText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 2 * staffLineSpacing))
                }

                // Tie mark
                if event.tiedToNext {
                    let tieText = Text("⁀").font(.system(size: 14))
                    let y: CGFloat = event.isRest ? staffTop + 2 * staffLineSpacing : staffTop
                    context.draw(tieText, at: CGPoint(x: currentX + eventWidth, y: y - 5))
                }

                // Dynamic marking
                if let dynamic = event.dynamic {
                    let dynText = Text(dynamic.displayName)
                        .font(.system(size: 9, design: .serif))
                        .italic()
                    context.draw(dynText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 5 * staffLineSpacing + 5))
                }

                currentX += eventWidth
            }

            // Tempo marking
            if let tempo = measure.tempoMarking {
                let tempoText = Text(tempo.displayString).font(.system(size: 9))
                context.draw(tempoText, at: CGPoint(x: noteStartX, y: staffTop - 10))
            }

            // Navigation mark
            if let nav = measure.navigationMark {
                let navText = Text(nav.displayString).font(.system(size: 10, weight: .bold))
                context.draw(navText, at: CGPoint(x: size.width / 2, y: staffTop - 10))
            }

            // Repeat barlines
            if measure.barlineEnd == .repeatEnd || measure.barlineEnd == .repeatBoth {
                let dotY1 = staffTop + 1.5 * staffLineSpacing
                let dotY2 = staffTop + 2.5 * staffLineSpacing
                let dot = Path(ellipseIn: CGRect(x: barlineX - 8, y: dotY1 - 2, width: 4, height: 4))
                let dot2 = Path(ellipseIn: CGRect(x: barlineX - 8, y: dotY2 - 2, width: 4, height: 4))
                context.fill(dot, with: .color(.primary))
                context.fill(dot2, with: .color(.primary))
            }
        }
    }

    // MARK: - Note rendering helpers

    private func noteY(pitch: Pitch, staffTop: CGFloat) -> CGFloat {
        // Map pitch to staff position relative to clef
        let middleLinePosition: Int
        switch clef {
        case .treble: middleLinePosition = Pitch(name: .B, octave: 4).staffPosition
        case .bass: middleLinePosition = Pitch(name: .D, octave: 3).staffPosition
        case .alto: middleLinePosition = Pitch(name: .C, octave: 4).staffPosition
        case .tenor: middleLinePosition = Pitch(name: .A, octave: 3).staffPosition
        }

        let staffPos = pitch.staffPosition
        let offset = middleLinePosition - staffPos
        return staffTop + 2 * staffLineSpacing + CGFloat(offset) * (staffLineSpacing / 2)
    }

    private func drawNoteHead(context: GraphicsContext, x: CGFloat, y: CGFloat, duration: DurationValue) {
        let radius: CGFloat = staffLineSpacing / 2 - 1
        let rect = CGRect(x: x - radius, y: y - radius * 0.75, width: radius * 2, height: radius * 1.5)
        let ellipse = Path(ellipseIn: rect)

        switch duration {
        case .whole:
            context.stroke(ellipse, with: .color(.primary), lineWidth: 1.5)
        case .half:
            context.stroke(ellipse, with: .color(.primary), lineWidth: 1.5)
            // Stem
            drawStem(context: context, x: x + radius, y: y)
        default:
            context.fill(ellipse, with: .color(.primary))
            // Stem
            drawStem(context: context, x: x + radius, y: y)
        }
    }

    private func drawStem(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        var stem = Path()
        stem.move(to: CGPoint(x: x, y: y))
        stem.addLine(to: CGPoint(x: x, y: y - staffLineSpacing * 3))
        context.stroke(stem, with: .color(.primary), lineWidth: 1)
    }

    private func drawLedgerLines(context: GraphicsContext, pitch: Pitch, x: CGFloat, staffTop: CGFloat) {
        let y = noteY(pitch: pitch, staffTop: staffTop)
        let topLine = staffTop
        let bottomLine = staffTop + 4 * staffLineSpacing
        let width: CGFloat = staffLineSpacing * 1.5

        // Above staff
        if y < topLine {
            var lineY = topLine - staffLineSpacing
            while lineY >= y - staffLineSpacing / 4 {
                var path = Path()
                path.move(to: CGPoint(x: x - width / 2, y: lineY))
                path.addLine(to: CGPoint(x: x + width / 2, y: lineY))
                context.stroke(path, with: .color(.primary.opacity(0.6)), lineWidth: 0.5)
                lineY -= staffLineSpacing
            }
        }

        // Below staff
        if y > bottomLine {
            var lineY = bottomLine + staffLineSpacing
            while lineY <= y + staffLineSpacing / 4 {
                var path = Path()
                path.move(to: CGPoint(x: x - width / 2, y: lineY))
                path.addLine(to: CGPoint(x: x + width / 2, y: lineY))
                context.stroke(path, with: .color(.primary.opacity(0.6)), lineWidth: 0.5)
                lineY += staffLineSpacing
            }
        }
    }

    private func restSymbol(for duration: DurationValue) -> String {
        // Using simple text since iOS doesn't render musical Unicode rest symbols
        switch duration {
        case .whole: return "■"
        case .half: return "▬"
        case .quarter: return "𝄾"
        case .eighth: return "♩̸"
        case .sixteenth: return "≋"
        case .thirtySecond: return "≋≋"
        }
    }
}
