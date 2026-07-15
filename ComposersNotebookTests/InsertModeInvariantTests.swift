import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore Insert-mode parity (Тимур parity point 1): entering a note in
/// insert mode must SHOVE the rest of the staff rightward instead of overwriting,
/// re-flowing the music into full bars — splitting any note that crosses a barline
/// into tied pieces, and growing the staff by however many bars the added time needs.
/// These guard both the pure `Measure.reflow` engine and the `ScoreViewModel.insertEvent`
/// wiring (caret placement, staff-count alignment).
@MainActor
final class InsertModeInvariantTests: XCTestCase {

    private let eps = 1e-6

    private func viewModel(measure: Measure, timeSignature: TimeSignature) -> ScoreViewModel {
        let part = Part(instrument: .flute, measures: [measure])
        let score = Score(parts: [part], timeSignature: timeSignature)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        return vm
    }

    private func measures(_ vm: ScoreViewModel) -> [Measure] {
        vm.score.parts[0].staves[0].measures
    }

    private func sum(_ events: [NoteEvent]) -> Double {
        events.reduce(0.0) { $0 + max(0, $1.actualBeats) }
    }

    // MARK: - reflow engine

    /// A stream shorter than one bar is packed into a single bar padded with rests.
    func testReflowPadsShortStreamToFullBar() {
        let q = { NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter)) }
        let bars = Measure.reflow([q(), q()], totalBeats: 4.0)
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(sum(bars[0]), 4.0, accuracy: eps, "single bar refilled to full")
        XCTAssertEqual(bars[0].prefix(2).filter { !$0.isRest }.count, 2, "both notes kept")
    }

    /// A half note (2 beats) reflowed into 3/8 (1.5-beat) bars must split across the
    /// barline into tied pieces, and the sounding total must be conserved.
    func testReflowSplitsNoteAcrossBarlineWithTie() {
        let half = NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .half))
        let bars = Measure.reflow([half], totalBeats: 1.5)
        XCTAssertEqual(bars.count, 2, "2 beats spills past a 1.5-beat bar")
        for b in bars { XCTAssertEqual(sum(b), 1.5, accuracy: eps, "every bar exactly full") }
        // The note pieces (non-rests) must sum back to the original 2 beats.
        let notePieces = bars.flatMap { $0 }.filter { !$0.isRest }
        XCTAssertEqual(sum(notePieces), 2.0, accuracy: eps, "sounding duration conserved")
        // The last note piece before the barline must tie onward; the very last must not.
        XCTAssertTrue(bars[0].last(where: { !$0.isRest })!.tiedToNext, "tie crosses the barline")
        XCTAssertFalse(notePieces.last!.tiedToNext, "final piece isn't left dangling-tied")
    }

    // MARK: - insertEvent wiring

    /// Inserting a quarter note at the head of a full 4/4 bar (a whole rest) must
    /// grow the staff to 2 bars (the pushed-out rest needs the room), keep the note
    /// first, and leave every bar exactly full.
    func testInsertGrowsStaffAndKeepsBarsFull() {
        let vm = viewModel(measure: .wholeRest(), timeSignature: .fourFour)
        vm.insertMode = true
        vm.cursorPosition = 0

        let note = NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter))
        vm.insertEventShiftingRight(note)

        let ms = measures(vm)
        XCTAssertEqual(ms.count, 2, "one inserted quarter pushes the whole rest into a new bar")
        for m in ms { XCTAssertEqual(sum(m.events), 4.0, accuracy: eps, "bar stays full") }
        XCTAssertFalse(ms[0].events.first!.isRest, "inserted note sits first")
        XCTAssertEqual(ms[0].events.first?.duration.value, .quarter)
    }

    /// Insert must SHIFT, not overwrite: a bar holding a quarter note then rests, with
    /// a quarter inserted at beat 0, must still contain the ORIGINAL note (two notes
    /// now), unlike overwrite which would have replaced it.
    func testInsertShiftsExistingNoteRatherThanOverwriting() {
        let n1 = NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter))
        let fill = Measure.restEvents(fillingBeats: 3.0, startBeat: 1.0)
        let measure = Measure(events: [n1] + fill, timeSignature: .fourFour)
        let vm = viewModel(measure: measure, timeSignature: .fourFour)
        vm.insertMode = true
        vm.cursorPosition = 0

        let note = NoteEvent.note(Pitch(name: .D, octave: 4), duration: Duration(value: .quarter))
        vm.insertEventShiftingRight(note)

        let all = measures(vm).flatMap { $0.events }
        let notes = all.filter { !$0.isRest }
        XCTAssertEqual(notes.count, 2, "original note preserved, not overwritten")
        for m in measures(vm) {
            XCTAssertEqual(sum(m.events), 4.0, accuracy: eps, "every bar full after insert")
        }
    }
}
