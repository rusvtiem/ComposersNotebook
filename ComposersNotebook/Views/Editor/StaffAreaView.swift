import SwiftUI

// MARK: - Note Hit Info

struct NoteHitInfo {
    let x: CGFloat
    let y: CGFloat
    let eventIndex: Int
}

// MARK: - Staff Area (all visible measures)

struct StaffAreaView: View {
    @ObservedObject var viewModel: ScoreViewModel

    private let staffLineSpacing: CGFloat = 10
    private let measureWidth: CGFloat = 200
    private let staffHeight: CGFloat = 60  // 4 spaces × 10 + some padding
    private let partSpacing: CGFloat = 80
    private let noteHitRadius: CGFloat = 14  // tap detection radius

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
                    let isCurrentMeasure = partIndex == viewModel.selectedPartIndex
                        && measureIndex == viewModel.selectedMeasureIndex

                    MeasureView(
                        measure: measure,
                        measureIndex: measureIndex,
                        isSelected: isCurrentMeasure,
                        selectedEventIndex: isCurrentMeasure ? viewModel.selectedEventIndex : nil,
                        timeSignature: effectiveTimeSignature(partIndex: partIndex, measureIndex: measureIndex),
                        clef: effectiveClef(partIndex: partIndex, measureIndex: measureIndex),
                        staffLineSpacing: staffLineSpacing
                    )
                    .frame(width: measureWidth, height: staffHeight + 40)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                viewModel.selectPart(at: partIndex)
                                viewModel.selectedMeasureIndex = measureIndex

                                let clef = effectiveClef(partIndex: partIndex, measureIndex: measureIndex)
                                let ts = effectiveTimeSignature(partIndex: partIndex, measureIndex: measureIndex)
                                let positions = computeNotePositions(
                                    measure: measure, measureIndex: measureIndex,
                                    clef: clef, timeSignature: ts
                                )

                                // Check if tap is on an existing note
                                if let hitIndex = hitTestNote(at: value.location, positions: positions) {
                                    if viewModel.selectedEventIndex == hitIndex {
                                        viewModel.deselectEvent()
                                    } else {
                                        viewModel.selectEvent(at: hitIndex)
                                    }
                                    return
                                }

