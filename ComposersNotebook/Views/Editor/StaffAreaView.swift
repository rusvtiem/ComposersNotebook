import SwiftUI
import CoreText

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

    // Width is measured by the parent (outside the ScrollView). A GeometryReader
    // nested inside a ScrollView collapses to zero height and blanks the staff.
    var availableWidth: CGFloat

    private var theme: AppTheme { themeManager.currentTheme }

    // Base sizes at 1.0x zoom
    private let baseStaffLineSpacing: CGFloat = 10
    private let baseMeasureWidth: CGFloat = 200
    private let basePartSpacing: CGFloat = 80

    // Computed sizes based on zoom
    private var staffLineSpacing: CGFloat { baseStaffLineSpacing * viewModel.zoomScale }
    private var measureWidth: CGFloat { baseMeasureWidth * viewModel.zoomScale }
    private var staffHeight: CGFloat { staffLineSpacing * 4 + 40 * viewModel.zoomScale }
    private var partSpacing: CGFloat { basePartSpacing * viewModel.zoomScale }
    private var noteHitRadius: CGFloat { 14 * viewModel.zoomScale }

    // MARK: Vertical metrics (staff-space based, per standard engraving)
    // One staff-space (sp) = staffLineSpacing; a staff is 4 sp tall (5 lines).
    // Room above/below a staff for note heads, stems and ledger lines.
    private var noteRoom: CGFloat { 4 * staffLineSpacing }
    // The five staff lines only.
    private var staffLinesHeight: CGFloat { 4 * staffLineSpacing }
    // Full per-measure drawing frame: staff plus note room on both sides.
    private var measureFrameHeight: CGFloat { staffLinesHeight + noteRoom * 2 }
    // Gap between the bottom line of one staff and the top line of the next in a
    // piano grand staff. Fixed at 2 sp by pitch continuity: treble bottom line is
    // E4, bass top line is A3, four diatonic steps apart (E4-D4-C4-B3-A3) = 2 sp,
    // so middle C (C4) lands on a single ledger line centred between the staves.
    // This is NOT a free constant — a larger gap breaks pitch continuity.
    private var grandStaffGap: CGFloat { 2 * staffLineSpacing }

    private var systemAvailableWidth: CGFloat {
        max(UIScreen.main.bounds.width - 40, 300) * viewModel.zoomScale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.score.parts.enumerated()), id: \.offset) { partIndex, part in
                partRow(part: part, partIndex: partIndex, availableWidth: availableWidth)
            }
        }
    }

    // MARK: - Part Row

    private func partRow(part: Part, partIndex: Int, availableWidth: CGFloat) -> some View {
        let staff = part.staves[0]
        let ts = viewModel.score.timeSignature
        let layout = EngravingEngine.computeLayout(
            measures: staff.measures,
            availableWidth: availableWidth,
            baseSpacing: baseStaffLineSpacing,
            zoomScale: viewModel.zoomScale,
            timeSignature: ts
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text(part.instrument.shortName)
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)

            if part.isGrandStaff {
                ForEach(Array(layout.measureRanges.enumerated()), id: \.offset) { _, range in
                    grandStaffSystem(part: part, partIndex: partIndex, measureRange: range, measureWidths: layout.measureWidths)
                }
            } else {
                ForEach(Array(layout.measureRanges.enumerated()), id: \.offset) { _, range in
                    singleStaffSystem(part: part, partIndex: partIndex, staffIndex: 0, measureRange: range, measureWidths: layout.measureWidths)
                }
            }

            Spacer().frame(height: partSpacing - staffHeight)
        }
    }

    // MARK: - Single Staff System (one line of measures)

    private func singleStaffSystem(part: Part, partIndex: Int, staffIndex: Int, measureRange: Range<Int>, measureWidths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(measureRange, id: \.self) { measureIndex in
                let measure = part.staves[staffIndex].measures[measureIndex]
                let isCurrentMeasure = partIndex == viewModel.selectedPartIndex
                    && staffIndex == viewModel.selectedStaffIndex
                    && measureIndex == viewModel.selectedMeasureIndex
                let w = measureWidths[measureIndex]

                staffMeasureView(
                    part: part, partIndex: partIndex, staffIndex: staffIndex,
                    measure: measure, measureIndex: measureIndex,
                    isCurrentMeasure: isCurrentMeasure,
                    overrideWidth: w
                )
            }
        }
    }

    // MARK: - Multi-Staff Row (grand staff: 2+ staves with brace)

    // Each measure frame carries `noteRoom` below the top staff and above the
    // bottom staff, so pull the frames together to leave exactly grandStaffGap.
    private var grandStaffSpacing: CGFloat { grandStaffGap - 2 * noteRoom }

    private func grandStaffSystem(part: Part, partIndex: Int, measureRange: Range<Int>, measureWidths: [CGFloat]) -> some View {
        let stavesCount = part.staves.count
        return HStack(spacing: 0) {
            ForEach(measureRange, id: \.self) { measureIndex in
                let w = measureWidths[measureIndex]
                VStack(spacing: grandStaffSpacing) {
                    ForEach(0..<stavesCount, id: \.self) { staffIndex in
                        let measure = part.staves[staffIndex].measures[measureIndex]
                        let isCurrent = partIndex == viewModel.selectedPartIndex
                            && viewModel.selectedStaffIndex == staffIndex
                            && measureIndex == viewModel.selectedMeasureIndex

                        staffMeasureView(
                            part: part, partIndex: partIndex, staffIndex: staffIndex,
                            measure: measure, measureIndex: measureIndex,
                            isCurrentMeasure: isCurrent,
                            overrideWidth: w,
                            drawSelectionBox: false
                        )
                    }
                }
                // Selection highlight spans the whole grand-staff system (both
                // staves + the gap), not a single staff — a piano measure is one
                // column. Hugs the staff lines: from the top line of the first
                // staff to the bottom line of the last.
                .overlay(alignment: .top) {
                    let systemSelected = partIndex == viewModel.selectedPartIndex
                        && measureIndex == viewModel.selectedMeasureIndex
                    let totalH = staffLinesHeight * CGFloat(stavesCount) + grandStaffGap * CGFloat(stavesCount - 1)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(systemSelected ? theme.accent : Color.clear, lineWidth: 2)
                        .frame(height: totalH + 6 * viewModel.zoomScale)
                        .padding(.top, noteRoom - 3 * viewModel.zoomScale)
                }
                .overlay(alignment: .leading) {
                    if measureIndex == measureRange.lowerBound {
                        braceView(stavesCount: stavesCount)
                    }
                }
                .overlay(alignment: .leading) {
                    // Span from the top line of the first staff to the bottom
                    // line of the last — centred, matching the symmetric frames.
                    let totalH = staffLinesHeight * CGFloat(stavesCount) + grandStaffGap * CGFloat(stavesCount - 1)
                    Rectangle()
                        .fill(theme.staffLine)
                        .frame(width: 1, height: totalH)
                        .offset(x: -1)
                }
            }
        }
    }

    private func braceView(stavesCount: Int) -> some View {
        let totalH = staffLinesHeight * CGFloat(stavesCount) + grandStaffGap * CGFloat(stavesCount - 1)
        let braceWidth = totalH * 0.14
        return Canvas { context, size in
            let musicFont = MusicFontManager.shared
            guard musicFont.isBravuraAvailable else {
                let fallback = Text("{")
                    .font(.system(size: totalH * 0.8, weight: .ultraLight))
                    .foregroundColor(theme.staffLine)
                context.draw(fallback, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            // SMuFL brace (U+E000) is ~1 em tall; scale vertically to span the
            // whole system. y-up glyph is un-mirrored with d:-sy in y-down space.
            let ctFont = musicFont.uiMusicFont(size: totalH) as CTFont
            var utf16 = Array("\u{E000}".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
            guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
                  let glyph = glyphs.first, glyph != 0,
                  let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { return }
            let bbox = path.boundingBoxOfPath
            let sy = totalH / bbox.height
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -sy, tx: size.width - bbox.width, ty: totalH)
            if let placed = path.copy(using: &transform) {
                context.fill(Path(placed), with: .color(theme.staffLine))
            }
        }
        .frame(width: braceWidth, height: totalH)
        .offset(x: -(braceWidth + 3 * viewModel.zoomScale))
    }

    // MARK: - Staff Measure View (shared between single/grand)

    private func staffMeasureView(
        part: Part, partIndex: Int, staffIndex: Int,
        measure: Measure, measureIndex: Int,
        isCurrentMeasure: Bool,
        overrideWidth: CGFloat? = nil,
        drawSelectionBox: Bool = true
    ) -> some View {
        let clef = effectiveClef(partIndex: partIndex, staffIndex: staffIndex, measureIndex: measureIndex)
        let ts = effectiveTimeSignature(partIndex: partIndex, staffIndex: staffIndex, measureIndex: measureIndex)
        let ks = effectiveKeySignature(partIndex: partIndex, staffIndex: staffIndex, measureIndex: measureIndex)

        return MeasureView(
            measure: measure,
            measureIndex: measureIndex,
            isSelected: isCurrentMeasure,
            selectedEventIndex: isCurrentMeasure ? viewModel.selectedEventIndex : nil,
            timeSignature: ts,
            keySignature: ks,
            clef: clef,
            staffLineSpacing: staffLineSpacing,
            zoomScale: viewModel.zoomScale,
            theme: theme
        )
        .frame(width: overrideWidth ?? measureWidth, height: measureFrameHeight)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    let wasDifferent = viewModel.selectedMeasureIndex != measureIndex
                        || viewModel.selectedPartIndex != partIndex
                        || viewModel.selectedStaffIndex != staffIndex
                    viewModel.selectPart(at: partIndex)
                    viewModel.selectedStaffIndex = staffIndex
                    viewModel.selectedMeasureIndex = measureIndex
                    if wasDifferent {
                        viewModel.cursorPosition = currentMeasureBeats(measure: measure, ts: ts)
                    }

                    let positions = computeNotePositions(
                        measure: measure, measureIndex: measureIndex,
                        clef: clef, timeSignature: ts, width: overrideWidth
                    )

                    if let hitIndex = hitTestNote(at: value.location, positions: positions) {
                        if viewModel.selectedEventIndex == hitIndex {
                            viewModel.deselectEvent()
                        } else {
                            viewModel.selectEvent(at: hitIndex)
                        }
                        return
                    }

                    viewModel.deselectEvent()

                    switch viewModel.inputMode {
                    case .note:
                        if let pitch = pitchFromTap(y: value.location.y, clef: clef) {
                            viewModel.addNote(pitch: pitch)
                        }
                    case .rest:
                        viewModel.addRest()
                    case .navigate:
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
                        if let pitch = pitchFromTap(y: drag.location.y, clef: clef) {
                            viewModel.updateSelectedEventPitch(pitch)
                        }
                    default: break
                    }
                }
        )
        // Selection highlight hugs the staff itself, not the padded note-room
        // frame (staff sits `noteRoom` from the top, is `staffLinesHeight` tall).
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    (drawSelectionBox && isCurrentMeasure) ? theme.accent : Color.clear,
                    lineWidth: 2
                )
                .frame(height: staffLinesHeight + 6 * viewModel.zoomScale)
                .padding(.top, noteRoom - 3 * viewModel.zoomScale)
        }
    }

    // MARK: - Note Hit Testing

    private func computeNotePositions(measure: Measure, measureIndex: Int, clef: Clef, timeSignature: TimeSignature, width: CGFloat? = nil) -> [NoteHitInfo] {
        let z = viewModel.zoomScale
        let startX: CGFloat = 8 * z
        let staffTop: CGFloat = noteRoom
        let noteStartX: CGFloat = measureIndex == 0 ? startX + 45 * z : startX + 15 * z
        let effectiveWidth = width ?? measureWidth
        let availableWidth = effectiveWidth - noteStartX - 10 * z
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

    private func effectiveTimeSignature(partIndex: Int, staffIndex: Int = 0, measureIndex: Int) -> TimeSignature {
        let part = viewModel.score.parts[partIndex]
        let sIdx = min(staffIndex, part.staves.count - 1)
        for i in stride(from: measureIndex, through: 0, by: -1) {
            if let ts = part.staves[sIdx].measures[i].timeSignature {
                return ts
            }
        }
        return viewModel.score.timeSignature
    }

    private func effectiveKeySignature(partIndex: Int, staffIndex: Int = 0, measureIndex: Int) -> KeySignature {
        let part = viewModel.score.parts[partIndex]
        let sIdx = min(staffIndex, part.staves.count - 1)
        for i in stride(from: measureIndex, through: 0, by: -1) {
            if let ks = part.staves[sIdx].measures[i].keySignature {
                return ks
            }
        }
        return viewModel.score.keySignature
    }

    private func effectiveClef(partIndex: Int, staffIndex: Int = 0, measureIndex: Int) -> Clef {
        let part = viewModel.score.parts[partIndex]
        let sIdx = min(staffIndex, part.staves.count - 1)
        for i in stride(from: measureIndex, through: 0, by: -1) {
            if let clef = part.staves[sIdx].measures[i].clefChange {
                return clef
            }
        }
        // Return the clef for this specific staff
        return sIdx < part.instrument.clefs.count ? part.instrument.clefs[sIdx] : part.instrument.defaultClef
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
            // Staff sits `noteRoom` (4 sp) below the frame top, matching the
            // frame height and the hit-test in StaffAreaView.
            let staffTop: CGFloat = staffLineSpacing * 4

            // Draw 5 staff lines.
            // Visibility guarantee: clamp the theme's staffLineOpacity to a
            // minimum readable value, and never render thinner than 1pt
            // regardless of zoom. Empty scores must show the staff plainly
            // (the rendered staff is the visual cue that a measure exists);
            // before this clamp the default dark theme used 40% white at
            // 0.5pt × 0.85 zoom ≈ 0.43pt — sub-pixel and visually empty.
            let staffLineVisibleOpacity = max(theme.staffLineOpacity, 0.7)
            let staffLineWidth: CGFloat = max(1.0, scaled(0.6))
            for line in 0..<5 {
                let y = staffTop + CGFloat(line) * staffLineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(theme.staffLine.opacity(staffLineVisibleOpacity)), lineWidth: staffLineWidth)
            }

            // Draw barline at end with the same readability floor.
            var barline = Path()
            let barlineX = size.width - 1
            barline.move(to: CGPoint(x: barlineX, y: staffTop))
            barline.addLine(to: CGPoint(x: barlineX, y: staffTop + 4 * staffLineSpacing))
            context.stroke(barline, with: .color(theme.barline.opacity(0.9)), lineWidth: max(1.0, scaled(1.0)))

            // Draw measure number above staff
            let measureNum = Text("\(measureIndex + 1)")
                .font(.system(size: scaled(8), weight: .medium))
            context.draw(measureNum, at: CGPoint(x: startX + scaled(4), y: staffTop - scaled(6)),
                        anchor: .leading)

            // Draw clef at start of first measure; the time signature begins clear
            // of its real right ink edge so they never collide.
            var headerEndX: CGFloat = startX
            if measureIndex == 0 {
                headerEndX = drawClef(context: context, clef: clef, x: startX + scaled(8), staffTop: staffTop) + scaled(6)
            }

            // Draw time signature at start of first measure
            if measureIndex == 0 || measure.timeSignature != nil {
                let tsX: CGFloat = headerEndX + scaled(6)
                headerEndX = drawTimeSignature(context: context, beats: timeSignature.beats, beatValue: timeSignature.beatValue, x: tsX, staffTop: staffTop) + scaled(8)
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
                        drawArticulation(context: context, symbol: articulation.displaySymbol, x: noteX, y: y, stemUp: stemUp, duration: event.duration.value, stackIndex: artIdx, articulation: articulation)
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
                    let musicFont = MusicFontManager.shared
                    if musicFont.isBravuraAvailable {
                        let dynSymbol = bravuraDynamic(dynamic)
                        let dynText = Text(dynSymbol)
                            .font(musicFont.musicFont(size: scaled(16)))
                            .foregroundColor(theme.noteHead)
                        context.draw(dynText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 5 * staffLineSpacing + scaled(5)))
                    } else {
                        let dynText = Text(dynamic.displayName)
                            .font(.system(size: scaled(9), design: .serif))
                            .italic()
                        context.draw(dynText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 5 * staffLineSpacing + scaled(5)))
                    }
                }

                // Lyrics (подтекстовка) below staff
                if let lyric = event.lyric, !lyric.isEmpty {
                    let lyricText = Text(lyric)
                        .font(.system(size: scaled(9)))
                    context.draw(lyricText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop + 5 * staffLineSpacing + scaled(14)))
                }

                // Playback technique marking
                if let technique = event.technique {
                    let techText = Text(technique.italianName)
                        .font(.system(size: scaled(8), design: .serif))
                        .italic()
                    context.draw(techText, at: CGPoint(x: currentX + eventWidth / 2, y: staffTop - scaled(4)))
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

            // Repeat barlines (end side)
            if measure.barlineEnd == .repeatEnd || measure.barlineEnd == .repeatBoth {
                let dotY1 = staffTop + 1.5 * staffLineSpacing
                let dotY2 = staffTop + 2.5 * staffLineSpacing
                let dotSize = scaled(4)
                let dot = Path(ellipseIn: CGRect(x: barlineX - dotSize * 2, y: dotY1 - dotSize / 2, width: dotSize, height: dotSize))
                let dot2 = Path(ellipseIn: CGRect(x: barlineX - dotSize * 2, y: dotY2 - dotSize / 2, width: dotSize, height: dotSize))
                context.fill(dot, with: .color(theme.noteHead))
                context.fill(dot2, with: .color(theme.noteHead))
                // Thicker barline for repeat
                var thick = Path()
                thick.move(to: CGPoint(x: barlineX - scaled(3), y: staffTop))
                thick.addLine(to: CGPoint(x: barlineX - scaled(3), y: staffTop + 4 * staffLineSpacing))
                context.stroke(thick, with: .color(theme.barline), lineWidth: 2.5)
            }
            // Double / Final barlines
            if measure.barlineEnd == .double {
                var second = Path()
                second.move(to: CGPoint(x: barlineX - scaled(3), y: staffTop))
                second.addLine(to: CGPoint(x: barlineX - scaled(3), y: staffTop + 4 * staffLineSpacing))
                context.stroke(second, with: .color(theme.barline), lineWidth: 1)
            }
            if measure.barlineEnd == .final_ {
                var thick = Path()
                thick.move(to: CGPoint(x: barlineX - scaled(3), y: staffTop))
                thick.addLine(to: CGPoint(x: barlineX - scaled(3), y: staffTop + 4 * staffLineSpacing))
                context.stroke(thick, with: .color(theme.barline), lineWidth: 3)
            }
            // Repeat start (left side of this measure if first)
            if measure.barlineEnd == .repeatStart || measure.barlineEnd == .repeatBoth {
                let leftX: CGFloat = scaled(2)
                var thick = Path()
                thick.move(to: CGPoint(x: leftX, y: staffTop))
                thick.addLine(to: CGPoint(x: leftX, y: staffTop + 4 * staffLineSpacing))
                context.stroke(thick, with: .color(theme.barline), lineWidth: 2.5)
                let dotY1 = staffTop + 1.5 * staffLineSpacing
                let dotY2 = staffTop + 2.5 * staffLineSpacing
                let dotSize = scaled(4)
                context.fill(Path(ellipseIn: CGRect(x: leftX + scaled(4), y: dotY1 - dotSize / 2, width: dotSize, height: dotSize)), with: .color(theme.noteHead))
                context.fill(Path(ellipseIn: CGRect(x: leftX + scaled(4), y: dotY2 - dotSize / 2, width: dotSize, height: dotSize)), with: .color(theme.noteHead))
            }

            // MARK: - Phase 2c spanners and texts

            // Helper to convert a beat position to an x coordinate, given the
            // already-computed event layout. Clamps to [noteStartX, barlineX].
            func xForBeat(_ beat: Double) -> CGFloat {
                guard !measure.events.isEmpty, totalBeats > 0 else {
                    let t = max(0, min(1, beat / max(timeSignature.totalBeats, 0.001)))
                    return noteStartX + availableWidth * CGFloat(t)
                }
                // Walk through events accumulating actualBeats; interpolate within an event.
                var x = noteStartX
                var b: Double = 0
                for (i, event) in measure.events.enumerated() {
                    let eventWidth = idealWidths[i] * scaleFactor
                    let eb = event.actualBeats
                    if beat < b + eb {
                        let t = eb > 0 ? max(0, (beat - b)) / eb : 0
                        return x + eventWidth * CGFloat(t)
                    }
                    x += eventWidth
                    b += eb
                }
                return min(x, barlineX - scaled(2))
            }

            // Tuplet brackets (group-aware)
            //
            // Группы определяются через NoteEvent.tuplet.groupID. Для каждой
            // уникальной группы находим первую и последнюю позицию ноты,
            // рисуем скобку и число над/под (выше штили вверх → скобка снизу).
            do {
                var seenGroups: Set<UUID> = []
                for (i, event) in measure.events.enumerated() {
                    guard let tup = event.tuplet, !seenGroups.contains(tup.groupID) else { continue }
                    seenGroups.insert(tup.groupID)
                    // Find all events of this group within the measure
                    let groupIndices = measure.events.enumerated().compactMap { (j, e) -> Int? in
                        e.tuplet?.groupID == tup.groupID ? j : nil
                    }
                    guard let firstIdx = groupIndices.first,
                          let lastIdx = groupIndices.last else { continue }
                    let firstPos = notePositions.first { $0.eventIndex == firstIdx }
                    let lastPos = notePositions.first { $0.eventIndex == lastIdx }
                    guard let fp = firstPos, let lp = lastPos else { continue }

                    let bracketY = staffTop - scaled(8)
                    var bracket = Path()
                    bracket.move(to: CGPoint(x: fp.x, y: bracketY + scaled(3)))
                    bracket.addLine(to: CGPoint(x: fp.x, y: bracketY))
                    bracket.addLine(to: CGPoint(x: (fp.x + lp.x) / 2 - scaled(5), y: bracketY))
                    bracket.move(to: CGPoint(x: (fp.x + lp.x) / 2 + scaled(5), y: bracketY))
                    bracket.addLine(to: CGPoint(x: lp.x, y: bracketY))
                    bracket.addLine(to: CGPoint(x: lp.x, y: bracketY + scaled(3)))
                    context.stroke(bracket, with: .color(theme.noteHead), lineWidth: 1)

                    let label = Text(tup.displayLabel).font(.system(size: scaled(10), weight: .semibold))
                    context.draw(label, at: CGPoint(x: (fp.x + lp.x) / 2, y: bracketY))

                    _ = i // suppress unused warning
                }
            }

            // Chord symbols + Fingering above each note
            for (eventIndex, event) in measure.events.enumerated() {
                guard let pos = notePositions.first(where: { $0.eventIndex == eventIndex }) else { continue }

                if let chord = event.chordSymbol {
                    let text = Text(chord.displayText)
                        .font(.system(size: scaled(11), weight: .medium))
                        .foregroundColor(theme.accent)
                    context.draw(text, at: CGPoint(x: pos.x, y: staffTop - scaled(18)))
                }

                if let fingering = event.fingering {
                    let text = Text(fingering)
                        .font(.system(size: scaled(9), weight: .semibold))
                        .foregroundColor(theme.noteHead)
                    // Place fingering near notehead — to the right and slightly above
                    context.draw(text, at: CGPoint(x: pos.x + scaled(8), y: pos.y - scaled(6)))
                }
            }

            // Hairpins (crescendo <  / diminuendo >)
            for hairpin in measure.hairpins {
                let x1 = xForBeat(hairpin.startBeat)
                let x2 = xForBeat(hairpin.endBeat)
                let yCenter = staffTop + 5 * staffLineSpacing + scaled(18)
                let half = scaled(3)
                var path = Path()
                switch hairpin.type {
                case .crescendo:
                    path.move(to: CGPoint(x: x1, y: yCenter))
                    path.addLine(to: CGPoint(x: x2, y: yCenter - half))
                    path.move(to: CGPoint(x: x1, y: yCenter))
                    path.addLine(to: CGPoint(x: x2, y: yCenter + half))
                case .diminuendo:
                    path.move(to: CGPoint(x: x1, y: yCenter - half))
                    path.addLine(to: CGPoint(x: x2, y: yCenter))
                    path.move(to: CGPoint(x: x1, y: yCenter + half))
                    path.addLine(to: CGPoint(x: x2, y: yCenter))
                }
                context.stroke(path, with: .color(theme.noteHead), lineWidth: 1)
            }

            // Octave shifts (8va / 8vb / 15ma / 15mb) — dashed line + small number
            for shift in measure.octaveShifts {
                let x1 = xForBeat(shift.startBeat)
                let x2 = xForBeat(shift.endBeat)
                let isAbove = shift.kind == .ottavaAlta || shift.kind == .quindicesimaAlta
                let y = isAbove ? staffTop - scaled(18) : staffTop + 5 * staffLineSpacing + scaled(28)

                let label = Text(shift.kind.symbol).font(.system(size: scaled(10), weight: .semibold).italic())
                context.draw(label, at: CGPoint(x: x1 + scaled(6), y: y))

                // Dashed line from after label to x2
                var dash = Path()
                dash.move(to: CGPoint(x: x1 + scaled(14), y: y))
                dash.addLine(to: CGPoint(x: x2, y: y))
                let stroke = StrokeStyle(lineWidth: 0.8, dash: [scaled(3), scaled(3)])
                context.stroke(dash, with: .color(theme.noteHead.opacity(0.8)), style: stroke)
                // Closing hook at the end
                var hook = Path()
                hook.move(to: CGPoint(x: x2, y: y))
                hook.addLine(to: CGPoint(x: x2, y: y + (isAbove ? scaled(3) : -scaled(3))))
                context.stroke(hook, with: .color(theme.noteHead.opacity(0.8)), lineWidth: 0.8)
            }

            // Volta (1st / 2nd ending bracket)
            if let volta = measure.volta {
                let y = staffTop - scaled(26)
                let xStart = noteStartX
                let xEnd = barlineX - scaled(2)
                var v = Path()
                v.move(to: CGPoint(x: xStart, y: y + scaled(8)))
                v.addLine(to: CGPoint(x: xStart, y: y))
                v.addLine(to: CGPoint(x: xEnd, y: y))
                v.addLine(to: CGPoint(x: xEnd, y: y + scaled(8)))
                context.stroke(v, with: .color(theme.noteHead), lineWidth: 1)
                let label = Text("\(volta.number).").font(.system(size: scaled(10), weight: .semibold))
                context.draw(label, at: CGPoint(x: xStart + scaled(8), y: y + scaled(4)))
            }

            // Rehearsal mark (buffered above volta if any)
            if let mark = measure.rehearsalMark {
                let y = (measure.volta != nil) ? staffTop - scaled(36) : staffTop - scaled(24)
                let label = Text(mark.text)
                    .font(.system(size: scaled(12), weight: mark.style == .bold ? .bold : .semibold))
                let center = CGPoint(x: noteStartX + scaled(2), y: y)
                if mark.style == .boxed {
                    let pad = scaled(3)
                    let textW = scaled(14)
                    let textH = scaled(14)
                    let rect = CGRect(x: center.x - textW / 2 - pad, y: center.y - textH / 2 - pad, width: textW + pad * 2, height: textH + pad * 2)
                    context.stroke(Path(rect), with: .color(theme.noteHead), lineWidth: 1)
                }
                context.draw(label, at: center)
            }

            // Expression texts (espressivo, dolce, ...) — italic above staff
            for expr in measure.expressionTexts {
                let x = xForBeat(expr.attachToBeat)
                let text = Text(expr.text)
                    .font(.system(size: scaled(10), design: .serif).italic())
                    .foregroundColor(theme.textSecondary)
                context.draw(text, at: CGPoint(x: x, y: staffTop - scaled(28)), anchor: .leading)
            }

            // Tempo change (accel / rit / ...) — italic text + dashed continuation
            if let tc = measure.tempoChange {
                let x1 = xForBeat(tc.startBeat)
                let x2 = xForBeat(tc.endBeat)
                let y = staffTop - scaled(14)
                let label = Text(tc.kind.symbol)
                    .font(.system(size: scaled(10), design: .serif).italic())
                context.draw(label, at: CGPoint(x: x1, y: y), anchor: .leading)
                var dash = Path()
                dash.move(to: CGPoint(x: x1 + scaled(20), y: y))
                dash.addLine(to: CGPoint(x: x2, y: y))
                context.stroke(dash, with: .color(theme.noteHead.opacity(0.6)), style: StrokeStyle(lineWidth: 0.6, dash: [scaled(2), scaled(2)]))
            }

            // Multi-measure rest — thick horizontal block with count number
            if measure.multiMeasureRestCount > 0 {
                let midY = staffTop + 2 * staffLineSpacing
                let blockHeight = staffLineSpacing
                let pad = scaled(20)
                let rect = CGRect(x: noteStartX + pad, y: midY - blockHeight / 2, width: max(availableWidth - pad * 2, scaled(40)), height: blockHeight)
                context.fill(Path(rect), with: .color(theme.noteHead))
                let countText = Text("\(measure.multiMeasureRestCount)").font(.system(size: scaled(14), weight: .bold))
                context.draw(countText, at: CGPoint(x: rect.midX, y: midY - blockHeight - scaled(2)))
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

    // Draw a clef as a vector outline (CTFont glyph path) rather than centred
    // text. SwiftUI's Text draw centres on the font's line box, which for Bravura
    // is far larger than the glyph and shoves the clef off its reference line.
    // Per SMuFL scoring metrics the glyph baseline (y=0) IS the clef's reference
    // pitch, so we register that baseline onto the correct staff line:
    //   G clef → G4 (2nd line from bottom), F clef → F3 (2nd line from top).
    // Font size 4 sp: per SMuFL, 1 staff space = 0.25 em, so the em (font point
    // size) equals the staff height = 4 staff spaces. (Was 5 sp = 25% oversized.)
    /// Draws the clef and returns the x of its right ink edge so the caller can
    /// place the time signature / notes clear of it (the glyph's real width).
    @discardableResult
    private func drawClef(context: GraphicsContext, clef: Clef, x: CGFloat, staffTop: CGFloat) -> CGFloat {
        let musicFont = MusicFontManager.shared
        guard musicFont.isBravuraAvailable else {
            let clefText = Text(clef.symbol)
                .font(.system(size: staffLineSpacing * 4))
                .foregroundColor(theme.noteHead)
            context.draw(clefText, at: CGPoint(x: x + staffLineSpacing, y: staffTop + 2 * staffLineSpacing))
            return x + staffLineSpacing * 3
        }
        let em = staffLineSpacing * 4
        let ctFont = musicFont.uiMusicFont(size: em) as CTFont
        var utf16 = Array(MusicSymbol.clef(clef).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
              let glyph = glyphs.first, glyph != 0,
              let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { return x + staffLineSpacing * 3 }

        let refLineY: CGFloat
        switch clef {
        case .treble: refLineY = staffTop + 3 * staffLineSpacing   // G4, 2nd line from bottom
        case .bass:   refLineY = staffTop + 1 * staffLineSpacing   // F3, 2nd line from top
        case .alto:   refLineY = staffTop + 2 * staffLineSpacing   // middle line
        case .tenor:  refLineY = staffTop + 1 * staffLineSpacing   // 4th line from bottom
        }
        // Glyph space is y-up with the reference pitch on the baseline (y=0);
        // screen space is y-down. Flip vertically and translate onto (x, refLineY).
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: refLineY)
        guard let placed = glyphPath.copy(using: &transform) else { return x + staffLineSpacing * 3 }
        context.fill(Path(placed), with: .color(theme.noteHead))
        return x + glyphPath.boundingBoxOfPath.maxX
    }

    // MARK: - Time signature (engraved Bravura digits)

    /// Draws a stacked engraved time signature (numerator over denominator) using
    /// Bravura's time-signature digit glyphs (U+E080–E089) via the same vector
    /// technique as the clef. Returns the x of its right ink edge. Falls back to
    /// bold system digits when Bravura is unavailable.
    @discardableResult
    private func drawTimeSignature(context: GraphicsContext, beats: Int, beatValue: Int, x: CGFloat, staffTop: CGFloat) -> CGFloat {
        let numLine = staffTop + staffLineSpacing        // centre of upper half of staff
        let denLine = staffTop + 3 * staffLineSpacing    // centre of lower half of staff
        let musicFont = MusicFontManager.shared
        guard musicFont.isBravuraAvailable else {
            let topNum = Text("\(beats)").font(.system(size: staffLineSpacing * 2, weight: .bold)).foregroundColor(theme.noteHead)
            let botNum = Text("\(beatValue)").font(.system(size: staffLineSpacing * 2, weight: .bold)).foregroundColor(theme.noteHead)
            context.draw(topNum, at: CGPoint(x: x + staffLineSpacing, y: numLine))
            context.draw(botNum, at: CGPoint(x: x + staffLineSpacing, y: denLine))
            return x + staffLineSpacing * 2.5
        }
        // SMuFL em == staff height == 4 staff spaces (see drawClef).
        let ctFont = musicFont.uiMusicFont(size: staffLineSpacing * 4) as CTFont
        let numDigits = "\(beats)"
        let denDigits = "\(beatValue)"
        let groupWidth = max(timeSigGroupWidth(numDigits, ctFont: ctFont),
                             timeSigGroupWidth(denDigits, ctFont: ctFont))
        let centreX = x + groupWidth / 2
        drawTimeSigGroup(context: context, digits: numDigits, centreX: centreX, centreY: numLine, ctFont: ctFont)
        drawTimeSigGroup(context: context, digits: denDigits, centreX: centreX, centreY: denLine, ctFont: ctFont)
        return x + groupWidth
    }

    private func timeSigGlyphPath(_ ch: Character, ctFont: CTFont) -> CGPath? {
        guard let digit = ch.wholeNumberValue else { return nil }
        var utf16 = Array(MusicSymbol.timeSigDigit(digit).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
              let glyph = glyphs.first, glyph != 0 else { return nil }
        return CTFontCreatePathForGlyph(ctFont, glyph, nil)
    }

    private func timeSigGroupWidth(_ digits: String, ctFont: CTFont) -> CGFloat {
        let gap = staffLineSpacing * 0.1
        var width: CGFloat = 0
        let chars = Array(digits)
        for (i, ch) in chars.enumerated() {
            guard let path = timeSigGlyphPath(ch, ctFont: ctFont) else { continue }
            width += path.boundingBoxOfPath.width
            if i < chars.count - 1 { width += gap }
        }
        return width
    }

    /// Draws one line of digits centred on (centreX, centreY). In y-down screen
    /// space the y-up glyph is un-mirrored with d:-1; centreY places the glyph
    /// bounding-box centre on the target line.
    private func drawTimeSigGroup(context: GraphicsContext, digits: String, centreX: CGFloat, centreY: CGFloat, ctFont: CTFont) {
        let gap = staffLineSpacing * 0.1
        let totalWidth = timeSigGroupWidth(digits, ctFont: ctFont)
        var cursor = centreX - totalWidth / 2
        for ch in digits {
            guard let path = timeSigGlyphPath(ch, ctFont: ctFont) else { continue }
            let bbox = path.boundingBoxOfPath
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: cursor - bbox.minX, ty: centreY + bbox.midY)
            if let placed = path.copy(using: &transform) {
                context.fill(Path(placed), with: .color(theme.noteHead))
            }
            cursor += bbox.width + gap
        }
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
        let noteColor: Color = selected ? theme.selectedNote : theme.noteHead
        let musicFont = MusicFontManager.shared

        if musicFont.isBravuraAvailable {
            let symbol: String
            switch duration {
            case .whole: symbol = MusicSymbol.noteheadWhole
            case .half: symbol = MusicSymbol.noteheadHalf
            default: symbol = MusicSymbol.noteheadBlack
            }
            let noteText = Text(symbol)
                .font(musicFont.musicFont(size: scaled(24)))
                .foregroundColor(noteColor)
            context.draw(noteText, at: CGPoint(x: x, y: y))

            if duration == .half || (duration != .whole && !skipFlags) {
                drawStem(context: context, x: x, y: y, radius: radius, stemUp: stemUp, color: noteColor, staffTop: staffTop)
            }
            if duration != .whole && duration != .half && !skipFlags {
                drawFlags(context: context, x: x, y: y, radius: radius, stemUp: stemUp, duration: duration, staffTop: staffTop)
            }
        } else {
            let rect = CGRect(x: x - radius, y: y - radius * 0.75, width: radius * 2, height: radius * 1.5)
            let ellipse = Path(ellipseIn: rect)

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

    private func drawArticulation(context: GraphicsContext, symbol: String, x: CGFloat, y: CGFloat, stemUp: Bool, duration: DurationValue, stackIndex: Int = 0, articulation: Articulation? = nil) {
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
        let direction: CGFloat = (duration == .whole || !stemUp) ? -1 : 1
        let artY = baseY + direction * CGFloat(stackIndex) * stackSpacing

        let musicFont = MusicFontManager.shared
        if musicFont.isBravuraAvailable, let art = articulation {
            let bravuraSymbol = bravuraArticulation(art)
            let artText = Text(bravuraSymbol)
                .font(musicFont.musicFont(size: scaled(16)))
                .foregroundColor(theme.noteHead)
            context.draw(artText, at: CGPoint(x: x, y: artY))
        } else {
            let artText = Text(symbol).font(.system(size: scaled(10)))
            context.draw(artText, at: CGPoint(x: x, y: artY))
        }
    }

    private func bravuraDynamic(_ dynamic: DynamicMarking) -> String {
        switch dynamic {
        case .ppp: return MusicSymbol.dynamicPiano + MusicSymbol.dynamicPiano + MusicSymbol.dynamicPiano
        case .pp: return MusicSymbol.dynamicPiano + MusicSymbol.dynamicPiano
        case .p: return MusicSymbol.dynamicPiano
        case .mp: return MusicSymbol.dynamicMezzo + MusicSymbol.dynamicPiano
        case .mf: return MusicSymbol.dynamicMezzo + MusicSymbol.dynamicForte
        case .f: return MusicSymbol.dynamicForte
        case .ff: return MusicSymbol.dynamicForte + MusicSymbol.dynamicForte
        case .fff: return MusicSymbol.dynamicForte + MusicSymbol.dynamicForte + MusicSymbol.dynamicForte
        case .sfz: return MusicSymbol.dynamicSforzando + MusicSymbol.dynamicForte + MusicSymbol.dynamicZ
        case .sfp: return MusicSymbol.dynamicSforzando + MusicSymbol.dynamicForte + MusicSymbol.dynamicPiano
        case .fp: return MusicSymbol.dynamicForte + MusicSymbol.dynamicPiano
        }
    }

    private func bravuraArticulation(_ art: Articulation) -> String {
        switch art {
        case .staccato: return MusicSymbol.articStaccatoAbove
        case .accent: return MusicSymbol.articAccentAbove
        case .tenuto: return MusicSymbol.articTenutoAbove
        case .marcato: return MusicSymbol.articMarcatoAbove
        case .fermata: return MusicSymbol.articFermataAbove
        case .legato: return "\u{E4A4}"
        }
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
