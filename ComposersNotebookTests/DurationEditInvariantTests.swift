import XCTest
@testable import Composer_s_Notebook

/// Locks Тимур's bug 2: editing a rest/note's duration must keep the measure exactly
/// full. Shrinking a 1/4 rest to 1/8 must refill the freed 1/8 (it can't just vanish);
/// growing a rest past the room to the barline must clamp to what fits (a 1/4 must not
/// appear where only a 1/8 remained). `updateSelectedEventDuration` routes through
/// `Measure.overwrite`, so these assertions guard against a regression to in-place
/// `duration.value` mutation that left the bar short or over-full.
@MainActor
final class DurationEditInvariantTests: XCTestCase {

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

    private func events(_ vm: ScoreViewModel) -> [NoteEvent] {
        vm.score.parts[0].staves[0].measures[0].events
    }

    private func sum(_ events: [NoteEvent]) -> Double {
        events.reduce(0.0) { $0 + max(0, $1.actualBeats) }
    }

    // MARK: - Shrink refills the freed time

    /// A lone 1/4 rest in a 4/4 measure, shrunk to 1/8: the measure must still sum to
    /// 4.0 — the freed 7/8 (the shrink plus the original 3 empty beats) refills with
    /// real, selectable rests, none of them vanishing.
    func testShrinkingRestRefillsMeasure() {
        // 4/4 measure whose first event is a quarter rest, then real fill to 4 beats.
        let quarterRest = NoteEvent.rest(duration: Duration(value: .quarter))
        let fill = Measure.restEvents(fillingBeats: 3.0, startBeat: 1.0)
        let measure = Measure(events: [quarterRest] + fill, timeSignature: .fourFour)
        let vm = viewModel(measure: measure, timeSignature: .fourFour)
        vm.selectedEventIndex = 0

        vm.updateSelectedEventDuration(.eighth)

        let out = events(vm)
        XCTAssertEqual(sum(out), 4.0, accuracy: eps, "measure stays exactly full after shrink")
        XCTAssertTrue(out.allSatisfy { $0.isRest }, "all still rests")
        XCTAssertEqual(out.first?.duration.value, .eighth, "the edited rest is now 1/8")
        XCTAssertGreaterThan(out.count, 1, "freed time refilled with real rests, not gone")
    }

    // MARK: - Grow clamps to the barline

    /// 3/8 measure = two 1/8 notes then a 1/8 rest. Selecting the trailing 1/8 rest and
    /// pressing 1/4 must NOT produce a 1/4 (there's only 1/8 of room): it clamps to the
    /// largest value that fits — a 1/8 — so nothing spills past the barline. This is the
    /// exact scenario Тимур described ("как она там появилась, если осталось только 1/8?").
    func testGrowingRestPastBarlineClampsToFit() {
        let n1 = NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .eighth))
        let n2 = NoteEvent.note(Pitch(name: .D, octave: 4), duration: Duration(value: .eighth))
        let rest = NoteEvent.rest(duration: Duration(value: .eighth))
        let measure = Measure(events: [n1, n2, rest], timeSignature: .threeeEight)
        let vm = viewModel(measure: measure, timeSignature: .threeeEight)
        vm.selectedEventIndex = 2

        vm.updateSelectedEventDuration(.quarter)

        let out = events(vm)
        XCTAssertEqual(sum(out), 1.5, accuracy: eps, "3/8 measure stays exactly full, no overflow")
        // The two notes survive untouched; the last event is still a 1/8 (clamped), a rest.
        XCTAssertEqual(out.filter { !$0.isRest }.count, 2, "both notes preserved")
        XCTAssertLessThanOrEqual(out.last!.actualBeats, 0.5 + eps, "grown rest clamped to the 1/8 that fit")
    }

    /// Growing a rest that DOES have room behaves normally: a 1/4 rest at beat 0 of a
    /// 4/4 measure grown to 1/2 becomes a half rest and the tail refills — sum stays 4.
    func testGrowingRestWithinRoomExpands() {
        let quarterRest = NoteEvent.rest(duration: Duration(value: .quarter))
        let fill = Measure.restEvents(fillingBeats: 3.0, startBeat: 1.0)
        let measure = Measure(events: [quarterRest] + fill, timeSignature: .fourFour)
        let vm = viewModel(measure: measure, timeSignature: .fourFour)
        vm.selectedEventIndex = 0

        vm.updateSelectedEventDuration(.half)

        let out = events(vm)
        XCTAssertEqual(sum(out), 4.0, accuracy: eps)
        XCTAssertEqual(out.first?.duration.value, .half, "rest grew to 1/2 (room allowed it)")
    }
}
