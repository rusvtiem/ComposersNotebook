import XCTest
@testable import Composer_s_Notebook

/// Locks the MuseScore "measure is always full of real, individually-selectable
/// rests" invariant — the model root of Тимур's bugs 2 & 3 (rests vanish on note
/// entry; full-measure rest not selectable). If any of these fail, the editor has
/// silently regressed to the pre-fix behaviour.
final class MeasureInvariantTests: XCTestCase {

    private let eps = 1e-6

    // MARK: - restEvents decomposition

    func testRestEventsFillWholeMeasureSumsExactly() {
        let rests = Measure.restEvents(fillingBeats: 4.0, startBeat: 0.0)
        XCTAssertFalse(rests.isEmpty)
        XCTAssertTrue(rests.allSatisfy { $0.isRest }, "fill must be all rests")
        let sum = rests.reduce(0.0) { $0 + $1.actualBeats }
        XCTAssertEqual(sum, 4.0, accuracy: eps)
    }

    func testRestEventsRespectMetricAlignment() {
        // A rest of length L must begin on a multiple of L. Filling 3 beats from
        // beat 1 must not produce a single dotted-half-spanning rest across the
        // strong beat-2 boundary; the decomposition stays readable and sums right.
        let rests = Measure.restEvents(fillingBeats: 3.0, startBeat: 1.0)
        let sum = rests.reduce(0.0) { $0 + $1.actualBeats }
        XCTAssertEqual(sum, 3.0, accuracy: eps)
        XCTAssertTrue(rests.allSatisfy { $0.isRest })
        // No half-rest may start on the off-beat (tick 16 = beat 1): the first
        // rest can be at most a quarter until we reach beat 2.
        XCTAssertEqual(rests.first?.duration.value, .quarter)
    }

    func testRestEventsFractionalTailRoundsToGrid() {
        // A tuplet/dotted remainder shorter than a tick is dropped, never negative.
        let rests = Measure.restEvents(fillingBeats: 0.0, startBeat: 0.0)
        XCTAssertTrue(rests.isEmpty)
    }

    // MARK: - overwrite keeps the measure exactly full

    func testOverwriteQuarterAtStartRefillsRemainder() {
        let start = [NoteEvent.rest(duration: .wholeNote)]
        let note = NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter))
        let result = Measure.overwrite(start, with: note, atBeat: 0.0, totalBeats: 4.0)

        let sum = result.reduce(0.0) { $0 + $1.actualBeats }
        XCTAssertEqual(sum, 4.0, accuracy: eps, "measure must stay exactly full")
        XCTAssertGreaterThanOrEqual(result.count, 2, "note + real fill rests")
        XCTAssertFalse(result[0].isRest, "the entered note comes first")
        XCTAssertTrue(result.dropFirst().allSatisfy { $0.isRest },
                      "everything after the note is real, selectable rests — not empty")
    }

    func testOverwriteInMiddlePreservesHeadAndTail() {
        let start = [NoteEvent.rest(duration: .wholeNote)]
        let note = NoteEvent.note(Pitch(name: .G, octave: 4), duration: Duration(value: .half))
        // Place a half note starting at beat 2 of a 4/4 measure.
        let result = Measure.overwrite(start, with: note, atBeat: 2.0, totalBeats: 4.0)

        let sum = result.reduce(0.0) { $0 + $1.actualBeats }
        XCTAssertEqual(sum, 4.0, accuracy: eps)
        // Exactly one non-rest (the half note); head (beats 0..2) is filled by rests.
        XCTAssertEqual(result.filter { !$0.isRest }.count, 1)
        let noteBeatsBefore = result.prefix { $0.isRest }.reduce(0.0) { $0 + $1.actualBeats }
        XCTAssertEqual(noteBeatsBefore, 2.0, accuracy: eps, "note lands on beat 2")
    }

    func testOverwriteNeverLeavesMeasureEmpty() {
        // Even overwriting the whole measure with a whole note keeps it full and
        // never yields an empty events array (which would render as nothing).
        let start = [NoteEvent.rest(duration: .wholeNote)]
        let note = NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .whole))
        let result = Measure.overwrite(start, with: note, atBeat: 0.0, totalBeats: 4.0)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.reduce(0.0) { $0 + $1.actualBeats }, 4.0, accuracy: eps)
    }
}