                                // No note hit — deselect and optionally add note
                                viewModel.deselectEvent()
                                if viewModel.inputMode == .note {
                                    if let pitch = pitchFromTap(y: value.location.y, clef: clef) {
                                        viewModel.addNote(pitch: pitch)
                                    }
                                } else {
                                    viewModel.cursorPosition = 0
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .sequenced(before: DragGesture())
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    guard let drag = drag,
                                          isCurrentMeasure,
                                          viewModel.selectedEventIndex != nil else { return }
                                    let clef = effectiveClef(partIndex: partIndex, measureIndex: measureIndex)
                                    if let pitch = pitchFromTap(y: drag.location.y, clef: clef) {
                                        viewModel.updateSelectedEventPitch(pitch)
                                    }
                                default: break
                                }
                            }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                isCurrentMeasure ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                }
            }

            Spacer().frame(height: partSpacing - staffHeight)
        }
    }

    // MARK: - Note Hit Testing

    private func computeNotePositions(measure: Measure, measureIndex: Int, clef: Clef, timeSignature: TimeSignature) -> [NoteHitInfo] {
        let startX: CGFloat = 8
        let staffTop: CGFloat = 20
        let noteStartX: CGFloat = measureIndex == 0 ? startX + 45 : startX + 15
        let availableWidth = measureWidth - noteStartX - 10
        let totalBeats = measure.usedBeats
        guard totalBeats > 0 else { return [] }

        var positions: [NoteHitInfo] = []
        var currentX = noteStartX

        for (eventIndex, event) in measure.events.enumerated() {
            let eventWidth = availableWidth * CGFloat(event.duration.beats / max(totalBeats, timeSignature.totalBeats))
            let noteX = currentX + eventWidth / 2

            switch event.type {
            case .note(let pitch):
                let y = MeasureView.noteYStatic(pitch: pitch, staffTop: staffTop, staffLineSpacing: staffLineSpacing, clef: clef)
                positions.append(NoteHitInfo(x: noteX, y: y, eventIndex: eventIndex))
            case .chord(let pitches):
                if let firstPitch = pitches.first {
                    let y = MeasureView.noteYStatic(pitch: firstPitch, staffTop: staffTop, staffLineSpacing: staffLineSpacing, clef: clef)
                    positions.append(NoteHitInfo(x: noteX, y: y, eventIndex: eventIndex))
                }
            case .rest:
                let y = staffTop + 2 * staffLineSpacing
                positions.append(NoteHitInfo(x: noteX, y: y, eventIndex: eventIndex))
            }

            currentX += eventWidth
        }

        return positions
    }

    private func hitTestNote(at point: CGPoint, positions: [NoteHitInfo]) -> Int? {
        var closest: (index: Int, distance: CGFloat)?
        for pos in positions {
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < noteHitRadius {
                if closest == nil || dist < closest!.distance {
                    closest = (pos.eventIndex, dist)
                }
            }
        }
        return closest?.index
    }

    // MARK: - Tap to place note

    private func pitchFromTap(y: CGFloat, clef: Clef) -> Pitch? {
        let staffTop: CGFloat = 20
        let halfSpace = staffLineSpacing / 2

        // Calculate staff position offset from middle line
        let middleLineY = staffTop + 2 * staffLineSpacing
        let offset = Int(round((middleLineY - y) / halfSpace))

        // Map offset to pitch based on clef
        let referencePitch: Pitch
        switch clef {
        case .treble: referencePitch = Pitch(name: .B, octave: 4)
        case .bass: referencePitch = Pitch(name: .D, octave: 3)
        case .alto: referencePitch = Pitch(name: .C, octave: 4)
        case .tenor: referencePitch = Pitch(name: .A, octave: 3)
        }

        // Step through diatonic scale from reference
        let noteNames: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
        let refIndex = noteNames.firstIndex(of: referencePitch.name)!
        var noteIndex = refIndex + offset
        var octave = referencePitch.octave

        while noteIndex >= 7 {
            noteIndex -= 7
            octave += 1
        }
        while noteIndex < 0 {
            noteIndex += 7
            octave -= 1
        }

        guard octave >= 0, octave <= 8 else { return nil }
        return Pitch(name: noteNames[noteIndex], octave: octave, accidental: viewModel.selectedAccidental ?? .natural)
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
    let selectedEventIndex: Int?
    let timeSignature: TimeSignature
    let clef: Clef
    let staffLineSpacing: CGFloat

    /// Static helper so StaffAreaView can compute positions without a MeasureView instance
    static func noteYStatic(pitch: Pitch, staffTop: CGFloat, staffLineSpacing: CGFloat, clef: Clef) -> CGFloat {
        let middleLinePosition: Int
        switch clef {
        case .treble: middleLinePosition = Pitch(name: .B, octave: 4).staffPosition
        case .bass: middleLinePosition = Pitch(name: .D, octave: 3).staffPosition
        case .alto: middleLinePosition = Pitch(name: .C, octave: 4).staffPosition
        case .tenor: middleLinePosition = Pitch(name: .A, octave: 3).staffPosition
        }
        let offset = middleLinePosition - pitch.staffPosition
        return staffTop + 2 * staffLineSpacing + CGFloat(offset) * (staffLineSpacing / 2)
    }

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

            // First pass: collect note positions and draw notes
            struct NotePosition {
                let x: CGFloat
                let y: CGFloat
                let eventIndex: Int
            }
            var notePositions: [NotePosition] = []
            var currentX = noteStartX

            for (eventIndex, event) in measure.events.enumerated() {
                let eventWidth = availableWidth * CGFloat(event.duration.beats / max(totalBeats, timeSignature.totalBeats))

                switch event.type {
                case .note(let pitch):
                    let y = noteY(pitch: pitch, staffTop: staffTop)
                    let noteX = currentX + eventWidth / 2
                    let stemUp = resolveStemDirection(event.stemDirection, noteY: y, staffTop: staffTop)
                    let isEventSelected = selectedEventIndex == eventIndex
                    if isEventSelected {
                        drawSelectionHighlight(context: context, x: noteX, y: y)
                    }
                    drawNoteHead(context: context, x: noteX, y: y, duration: event.duration.value, stemUp: stemUp, selected: isEventSelected)
                    drawLedgerLines(context: context, pitch: pitch, x: noteX, staffTop: staffTop)
                    drawAccidental(context: context, pitch: pitch, x: noteX, y: y, showNatural: event.showNatural)
                    notePositions.append(NotePosition(x: noteX, y: y, eventIndex: eventIndex))
                    if !event.articulations.isEmpty {
                        drawArticulation(context: context, symbol: event.articulations.first!.displaySymbol, x: noteX, y: y, stemUp: stemUp, duration: event.duration.value)
                    }

                case .chord(let pitches):
                    let topPitch = pitches.min(by: { noteY(pitch: $0, staffTop: staffTop) < noteY(pitch: $1, staffTop: staffTop) })
                    let chordY = topPitch.map { noteY(pitch: $0, staffTop: staffTop) } ?? staffTop + 2 * staffLineSpacing
                    let stemUp = resolveStemDirection(event.stemDirection, noteY: chordY, staffTop: staffTop)
                    let isEventSelected = selectedEventIndex == eventIndex
                    for pitch in pitches {
                        let y = noteY(pitch: pitch, staffTop: staffTop)
                        let noteX = currentX + eventWidth / 2
                        if isEventSelected {
                            drawSelectionHighlight(context: context, x: noteX, y: y)
                        }
                        drawNoteHead(context: context, x: noteX, y: y, duration: event.duration.value, stemUp: stemUp, selected: isEventSelected)
                        drawLedgerLines(context: context, pitch: pitch, x: noteX, staffTop: staffTop)
                        drawAccidental(context: context, pitch: pitch, x: noteX, y: y, showNatural: event.showNatural)
                    }
                    if let tp = topPitch {
                        let y = noteY(pitch: tp, staffTop: staffTop)
                        notePositions.append(NotePosition(x: currentX + eventWidth / 2, y: y, eventIndex: eventIndex))
                    }

                case .rest:
                    let restX = currentX + eventWidth / 2
                    let restY = staffTop + 2 * staffLineSpacing
                    if selectedEventIndex == eventIndex {
                        drawSelectionHighlight(context: context, x: restX, y: restY)
                    }
                    let restText = Text(restSymbol(for: event.duration.value))
                        .font(.system(size: 18))
                    context.draw(restText, at: CGPoint(x: restX, y: restY))
                    notePositions.append(NotePosition(x: restX, y: restY, eventIndex: eventIndex))
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

            // Second pass: draw ties and slurs as Bézier curves
            for (i, event) in measure.events.enumerated() {
                if event.tiedToNext || event.slurStart {
                    // Find this note's position and next note's position
                    guard let fromPos = notePositions.first(where: { $0.eventIndex == i }),
                          let toPos = notePositions.first(where: { $0.eventIndex == i + 1 }) else { continue }

                    let curveDir: CGFloat = fromPos.y >= staffTop + 2 * staffLineSpacing ? -1 : 1
                    let curveHeight: CGFloat = staffLineSpacing * 1.5

                    var curve = Path()
                    curve.move(to: CGPoint(x: fromPos.x + 4, y: fromPos.y + curveDir * 4))
                    curve.addQuadCurve(
                        to: CGPoint(x: toPos.x - 4, y: toPos.y + curveDir * 4),
                        control: CGPoint(
                            x: (fromPos.x + toPos.x) / 2,
                            y: min(fromPos.y, toPos.y) + curveDir * curveHeight
                        )
                    )
                    let lineWidth: CGFloat = event.tiedToNext ? 1.5 : 1.0
                    context.stroke(curve, with: .color(.primary), lineWidth: lineWidth)
                }
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

    private func drawSelectionHighlight(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        let highlightRadius: CGFloat = staffLineSpacing * 0.9
        let rect = CGRect(x: x - highlightRadius, y: y - highlightRadius, width: highlightRadius * 2, height: highlightRadius * 2)
        let circle = Path(ellipseIn: rect)
        context.fill(circle, with: .color(.blue.opacity(0.2)))
        context.stroke(circle, with: .color(.blue.opacity(0.6)), lineWidth: 1.5)
    }

    private func drawNoteHead(context: GraphicsContext, x: CGFloat, y: CGFloat, duration: DurationValue, stemUp: Bool = true, selected: Bool = false) {
        let radius: CGFloat = staffLineSpacing / 2 - 1
        let rect = CGRect(x: x - radius, y: y - radius * 0.75, width: radius * 2, height: radius * 1.5)
        let ellipse = Path(ellipseIn: rect)
        let noteColor: Color = selected ? .blue : .primary

        switch duration {
        case .whole:
            context.stroke(ellipse, with: .color(noteColor), lineWidth: 1.5)
        case .half:
            context.stroke(ellipse, with: .color(noteColor), lineWidth: 1.5)
            drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor)
        default:
            context.fill(ellipse, with: .color(noteColor))
            drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor)
            drawFlags(context: context, x: x, y: y, radius: radius, stemUp: stemUp, duration: duration)
        }
    }

    private func resolveStemDirection(_ direction: StemDirection, noteY: CGFloat, staffTop: CGFloat) -> Bool {
        switch direction {
        case .auto: return noteY >= staffTop + staffLineSpacing * 2
        case .up: return true
        case .down: return false
        }
    }

    private func drawStem(context: GraphicsContext, x: CGFloat, y: CGFloat, radius: CGFloat, stemUp: Bool, color: Color = .primary) {
        var stem = Path()
        let stemLength = staffLineSpacing * 3.5
        let stemX = stemUp ? x + radius : x - radius
        stem.move(to: CGPoint(x: stemX, y: y))
        stem.addLine(to: CGPoint(x: stemX, y: stemUp ? y - stemLength : y + stemLength))
        context.stroke(stem, with: .color(color), lineWidth: 1)
    }

    private func drawFlags(context: GraphicsContext, x: CGFloat, y: CGFloat, radius: CGFloat, stemUp: Bool, duration: DurationValue) {
        let flagCount: Int
        switch duration {
        case .eighth: flagCount = 1
        case .sixteenth: flagCount = 2
        case .thirtySecond: flagCount = 3
        default: return
        }

        let stemLength = staffLineSpacing * 3.5
        let stemX = stemUp ? x + radius : x - radius
        let stemEnd = stemUp ? y - stemLength : y + stemLength
        let flagLength: CGFloat = staffLineSpacing * 1.5
        let flagSpacing: CGFloat = staffLineSpacing * 0.8

        for i in 0..<flagCount {
            let flagY = stemEnd + (stemUp ? CGFloat(i) * flagSpacing : -CGFloat(i) * flagSpacing)
            var flag = Path()
            flag.move(to: CGPoint(x: stemX, y: flagY))
            let curveDir: CGFloat = stemUp ? 1 : -1
            flag.addQuadCurve(
                to: CGPoint(x: stemX + flagLength * curveDir, y: flagY + flagLength * 0.6 * (stemUp ? 1 : -1)),
                control: CGPoint(x: stemX + flagLength * 0.6 * curveDir, y: flagY)
            )
            context.stroke(flag, with: .color(.primary), lineWidth: 1.2)
        }
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

    private func drawAccidental(context: GraphicsContext, pitch: Pitch, x: CGFloat, y: CGFloat, showNatural: Bool = false) {
        if pitch.accidental == .natural && !showNatural { return }
        let symbol = pitch.accidental.displaySymbol
        let accText = Text(symbol).font(.system(size: 12, weight: .bold))
        let radius: CGFloat = staffLineSpacing / 2 - 1
        context.draw(accText, at: CGPoint(x: x - radius * 2 - 6, y: y))
    }

    private func drawArticulation(context: GraphicsContext, symbol: String, x: CGFloat, y: CGFloat, stemUp: Bool, duration: DurationValue) {
        let artOffset: CGFloat = staffLineSpacing * 0.8
        let artY: CGFloat
        if duration == .whole {
            // No stem — place above
            artY = y - artOffset
        } else if stemUp {
            // Stem goes up — articulation below the note head
            artY = y + artOffset
        } else {
            // Stem goes down — articulation above the note head
            artY = y - artOffset
        }
        let artText = Text(symbol).font(.system(size: 10))
        context.draw(artText, at: CGPoint(x: x, y: artY))
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
