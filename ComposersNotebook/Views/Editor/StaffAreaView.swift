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
    private var staffHeight: CGFloat { staffLineSpacing * 4 + 60 * viewModel.zoomScale }
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

        // Mirror the spacing algorithm from MeasureView
        let minNoteWidth: CGFloat = 18 * z
        let hasAcc = measure.events.contains { event in
            switch event.type {
            case .note(let p): return p.accidental != .natural
            case .chord(let ps): return ps.contains { $0.accidental != .natural }
            case .rest: return false
            }
        }
        let accPad: CGFloat = hasAcc ? 10 * z : 0
        let refBeats = max(totalBeats, timeSignature.totalBeats)
        var idealWidths: [CGFloat] = []
        for event in measure.events {
            let proportional = availableWidth * CGFloat(event.duration.beats / refBeats)
            idealWidths.append(max(proportional, minNoteWidth + accPad))
        }
        let totalIdeal = idealWidths.reduce(0, +)
        let sf = totalIdeal > availableWidth ? availableWidth / totalIdeal : 1.0

        var positions: [NoteHitInfo] = []
        var currentX = noteStartX

        for (eventIndex, event) in measure.events.enumerated() {
            let eventWidth = idealWidths[eventIndex] * sf
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
                let musicFont = MusicFontManager.shared
                let clefSymbol = musicFont.isBravuraAvailable ? MusicSymbol.clef(clef) : clef.symbol
                let clefFont: Font = musicFont.isBravuraAvailable ? musicFont.musicFont(size: scaled(32)) : .system(size: scaled(28))
                let clefText = Text(clefSymbol).font(clefFont)
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
            let availableWidth = size.width - noteStartX - scaled(10)
            let totalBeats = measure.usedBeats
            guard totalBeats > 0 else { return }

            // Calculate minimum widths per note based on engraving standards
            // Shorter notes need proportionally more space than pure beat ratio
            let minNoteWidth = scaled(18) // minimum space for any note
            let hasAccidentals = measure.events.contains { event in
                switch event.type {
                case .note(let p): return p.accidental != .natural
                case .chord(let ps): return ps.contains { $0.accidental != .natural }
                case .rest: return false
                }
            }
            let accidentalPadding: CGFloat = hasAccidentals ? scaled(10) : 0

            // Two-pass spacing: first compute ideal widths, then normalize
            var idealWidths: [CGFloat] = []
            let refBeats = max(totalBeats, timeSignature.totalBeats)
            for event in measure.events {
                let proportional = availableWidth * CGFloat(event.duration.beats / refBeats)
                idealWidths.append(max(proportional, minNoteWidth + accidentalPadding))
            }
            let totalIdeal = idealWidths.reduce(0, +)
            let scaleFactor = totalIdeal > availableWidth ? availableWidth / totalIdeal : 1.0

            // First pass: collect note positions and draw notes
            struct NotePosition {
                let x: CGFloat
                let y: CGFloat
                let eventIndex: Int
            }
            var notePositions: [NotePosition] = []
            var beamCandidates: [MeasureView.BeamCandidate] = []
            var currentX = noteStartX
            var cumulativeBeats: Double = 0

            for (eventIndex, event) in measure.events.enumerated() {
                let eventWidth = idealWidths[eventIndex] * scaleFactor

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
                    drawNoteHead(context: context, x: noteX, y: y, duration: event.duration.value, stemUp: stemUp, selected: isEventSelected, skipFlags: isBeamable, staffTop: staffTop)
                    drawAugmentationDots(context: context, x: noteX, y: y, dotted: event.duration.dotted, doubleDotted: event.duration.doubleDotted)
                    drawLedgerLines(context: context, pitch: pitch, x: noteX, staffTop: staffTop)
                    drawAccidental(context: context, pitch: pitch, x: noteX, y: y, showNatural: event.showNatural)
                    notePositions.append(NotePosition(x: noteX, y: y, eventIndex: eventIndex))
                    if isBeamable {
                        beamCandidates.append(BeamCandidate(x: noteX, y: y, stemUp: stemUp, duration: event.duration.value, eventIndex: eventIndex, beatPosition: cumulativeBeats))
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
                        drawNoteHead(context: context, x: noteX, y: y, duration: event.duration.value, stemUp: stemUp, selected: isEventSelected, skipFlags: isBeamable, staffTop: staffTop)
                        drawAugmentationDots(context: context, x: noteX, y: y, dotted: event.duration.dotted, doubleDotted: event.duration.doubleDotted)
                        drawLedgerLines(context: context, pitch: pitch, x: noteX, staffTop: staffTop)
                        drawAccidental(context: context, pitch: pitch, x: noteX, y: y, showNatural: event.showNatural)
                    }
                    if let tp = topPitch {
                        let y = noteY(pitch: tp, staffTop: staffTop)
                        let noteX = currentX + eventWidth / 2
                        notePositions.append(NotePosition(x: noteX, y: y, eventIndex: eventIndex))
                        if isBeamable {
                            beamCandidates.append(BeamCandidate(x: noteX, y: y, stemUp: stemUp, duration: event.duration.value, eventIndex: eventIndex, beatPosition: cumulativeBeats))
                        }
                    }

                case .rest:
                    let restX = currentX + eventWidth / 2
                    let restY = staffTop + 2 * staffLineSpacing
                    if selectedEventIndex == eventIndex {
                        drawSelectionHighlight(context: context, x: restX, y: restY)
                    }
                    drawRestShape(context: context, x: restX, y: restY, duration: event.duration.value, staffTop: staffTop)
                    notePositions.append(NotePosition(x: restX, y: restY, eventIndex: eventIndex))
                }

                // Dynamic marking
                if let dynamic = event.dynamic {
                    let dynText = Text(dynamic.displayName)
                        .font(.system(size: scaled(9), design: .serif))
                        .italic()
                    context.draw(dynText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 5 * staffLineSpacing + scaled(5)))
                }

                cumulativeBeats += event.duration.beats
                currentX += eventWidth
            }

            // Draw ghost rests for remaining beats in the measure
            let remainingBeats = timeSignature.totalBeats - measure.usedBeats
            if remainingBeats > 0.01 && !measure.events.isEmpty {
                let remainingWidth = max(size.width - currentX - scaled(10), scaled(20))
                let ghostX = currentX + remainingWidth / 2
                let ghostDuration = restSymbolForBeats(remainingBeats)
                // Draw ghost rest with reduced opacity
                var ghostContext = context
                ghostContext.opacity = 0.3
                drawRestShape(context: ghostContext, x: ghostX, y: staffTop + 2 * staffLineSpacing, duration: ghostDuration, staffTop: staffTop)
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

    private func drawNoteHead(context: GraphicsContext, x: CGFloat, y: CGFloat, duration: DurationValue, stemUp: Bool = true, selected: Bool = false, skipFlags: Bool = false, staffTop: CGFloat = 0) {
        let radius: CGFloat = staffLineSpacing / 2 - 1
        let rect = CGRect(x: x - radius, y: y - radius * 0.75, width: radius * 2, height: radius * 1.5)
        let ellipse = Path(ellipseIn: rect)
        let noteColor: Color = selected ? theme.selectedNote : theme.noteHead

        switch duration {
        case .whole:
            context.stroke(ellipse, with: .color(noteColor), lineWidth: 1.5)
        case .half:
            context.stroke(ellipse, with: .color(noteColor), lineWidth: 1.5)
            drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor, staffTop: staffTop)
        default:
            context.fill(ellipse, with: .color(noteColor))
            if !skipFlags {
                drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor, staffTop: staffTop)
                drawFlags(context: context, x: x, y: y, radius: radius, stemUp: stemUp, duration: duration, staffTop: staffTop)
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

    private func drawStem(context: GraphicsContext, x: CGFloat, y: CGFloat, radius: CGFloat, stemUp: Bool, color: Color? = nil, staffTop: CGFloat? = nil) {
        let stemColor = color ?? theme.noteHead
        var stem = Path()
        let defaultStemLength = staffLineSpacing * 3.5
        let stemX = stemUp ? x + radius : x - radius

        // Calculate stem end, ensuring it reaches at least the middle of the staff
        var stemEnd: CGFloat
        if stemUp {
            stemEnd = y - defaultStemLength
            if let top = staffTop {
                let midStaff = top + staffLineSpacing * 2
                stemEnd = min(stemEnd, midStaff)
            }
        } else {
            stemEnd = y + defaultStemLength
            if let top = staffTop {
                let midStaff = top + staffLineSpacing * 2
                stemEnd = max(stemEnd, midStaff)
            }
        }

        stem.move(to: CGPoint(x: stemX, y: y))
        stem.addLine(to: CGPoint(x: stemX, y: stemEnd))
        context.stroke(stem, with: .color(stemColor), lineWidth: 1)
    }

    private func drawFlags(context: GraphicsContext, x: CGFloat, y: CGFloat, radius: CGFloat, stemUp: Bool, duration: DurationValue, staffTop: CGFloat = 0) {
        let flagCount: Int
        switch duration {
        case .eighth: flagCount = 1
        case .sixteenth: flagCount = 2
        case .thirtySecond: flagCount = 3
        default: return
        }

        let defaultStemLength = staffLineSpacing * 3.5
        let midStaff = staffTop + staffLineSpacing * 2
        let stemX = stemUp ? x + radius : x - radius
        var stemEnd = stemUp ? y - defaultStemLength : y + defaultStemLength
        if stemUp { stemEnd = min(stemEnd, midStaff) }
        else { stemEnd = max(stemEnd, midStaff) }
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
        let musicFont = MusicFontManager.shared
        let symbol: String
        let font: Font
        if musicFont.isBravuraAvailable {
            symbol = MusicSymbol.accidental(pitch.accidental)
            font = musicFont.musicFont(size: scaled(18))
        } else {
            symbol = pitch.accidental.displaySymbol
            font = .system(size: scaled(14), weight: .bold)
        }
        let accText = Text(symbol).font(font).foregroundColor(theme.noteHead)
        // Standard engraving: accidental placed ~1 staff space left of notehead
        let accOffset = staffLineSpacing * 1.2
        context.draw(accText, at: CGPoint(x: x - accOffset, y: y))
    }

    /// Draw augmentation dot(s) for dotted/double-dotted notes
    private func drawAugmentationDots(context: GraphicsContext, x: CGFloat, y: CGFloat, dotted: Bool, doubleDotted: Bool) {
        guard dotted || doubleDotted else { return }
        let radius: CGFloat = staffLineSpacing / 2 - 1
        let dotRadius: CGFloat = scaled(1.8)
        let dotX = x + radius + scaled(4)
        // If note is on a line, shift dot up by half a space
        let dotY = y
        let dot1 = Path(ellipseIn: CGRect(x: dotX - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        context.fill(dot1, with: .color(theme.noteHead))
        if doubleDotted {
            let dot2X = dotX + scaled(4)
            let dot2 = Path(ellipseIn: CGRect(x: dot2X - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
            context.fill(dot2, with: .color(theme.noteHead))
        }
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
        let beatPosition: Double  // cumulative beat position within measure
    }

    private func drawBeams(context: GraphicsContext, candidates: [BeamCandidate], staffTop: CGFloat) {
        guard !candidates.isEmpty else { return }

        // Step 1: Group consecutive beamable notes (adjacent eventIndex)
        var consecutiveGroups: [[BeamCandidate]] = []
        var currentGroup: [BeamCandidate] = []

        for candidate in candidates {
            if let last = currentGroup.last {
                if candidate.eventIndex == last.eventIndex + 1 {
                    currentGroup.append(candidate)
                } else {
                    consecutiveGroups.append(currentGroup)
                    currentGroup = [candidate]
                }
            } else {
                currentGroup.append(candidate)
            }
        }
        if !currentGroup.isEmpty {
            consecutiveGroups.append(currentGroup)
        }

        // Step 2: Split each consecutive group by beat boundaries
        // In 4/4: beat at 0, 1, 2, 3. Group = notes within same beat.
        // In 6/8: compound meter, group by dotted quarter (1.5 beats)
        let beatUnit: Double
        if timeSignature.beatValue == 8 && timeSignature.beats % 3 == 0 {
            // Compound meter (6/8, 9/8, 12/8): group by dotted quarter
            beatUnit = 1.5
        } else {
            // Simple meter: group by one beat
            beatUnit = 1.0
        }

        var beatGroups: [[BeamCandidate]] = []
        for group in consecutiveGroups {
            var subGroup: [BeamCandidate] = []
            for candidate in group {
                if let last = subGroup.last {
                    let lastBeat = Int(last.beatPosition / beatUnit)
                    let curBeat = Int(candidate.beatPosition / beatUnit)
                    if curBeat != lastBeat {
                        beatGroups.append(subGroup)
                        subGroup = [candidate]
                    } else {
                        subGroup.append(candidate)
                    }
                } else {
                    subGroup.append(candidate)
                }
            }
            if !subGroup.isEmpty {
                beatGroups.append(subGroup)
            }
        }

        let radius: CGFloat = staffLineSpacing / 2 - 1
        let minStemLength = staffLineSpacing * 2.5
        let beamThickness: CGFloat = scaled(2.5)
        let midStaff = staffTop + staffLineSpacing * 2

        for group in beatGroups {
            if group.count == 1 {
                // Single note — draw stem and flag
                let c = group[0]
                drawStem(context: context, x: c.x, y: c.y, radius: radius, stemUp: c.stemUp, color: theme.noteHead, staffTop: staffTop)
                drawFlags(context: context, x: c.x, y: c.y, radius: radius, stemUp: c.stemUp, duration: c.duration, staffTop: staffTop)
                continue
            }

            // Determine beam direction: use average note position
            let avgY = group.map(\.y).reduce(0, +) / CGFloat(group.count)
            let stemUp = avgY >= midStaff

            // Calculate flat beam Y position:
            // For stem up: beam above the highest note (smallest y) by minStemLength
            // For stem down: beam below the lowest note (largest y) by minStemLength
            let beamY: CGFloat
            if stemUp {
                let highestNoteY = group.map(\.y).min()!
                beamY = min(highestNoteY - minStemLength, midStaff)
            } else {
                let lowestNoteY = group.map(\.y).max()!
                beamY = max(lowestNoteY + minStemLength, midStaff)
            }

            // Draw stems from each notehead to the beam position
            for c in group {
                let stemX = stemUp ? c.x + radius : c.x - radius
                var stem = Path()
                stem.move(to: CGPoint(x: stemX, y: c.y))
                stem.addLine(to: CGPoint(x: stemX, y: beamY))
                context.stroke(stem, with: .color(theme.noteHead), lineWidth: 1)
            }

            // Calculate stem endpoint positions (for beam and secondary beam drawing)
            let stemEndPoints: [(x: CGFloat, y: CGFloat)] = group.map { c in
                let stemX = stemUp ? c.x + radius : c.x - radius
                return (stemX, beamY)
            }

            guard let first = stemEndPoints.first, let last = stemEndPoints.last else { continue }

            // Primary beam line (flat, at beamY)
            var beam = Path()
            beam.move(to: CGPoint(x: first.x, y: beamY))
            beam.addLine(to: CGPoint(x: last.x, y: beamY))
            context.stroke(beam, with: .color(theme.noteHead), lineWidth: beamThickness)

            // Secondary beam for sixteenth notes
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

            let beamGap: CGFloat = beamThickness + scaled(2)
            let secondBeamOffset: CGFloat = stemUp ? beamGap : -beamGap
            for subGroup in sixteenthGroups {
                guard let firstIdx = subGroup.first, let lastIdx = subGroup.last else { continue }
                let p1 = stemEndPoints[firstIdx]
                let p2 = stemEndPoints[lastIdx]
                var beam2 = Path()
                beam2.move(to: CGPoint(x: p1.x, y: p1.y + secondBeamOffset))
                beam2.addLine(to: CGPoint(x: p2.x, y: p2.y + secondBeamOffset))
                context.stroke(beam2, with: .color(theme.noteHead), lineWidth: beamThickness)
            }

            // Tertiary beam for 32nd notes
            var thirtySecondGroups: [[Int]] = []
            var cur32ndGroup: [Int] = []
            for (i, c) in group.enumerated() {
                if c.duration == .thirtySecond {
                    cur32ndGroup.append(i)
                } else {
                    if cur32ndGroup.count >= 2 { thirtySecondGroups.append(cur32ndGroup) }
                    cur32ndGroup = []
                }
            }
            if cur32ndGroup.count >= 2 { thirtySecondGroups.append(cur32ndGroup) }

            let thirdBeamOffset: CGFloat = stemUp ? beamGap * 2 : -beamGap * 2
            for subGroup in thirtySecondGroups {
                guard let firstIdx = subGroup.first, let lastIdx = subGroup.last else { continue }
                let p1 = stemEndPoints[firstIdx]
                let p2 = stemEndPoints[lastIdx]
                var beam3 = Path()
                beam3.move(to: CGPoint(x: p1.x, y: p1.y + thirdBeamOffset))
                beam3.addLine(to: CGPoint(x: p2.x, y: p2.y + thirdBeamOffset))
                context.stroke(beam3, with: .color(theme.noteHead), lineWidth: beamThickness)
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

        let musicFont = MusicFontManager.shared
        let symbol: String
        let font: Font
        let positions: [CGFloat]
        let count: Int

        if fifths > 0 {
            symbol = musicFont.isBravuraAvailable ? MusicSymbol.accidentalSharp : "♯"
            positions = sharpPositions
            count = min(fifths, 7)
        } else {
            symbol = musicFont.isBravuraAvailable ? MusicSymbol.accidentalFlat : "♭"
            positions = flatPositions
            count = min(-fifths, 7)
        }
        font = musicFont.isBravuraAvailable ? musicFont.musicFont(size: scaled(20)) : .system(size: scaled(16), weight: .bold)

        var currentX = x

        for i in 0..<count {
            let halfSpaces = positions[i]
            let y = staffTop + halfSpaces * (staffLineSpacing / 2)
            let accText = Text(symbol).font(font)
            context.draw(accText, at: CGPoint(x: currentX, y: y))
            currentX += scaled(10)
        }

        return currentX
    }

    private func restSymbol(for duration: DurationValue) -> String {
        // Text-based rest symbols (iOS system fonts don't render Unicode Musical Symbols block)
        switch duration {
        case .whole: return "—"       // Whole rest (horizontal bar)
        case .half: return "▬"        // Half rest (filled bar)
        case .quarter: return "𝄾"     // Try quarter rest, fallback below
        case .eighth: return "𝄾"
        case .sixteenth: return "𝄿"
        case .thirtySecond: return "𝅀"
        }
    }

    /// Draw rest as a graphical shape or Bravura glyph
    private func drawRestShape(context: GraphicsContext, x: CGFloat, y: CGFloat, duration: DurationValue, staffTop: CGFloat) {
        let sp = staffLineSpacing
        let musicFont = MusicFontManager.shared

        // Use Bravura SMuFL glyphs when available
        if musicFont.isBravuraAvailable {
            let restSymbol = MusicSymbol.rest(for: duration)
            let fontSize: CGFloat
            let restY: CGFloat
            switch duration {
            case .whole:
                fontSize = scaled(28)
                restY = staffTop + sp * 1.5
            case .half:
                fontSize = scaled(28)
                restY = staffTop + sp * 2.0
            case .quarter:
                fontSize = scaled(28)
                restY = staffTop + sp * 2.0
            case .eighth:
                fontSize = scaled(24)
                restY = staffTop + sp * 2.0
            case .sixteenth:
                fontSize = scaled(24)
                restY = staffTop + sp * 2.0
            case .thirtySecond:
                fontSize = scaled(22)
                restY = staffTop + sp * 2.0
            }
            let text = Text(restSymbol).font(musicFont.musicFont(size: fontSize)).foregroundColor(theme.noteHead)
            context.draw(context.resolve(text), at: CGPoint(x: x, y: restY), anchor: .center)
            return
        }

        // Fallback: Path-based drawing when Bravura not available
        switch duration {
        case .whole:
            let rect = CGRect(x: x - sp * 0.6, y: staffTop + sp - sp * 0.05, width: sp * 1.2, height: sp * 0.45)
            context.fill(Path(rect), with: .color(theme.noteHead))

        case .half:
            let rect = CGRect(x: x - sp * 0.6, y: staffTop + 2 * sp - sp * 0.45, width: sp * 1.2, height: sp * 0.45)
            context.fill(Path(rect), with: .color(theme.noteHead))

        case .quarter:
            var path = Path()
            let h = sp * 2.5
            let top = staffTop + sp * 0.75
            path.move(to: CGPoint(x: x + sp * 0.25, y: top))
            path.addLine(to: CGPoint(x: x - sp * 0.2, y: top + h * 0.25))
            path.addLine(to: CGPoint(x: x + sp * 0.25, y: top + h * 0.5))
            path.addLine(to: CGPoint(x: x - sp * 0.15, y: top + h * 0.75))
            path.addQuadCurve(to: CGPoint(x: x + sp * 0.1, y: top + h),
                             control: CGPoint(x: x - sp * 0.3, y: top + h * 0.95))
            context.stroke(path, with: .color(theme.noteHead), lineWidth: scaled(1.5))

        case .eighth:
            let dotY = staffTop + sp * 1.5
            let dotR: CGFloat = sp * 0.2
            context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)), with: .color(theme.noteHead))
            var tail = Path()
            tail.move(to: CGPoint(x: x, y: dotY))
            tail.addLine(to: CGPoint(x: x - sp * 0.3, y: staffTop + sp * 2.75))
            context.stroke(tail, with: .color(theme.noteHead), lineWidth: scaled(1.2))

        case .sixteenth:
            let dotR: CGFloat = sp * 0.18
            let dot1Y = staffTop + sp * 1.2
            let dot2Y = staffTop + sp * 2.0
            context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: dot1Y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(theme.noteHead))
            context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: dot2Y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(theme.noteHead))
            var tail = Path()
            tail.move(to: CGPoint(x: x, y: dot1Y))
            tail.addLine(to: CGPoint(x: x - sp * 0.3, y: staffTop + sp * 3.0))
            context.stroke(tail, with: .color(theme.noteHead), lineWidth: scaled(1.2))

        case .thirtySecond:
            let dotR: CGFloat = sp * 0.15
            let dot1Y = staffTop + sp * 1.0
            let dot2Y = staffTop + sp * 1.7
            let dot3Y = staffTop + sp * 2.4
            context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: dot1Y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(theme.noteHead))
            context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: dot2Y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(theme.noteHead))
            context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: dot3Y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(theme.noteHead))
            var tail = Path()
            tail.move(to: CGPoint(x: x, y: dot1Y))
            tail.addLine(to: CGPoint(x: x - sp * 0.3, y: staffTop + sp * 3.25))
            context.stroke(tail, with: .color(theme.noteHead), lineWidth: scaled(1.0))
        }
    }

    /// Pick the best rest symbol to represent a given number of remaining beats
    private func restSymbolForBeats(_ beats: Double) -> DurationValue {
        if beats >= 4.0 { return .whole }
        if beats >= 2.0 { return .half }
        if beats >= 1.0 { return .quarter }
        if beats >= 0.5 { return .eighth }
        if beats >= 0.25 { return .sixteenth }
        return .thirtySecond
    }
}
