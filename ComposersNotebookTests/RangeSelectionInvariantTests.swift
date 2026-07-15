import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore range-selection parity (Тимур parity point 2): Shift+←/→ grow a
/// contiguous range from an anchor, "select bar" and Ctrl+A seed larger ranges, and
/// range-aware transpose/delete act on every event in the blue span — not just the
/// focused note. These guard the pure selection model on `ScoreViewModel`, which the
/// toolbar buttons and the Verovio highlight both read from.
@MainActor
final class RangeSelectionInvariantTests: XCTestCase {

    /// A staff of `barCount` bars, each holding `perBar` quarter notes (rising pitch),
    /// with the focus parked on the first event of the first bar.
    private func viewModel(barCount: Int, perBar: Int) -> ScoreViewModel {
        var measures: [Measure] = []
        var midi = 60
        for _ in 0..<barCount {
            var events: [NoteEvent] = []
            for _ in 0..<perBar {
                events.append(.note(Pitch.fromMIDI(midi), duration: Duration(value: .quarter)))
                midi += 1
            }
            measures.append(Measure(events: events, timeSignature: .fourFour))
        }
        let part = Part(instrument: .flute, measures: measures)
        let score = Score(parts: [part], timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        vm.selectedEventIndex = 0
        return vm
    }

    private func measures(_ vm: ScoreViewModel) -> [Measure] {
        vm.score.parts[0].staves[0].measures
    }

    // MARK: - Shift+arrows anchor and grow

    /// The first Shift+→ anchors at the current focus and moves the focus forward, so
    /// the range covers both the origin note and the next one.
    func testExtendForwardAnchorsAndCoversTwo() {
        let vm = viewModel(barCount: 1, perBar: 4)
        vm.extendSelectionForward()
        XCTAssertTrue(vm.hasRangeSelection, "a two-event span is a range")
        XCTAssertEqual(vm.selectedRangePositions.map { $0.event }, [0, 1], "covers origin + next")
        XCTAssertEqual(vm.selectionAnchorEventIndex, 0, "anchor pinned at origin")
        XCTAssertEqual(vm.selectedEventIndex, 1, "focus moved forward")
    }

    /// Shift+→ then Shift+← collapses back onto the single origin note — the anchor and
    /// focus coincide again, so it is no longer a range.
    func testExtendForwardThenBackwardCollapses() {
        let vm = viewModel(barCount: 1, perBar: 4)
        vm.extendSelectionForward()
        vm.extendSelectionBackward()
        XCTAssertFalse(vm.hasRangeSelection, "focus returned onto the anchor")
        XCTAssertEqual(vm.selectedRangePositions.map { $0.event }, [0])
    }

    /// Shift+→ across a barline keeps the anchor in bar 0 and pulls the last note of
    /// bar 0 plus the first of bar 1 into the range (contiguous, measure-crossing).
    func testExtendForwardCrossesBarline() {
        let vm = viewModel(barCount: 2, perBar: 2)
        vm.selectedEventIndex = 1            // last event of bar 0
        vm.extendSelectionForward()          // should cross into bar 1, event 0
        XCTAssertEqual(vm.selectedMeasureIndex, 1, "focus crossed into next bar")
        XCTAssertEqual(vm.selectedEventIndex, 0)
        let cover = vm.selectedRangePositions.map { "\($0.measure).\($0.event)" }
        XCTAssertEqual(cover, ["0.1", "1.0"], "range spans the barline")
    }

    /// A plain arrow after a range must drop the range and become a single selection.
    func testPlainArrowClearsRange() {
        let vm = viewModel(barCount: 1, perBar: 4)
        vm.extendSelectionForward()
        XCTAssertTrue(vm.hasRangeSelection)
        vm.selectNextEvent()
        XCTAssertFalse(vm.hasRangeSelection, "plain → drops the anchor")
        XCTAssertNil(vm.selectionAnchorEventIndex)
    }

    // MARK: - Select bar / Ctrl+A

    func testSelectCurrentMeasureCoversWholeBar() {
        let vm = viewModel(barCount: 2, perBar: 4)
        vm.selectedMeasureIndex = 1
        vm.selectedEventIndex = 2
        vm.selectCurrentMeasure()
        XCTAssertTrue(vm.hasRangeSelection)
        XCTAssertEqual(vm.selectedRangePositions.map { $0.event }, [0, 1, 2, 3], "all four notes")
        XCTAssertTrue(vm.selectedRangePositions.allSatisfy { $0.measure == 1 }, "stays in bar 1")
    }

    func testSelectAllSpansEveryEventOnStaff() {
        let vm = viewModel(barCount: 3, perBar: 2)
        vm.selectAll()
        XCTAssertEqual(vm.selectedRangePositions.count, 6, "3 bars × 2 events")
        XCTAssertEqual(vm.selectedEventIDs.count, 6, "one id per event, no dupes")
    }

    // MARK: - Range-aware acting

    /// Transposing a range shifts every note in it, and leaves untouched notes outside.
    func testTransposeSelectionShiftsWholeRange() {
        let vm = viewModel(barCount: 1, perBar: 4)   // 60,61,62,63
        vm.extendSelectionForward()
        vm.extendSelectionForward()                  // range covers events 0,1,2
        vm.transposeSelection(semitones: 2)
        let pitches = measures(vm)[0].events.map { $0.pitches.first?.midiNote }
        XCTAssertEqual(pitches, [62, 63, 64, 63], "first three shifted +2, fourth intact")
    }

    /// Deleting a range turns every note in it into a rest of the same duration, and
    /// keeps the events outside the range as notes.
    func testDeleteSelectionRestsWholeRange() {
        let vm = viewModel(barCount: 1, perBar: 4)
        vm.extendSelectionForward()                  // events 0,1
        vm.deleteSelection()
        let isRest = measures(vm)[0].events.map { $0.isRest }
        XCTAssertEqual(isRest, [true, true, false, false], "first two blanked, rest kept")
        XCTAssertFalse(vm.hasRangeSelection, "selection cleared after delete")
    }

    /// A single-focus transpose/delete still works through the range-aware entry points
    /// (no regression for the common one-note case).
    func testSingleFocusStillWorksThroughRangeAPI() {
        let vm = viewModel(barCount: 1, perBar: 4)
        vm.selectedEventIndex = 2
        vm.transposeSelection(semitones: 1)
        XCTAssertEqual(measures(vm)[0].events[2].pitches.first?.midiNote, 63, "only the focus moved")
        XCTAssertEqual(measures(vm)[0].events[0].pitches.first?.midiNote, 60, "others intact")
    }

    // MARK: - Range copy / cut / paste (parity point 3)

    /// Bar 0: four quarters C D E F. Bar 1: a whole rest (the paste target).
    private func copyPasteVM() -> ScoreViewModel {
        let b0 = Measure(events: [
            .note(Pitch.fromMIDI(60), duration: Duration(value: .quarter)),
            .note(Pitch.fromMIDI(62), duration: Duration(value: .quarter)),
            .note(Pitch.fromMIDI(64), duration: Duration(value: .quarter)),
            .note(Pitch.fromMIDI(65), duration: Duration(value: .quarter)),
        ], timeSignature: .fourFour)
        let part = Part(instrument: .flute, measures: [b0, .wholeRest()])
        let score = Score(parts: [part], timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        vm.selectedEventIndex = 0
        return vm
    }

    private func focusEmptyBar1(_ vm: ScoreViewModel) {
        vm.clearRangeAnchor()
        vm.selectedEventIndex = nil
        vm.selectedMeasureIndex = 1
        vm.cursorPosition = 0
    }

    /// Copying a two-note range and pasting into an empty bar reproduces the notes in
    /// order, leaving the originals untouched.
    func testCopyRangePastesDuplicateNotes() {
        let vm = copyPasteVM()
        vm.extendSelectionForward()          // range covers C,D
        vm.copySelection()
        focusEmptyBar1(vm)
        vm.paste()
        let pasted = measures(vm)[1].events.filter { !$0.isRest }.map { $0.pitches.first?.midiNote }
        XCTAssertEqual(Array(pasted.prefix(2)), [60, 62], "pasted C,D in order")
        let originals = measures(vm)[0].events.prefix(2).map { $0.pitches.first?.midiNote }
        XCTAssertEqual(Array(originals), [60, 62], "source notes untouched by copy")
    }

    /// Pasted notes must carry brand-new ids so they never collide with the source
    /// glyphs' Verovio ids (which the selection/highlight resolve by id).
    func testPasteMintsFreshIDs() {
        let vm = copyPasteVM()
        vm.extendSelectionForward()
        let sourceIDs = vm.selectedEventIDs
        vm.copySelection()
        focusEmptyBar1(vm)
        vm.paste()
        let pastedIDs = Set(measures(vm)[1].events.filter { !$0.isRest }.map { $0.id })
        XCTAssertEqual(pastedIDs.count, 2, "two fresh events")
        XCTAssertTrue(sourceIDs.isDisjoint(with: pastedIDs), "no id collision with the source")
    }

    /// Cut blanks the source range to rests, keeps the run on the clipboard, and paste
    /// restores it elsewhere.
    func testCutRangeBlanksOriginalsThenPasteRestores() {
        let vm = copyPasteVM()
        vm.extendSelectionForward()          // C,D
        vm.cutSelection()
        let blanked = measures(vm)[0].events.prefix(2).map { $0.isRest }
        XCTAssertEqual(Array(blanked), [true, true], "cut turns the source range to rests")
        XCTAssertTrue(vm.hasClipboardContent, "clipboard holds the cut run")
        focusEmptyBar1(vm)
        vm.paste()
        let restored = measures(vm)[1].events.filter { !$0.isRest }.map { $0.pitches.first?.midiNote }
        XCTAssertEqual(Array(restored.prefix(2)), [60, 62], "cut run pasted back")
    }
}
