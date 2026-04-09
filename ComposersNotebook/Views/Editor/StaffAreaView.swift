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
    @EnvironmentObject var themeManager: ThemeManager

    private var theme: AppTheme { themeManager.currentTheme }

    // Base sizes at 1.0x zoom
    private let baseStaffLineSpacing: CGFloat = 10
    private let baseMeasureWidth: CGFloat = 200
    private let basePartSpacing: CGFloat = 80

    // Computed sizes based on zoom
    private var staffLineSpacing: CGFloat { baseStaffLineSpacing * viewModel.zoomScale }
    private var measureWidth: CGFloat { baseMeasureWidth * viewModel.zoomScale }
    private var staffHeight: CGFloat { staffLineSpacing * 4 + 20 }
    private var partSpacing: CGFloat { basePartSpacing * viewModel.zoomScale }
    private var noteHitRadius: CGFloat { 14 * viewModel.zoomScale }

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
                .foregroundStyle(theme.textSecondary)

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
                        keySignature: effectiveKeySignature(partIndex: partIndex, measureIndex: measureIndex),
                        clef: effectiveClef(partIndex: partIndex, measureIndex: measureIndex),
                        staffLineSpacing: staffLineSpacing,
                        zoomScale: viewModel.zoomScale,
                        theme: theme
                    )
                    .frame(width: measureWidth, height: staffHeight + 40 * viewModel.zoomScale)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let wasDifferentMeasure = viewModel.selectedMeasureIndex != measureIndex
                                    || viewModel.selectedPartIndex != partIndex
                                viewModel.selectPart(at: partIndex)
                                viewModel.selectedMeasureIndex = measureIndex
                                // Reset cursor when switching to a different measure
                                if wasDifferentMeasure {
                                    viewModel.cursorPosition = currentMeasureBeats(measure: measure, ts: effectiveTimeSignature(partIndex: partIndex, measureIndex: measureIndex))
                                }

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

                                // No note hit
                                viewModel.deselectEvent()

                                switch viewModel.inputMode {
                                case .note:
                                    if let pitch = pitchFromTap(y: value.location.y, clef: clef) {
                                        viewModel.addNote(pitch: pitch)
                                    }
                                case .rest:
                                    viewModel.addRest()
                                case .navigate:
                                    // Just select the measure, no insertion
                                    viewModel.cursorPosition = 0
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .sequenced(before: DragGesture(minimumDistance: 0))
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
                                isCurrentMeasure ? theme.accent : Color.clear,
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
        let z = viewModel.zoomScale
        let startX: CGFloat = 8 * z
        let staffTop: CGFloat = 20 * z
        let noteStartX: CGFloat = measureIndex == 0 ? startX + 45 * z : startX + 15 * z
        let availableWidth = measureWidth - noteStartX - 10 * z
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
        let staffTop: CGFloat = 20 * viewModel.zoomScale
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

    /// Total beats currently used in the measure
    private func currentMeasureBeats(measure: Measure, ts: TimeSignature) -> Double {
        measure.usedBeats
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

    private func effectiveKeySignature(partIndex: Int, measureIndex: Int) -> KeySignature {
        let part = viewModel.score.parts[partIndex]
        for i in stride(from: measureIndex, through: 0, by: -1) {
            if let ks = part.measures[i].keySignature {
                return ks
            }
        }
        return viewModel.score.keySignature
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
    let keySignature: KeySignature
    let clef: Clef
    let staffLineSpacing: CGFloat
    var zoomScale: CGFloat = 1.0
    var theme: AppTheme = .dark

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

    private func scaled(_ value: CGFloat) -> CGFloat { value * zoomScale }

    var body: some View {
        Canvas { context, size in
            let startX: CGFloat = scaled(8)
            let staffTop: CGFloat = scaled(20)

            // Draw 5 staff lines
            for line in 0..<5 {
                let y = staffTop + CGFloat(line) * staffLineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(theme.staffLine.opacity(theme.staffLineOpacity)), lineWidth: 0.5)
            }

            // Draw barline at end
            var barline = Path()
            let barlineX = size.width - 1
            barline.move(to: CGPoint(x: barlineX, y: staffTop))
            barline.addLine(to: CGPoint(x: barlineX, y: staffTop + 4 * staffLineSpacing))
            context.stroke(barline, with: .color(theme.barline.opacity(0.6)), lineWidth: 1)

            // Draw clef symbol at start of first measure
            if measureIndex == 0 {
                let clefText = Text(clef.symbol).font(.system(size: scaled(28)))
                context.draw(clefText, at: CGPoint(x: startX + scaled(10), y: staffTop + 2 * staffLineSpacing))
            }

            // Draw time signature at start of first measure
            var headerEndX: CGFloat = measureIndex == 0 ? startX + scaled(25) : startX
            if measureIndex == 0 || measure.timeSignature != nil {
                let tsX: CGFloat = headerEndX + scaled(8)
                let topNum = Text("\(timeSignature.beats)").font(.system(size: scaled(14), weight: .bold))
                let botNum = Text("\(timeSignature.beatValue)").font(.system(size: scaled(14), weight: .bold))
                context.draw(topNum, at: CGPoint(x: tsX, y: staffTop + staffLineSpacing))
                context.draw(botNum, at: CGPoint(x: tsX, y: staffTop + 3 * staffLineSpacing))
                headerEndX = tsX + scaled(10)
            }

            // Draw key signature accidentals
            if keySignature.fifths != 0 && (measureIndex == 0 || measure.keySignature != nil) {
                let ksX = headerEndX + scaled(4)
                headerEndX = drawKeySignature(context: context, fifths: keySignature.fifths, x: ksX, staffTop: staffTop)
            }

            // Draw notes
            let noteStartX: CGFloat = headerEndX + scaled(8)
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
            var beamCandidates: [MeasureView.BeamCandidate] = []
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
                    let isBeamable = event.duration.value == .eighth || event.duration.value == .sixteenth || event.duration.value == .thirtySecond
                    drawNoteHead(context: context, x: noteX, y: y, duration: event.duration.value, stemUp: stemUp, selected: isEventSelected, skipFlags: isBeamable)
                    drawLedgerLines(context: context, pitch: pitch, x: noteX, staffTop: staffTop)
                    drawAccidental(context: context, pitch: pitch, x: noteX, y: y, showNatural: event.showNatural)
                    notePositions.append(NotePosition(x: noteX, y: y, eventIndex: eventIndex))
                    if isBeamable {
                        beamCandidates.append(BeamCandidate(x: noteX, y: y, stemUp: stemUp, duration: event.duration.value, eventIndex: eventIndex))
                    }
                    for (artIdx, articulation) in event.articulations.enumerated() {
                        drawArticulation(context: context, symbol: articulation.displaySymbol, x: noteX, y: y, stemUp: stemUp, duration: event.duration.value, stackIndex: artIdx)
                    }

                case .chord(let pitches):
                    let topPitch = pitches.min(by: { noteY(pitch: $0, staffTop: staffTop) < noteY(pitch: $1, staffTop: staffTop) })
                    let chordY = topPitch.map { noteY(pitch: $0, staffTop: staffTop) } ?? staffTop + 2 * staffLineSpacing
                    let stemUp = resolveStemDirection(event.stemDirection, noteY: chordY, staffTop: staffTop)
                    let isEventSelected = selectedEventIndex == eventIndex
                    let isBeamable = event.duration.value == .eighth || event.duration.value == .sixteenth || event.duration.value == .thirtySecond
                    for pitch in pitches {
                        let y = noteY(pitch: pitch, staffTop: staffTop)
                        let noteX = currentX + eventWidth / 2
                        if isEventSelected {
                            drawSelectionHighlight(context: context, x: noteX, y: y)
                        }
                        drawNoteHead(context: context, x: noteX, y: y, duration: event.duration.value, stemUp: stemUp, selected: isEventSelected, skipFlags: isBeamable)
                        drawLedgerLines(context: context, pitch: pitch, x: noteX, staffTop: staffTop)
                        drawAccidental(context: context, pitch: pitch, x: noteX, y: y, showNatural: event.showNatural)
                    }
                    if let tp = topPitch {
                        let y = noteY(pitch: tp, staffTop: staffTop)
                        let noteX = currentX + eventWidth / 2
                        notePositions.append(NotePosition(x: noteX, y: y, eventIndex: eventIndex))
                        if isBeamable {
                            beamCandidates.append(BeamCandidate(x: noteX, y: y, stemUp: stemUp, duration: event.duration.value, eventIndex: eventIndex))
                        }
                    }

                case .rest:
                    let restX = currentX + eventWidth / 2
                    let restY = staffTop + 2 * staffLineSpacing
                    if selectedEventIndex == eventIndex {
                        drawSelectionHighlight(context: context, x: restX, y: restY)
                    }
                    let restText = Text(restSymbol(for: event.duration.value))
                        .font(.system(size: scaled(18)))
                    context.draw(restText, at: CGPoint(x: restX, y: restY))
                    notePositions.append(NotePosition(x: restX, y: restY, eventIndex: eventIndex))
                }

                // Dynamic marking
                if let dynamic = event.dynamic {
                    let dynText = Text(dynamic.displayName)
                        .font(.system(size: scaled(9), design: .serif))
                        .italic()
                    context.draw(dynText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 5 * staffLineSpacing + scaled(5)))
                }

                currentX += eventWidth
            }

            // Draw ghost rests for remaining beats in the measure
            let remainingBeats = timeSignature.totalBeats - measure.usedBeats
            if remainingBeats > 0.01 && !measure.events.isEmpty {
                let remainingWidth = availableWidth * CGFloat(remainingBeats / max(totalBeats, timeSignature.totalBeats))
                let ghostX = currentX + remainingWidth / 2
                let restY = staffTop + 2 * staffLineSpacing
                let ghostSymbol = restSymbolForBeats(remainingBeats)
                let ghostText = Text(ghostSymbol)
                    .font(.system(size: scaled(16)))
                    .foregroundColor(theme.textSecondary.opacity(0.4))
                context.draw(ghostText, at: CGPoint(x: ghostX, y: restY))
            }

            // Draw beams for grouped eighth/sixteenth notes
            drawBeams(context: context, candidates: beamCandidates, staffTop: staffTop)

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
                    context.stroke(curve, with: .color(theme.noteHead), lineWidth: lineWidth)
                }
            }

            // Tempo marking
            if let tempo = measure.tempoMarking {
                let tempoText = Text(tempo.displayString).font(.system(size: scaled(9)))
                context.draw(tempoText, at: CGPoint(x: noteStartX, y: staffTop - scaled(10)))
            }

            // Navigation mark
            if let nav = measure.navigationMark {
                let navText = Text(nav.displayString).font(.system(size: scaled(10), weight: .bold))
                context.draw(navText, at: CGPoint(x: size.width / 2, y: staffTop - scaled(10)))
            }

            // Repeat barlines
            if measure.barlineEnd == .repeatEnd || measure.barlineEnd == .repeatBoth {
                let dotY1 = staffTop + 1.5 * staffLineSpacing
                let dotY2 = staffTop + 2.5 * staffLineSpacing
                let dotSize = scaled(4)
                let dot = Path(ellipseIn: CGRect(x: barlineX - dotSize * 2, y: dotY1 - dotSize / 2, width: dotSize, height: dotSize))
                let dot2 = Path(ellipseIn: CGRect(x: barlineX - dotSize * 2, y: dotY2 - dotSize / 2, width: dotSize, height: dotSize))
                context.fill(dot, with: .color(theme.noteHead))
                context.fill(dot2, with: .color(theme.noteHead))
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
        context.fill(circle, with: .color(theme.selectedNote.opacity(0.2)))
        context.stroke(circle, with: .color(theme.selectedNote.opacity(0.6)), lineWidth: 1.5)
    }

    private func drawNoteHead(context: GraphicsContext, x: CGFloat, y: CGFloat, duration: DurationValue, stemUp: Bool = true, selected: Bool = false, skipFlags: Bool = false) {
        let radius: CGFloat = staffLineSpacing / 2 - 1
        let rect = CGRect(x: x - radius, y: y - radius * 0.75, width: radius * 2, height: radius * 1.5)
        let ellipse = Path(ellipseIn: rect)
        let noteColor: Color = selected ? theme.selectedNote : theme.noteHead

        switch duration {
        case .whole:
            context.stroke(ellipse, with: .color(noteColor), lineWidth: 1.5)
        case .half:
            context.stroke(ellipse, with: .color(noteColor), lineWidth: 1.5)
            drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor)
        default:
            context.fill(ellipse, with: .color(noteColor))
            drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor)
            if !skipFlags {
                drawFlags(context: context, x: x, y: y, radius: radius, stemUp: stemUp, duration: duration)
            }
        }
    }

    private func resolveStemDirection(_ direction: StemDirection, noteY: CGFloat, staffTop: CGFloat) -> Bool {
        switch direction {
        case .auto: return noteY >= staffTop + staffLineSpacing * 2
        case .up: return true
        case .down: return false
        }
    }

    private func drawStem(context: GraphicsContext, x: CGFloat, y: CGFloat, radius: CGFloat, stemUp: Bool, color: Color? = nil) {
        let stemColor = color ?? theme.noteHead
        var stem = Path()
        let stemLength = staffLineSpacing * 3.5
        let stemX = stemUp ? x + radius : x - radius
        stem.move(to: CGPoint(x: stemX, y: y))
        stem.addLine(to: CGPoint(x: stemX, y: stemUp ? y - stemLength : y + stemLength))
        context.stroke(stem, with: .color(stemColor), lineWidth: 1)
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
            context.stroke(flag, with: .color(theme.noteHead), lineWidth: 1.2)
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
                context.stroke(path, with: .color(theme.staffLine.opacity(0.6)), lineWidth: 0.5)
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
                context.stroke(path, with: .color(theme.staffLine.opacity(0.6)), lineWidth: 0.5)
                lineY += staffLineSpacing
            }
        }
    }

    private func drawAccidental(context: GraphicsContext, pitch: Pitch, x: CGFloat, y: CGFloat, showNatural: Bool = false) {
        if pitch.accidental == .natural && !showNatural { return }
        let symbol = pitch.accidental.displaySymbol
        let accText = Text(symbol).font(.system(size: scaled(12), weight: .bold))
        let radius: CGFloat = staffLineSpacing / 2 - 1
        context.draw(accText, at: CGPoint(x: x - radius * 2 - scaled(6), y: y))
    }

    private func drawArticulation(context: GraphicsContext, symbol: String, x: CGFloat, y: CGFloat, stemUp: Bool, duration: DurationValue, stackIndex: Int = 0) {
        let artOffset: CGFloat = staffLineSpacing * 0.8
        let stackSpacing: CGFloat = staffLineSpacing * 0.6
        let baseY: CGFloat
        if duration == .whole {
            baseY = y - artOffset
        } else if stemUp {
            baseY = y + artOffset
        } else {
            baseY = y - artOffset
        }
        // Stack multiple articulations away from note head
        let direction: CGFloat = (duration == .whole || !stemUp) ? -1 : 1
        let artY = baseY + direction * CGFloat(stackIndex) * stackSpacing
        let artText = Text(symbol).font(.system(size: scaled(10)))
        context.draw(artText, at: CGPoint(x: x, y: artY))
    }

    // MARK: - Beam Drawing

    struct BeamCandidate {
        let x: CGFloat
        let y: CGFloat
        let stemUp: Bool
        let duration: DurationValue
        let eventIndex: Int
    }

    private func drawBeams(context: GraphicsContext, candidates: [BeamCandidate], staffTop: CGFloat) {
        guard candidates.count >= 1 else { return }

        // Group consecutive beamable notes (adjacent eventIndex)
        var groups: [[BeamCandidate]] = []
        var currentGroup: [BeamCandidate] = []

        for candidate in candidates {
            if let last = currentGroup.last {
                if candidate.eventIndex == last.eventIndex + 1 {
                    currentGroup.append(candidate)
                } else {
                    groups.append(currentGroup)
                    currentGroup = [candidate]
                }
            } else {
                currentGroup.append(candidate)
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        let radius: CGFloat = staffLineSpacing / 2 - 1
        let stemLength = staffLineSpacing * 3.5
        let beamThickness: CGFloat = scaled(2.5)

        for group in groups {
            if group.count == 1 {
                // Single note — draw flag instead
                let c = group[0]
                drawFlags(context: context, x: c.x, y: c.y, radius: radius, stemUp: c.stemUp, duration: c.duration)
                continue
            }

            // Determine beam direction: majority vote
            let stemUp = group.filter(\.stemUp).count >= group.count / 2

            // Draw primary beam (eighth note level)
            let stemEndPoints: [(x: CGFloat, y: CGFloat)] = group.map { c in
                let stemX = stemUp ? c.x + radius : c.x - radius
                let stemEnd = stemUp ? c.y - stemLength : c.y + stemLength
                return (stemX, stemEnd)
            }

            guard let first = stemEndPoints.first, let last = stemEndPoints.last else { continue }

            // Primary beam line
            var beam = Path()
            beam.move(to: CGPoint(x: first.x, y: first.y))
            beam.addLine(to: CGPoint(x: last.x, y: last.y))
            context.stroke(beam, with: .color(theme.noteHead), lineWidth: beamThickness)

            // Secondary beam for sixteenth notes
            let sixteenthNotes = group.filter { $0.duration == .sixteenth || $0.duration == .thirtySecond }
            if sixteenthNotes.count >= 2 {
                // Find consecutive sixteenth groups within this group
                var sixteenthGroups: [[Int]] = []
                var curSixteenthGroup: [Int] = []
                for (i, c) in group.enumerated() {
                    if c.duration == .sixteenth || c.duration == .thirtySecond {
                        curSixteenthGroup.append(i)
                    } else {
                        if curSixteenthGroup.count >= 2 { sixteenthGroups.append(curSixteenthGroup) }
                        curSixteenthGroup = []
                    }
                }
                if curSixteenthGroup.count >= 2 { sixteenthGroups.append(curSixteenthGroup) }

                let secondBeamOffset: CGFloat = stemUp ? beamThickness + scaled(2) : -(beamThickness + scaled(2))
                for subGroup in sixteenthGroups {
                    guard let firstIdx = subGroup.first, let lastIdx = subGroup.last else { continue }
                    let p1 = stemEndPoints[firstIdx]
                    let p2 = stemEndPoints[lastIdx]
                    var beam2 = Path()
                    beam2.move(to: CGPoint(x: p1.x, y: p1.y + secondBeamOffset))
                    beam2.addLine(to: CGPoint(x: p2.x, y: p2.y + secondBeamOffset))
                    context.stroke(beam2, with: .color(theme.noteHead), lineWidth: beamThickness)
                }
            }
        }
    }

    // MARK: - Key Signature Drawing

    /// Draw key signature accidentals and return the X position after the last accidental
    private func drawKeySignature(context: GraphicsContext, fifths: Int, x: CGFloat, staffTop: CGFloat) -> CGFloat {
        // Staff line positions from top: 0 = F5, 1 = E5, 2 = D5, 3 = C5, 4 = B4 (treble)
        // Sharp order positions on treble clef (line/space index from top line):
        // F♯(0), C♯(1.5), G♯(-0.5), D♯(1), A♯(2.5), E♯(0.5), B♯(2)
        let sharpPositions: [CGFloat]  // half-spaces from top line
        let flatPositions: [CGFloat]

        switch clef {
        case .treble:
            // Sharp order: F C G D A E B — positions as half-spaces from top line
            sharpPositions = [0, 3, -1, 2, 5, 1, 4]
            // Flat order: B E A D G C F
            flatPositions = [4, 1, 5, 2, 6, 3, 7]
        case .bass:
            // Sharp order on bass: shifted down 2 positions from treble
            sharpPositions = [2, 5, 1, 4, 7, 3, 6]
            flatPositions = [6, 3, 7, 4, 8, 5, 9]
        case .alto:
            sharpPositions = [1, 4, 0, 3, 6, 2, 5]
            flatPositions = [5, 2, 6, 3, 7, 4, 8]
        case .tenor:
            sharpPositions = [3, 6, 2, 5, 8, 4, 7]
            flatPositions = [7, 4, 8, 5, 9, 6, 10]
        }

        let symbol: String
        let positions: [CGFloat]
        let count: Int

        if fifths > 0 {
            symbol = "♯"
            positions = sharpPositions
            count = min(fifths, 7)
        } else {
            symbol = "♭"
            positions = flatPositions
            count = min(-fifths, 7)
        }

        let spacing = scaled(8)
        var currentX = x

        for i in 0..<count {
            let halfSpaces = positions[i]
            let y = staffTop + halfSpaces * (staffLineSpacing / 2)
            let accText = Text(symbol).font(.system(size: scaled(12), weight: .bold))
            context.draw(accText, at: CGPoint(x: currentX, y: y))
            currentX += spacing
        }

        return currentX
    }

    private func restSymbol(for duration: DurationValue) -> String {
        // SMuFL-compatible rest symbols (Unicode Musical Symbols block)
        switch duration {
        case .whole: return "𝄻"      // U+1D13B Whole rest
        case .half: return "𝄼"       // U+1D13C Half rest
        case .quarter: return "𝄽"    // U+1D13D Quarter rest
        case .eighth: return "𝄾"     // U+1D13E Eighth rest
        case .sixteenth: return "𝄿"  // U+1D13F Sixteenth rest
        case .thirtySecond: return "𝅀" // U+1D140 Thirty-second rest
        }
    }

    /// Pick the best rest symbol to represent a given number of remaining beats
    private func restSymbolForBeats(_ beats: Double) -> String {
        if beats >= 4.0 { return "𝄻" }
        if beats >= 2.0 { return "𝄼" }
        if beats >= 1.0 { return "𝄽" }
        if beats >= 0.5 { return "𝄾" }
        if beats >= 0.25 { return "𝄿" }
        return "𝅀"
    }
}
