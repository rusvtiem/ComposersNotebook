import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore parity #7 — Rhythm input mode. A tap in `.rhythm` mode lays
/// down a note of the current duration (incl. dots) at the last entered pitch,
/// ignoring where on the staff the finger landed, so the composer taps out a
/// rhythm and re-pitches later. These tests pin: entry only fires in rhythm
/// mode, the default pitch on an empty staff is the clef's middle line, a run of
/// taps reuses the previous pitch, and the selected duration/dots carry through.
@MainActor
final class RhythmInputTests: XCTestCase {

    private func viewModel() -> ScoreViewModel {
        let part = Part(instrument: .flute, measures: [Measure.wholeRest()])
        let score = Score(parts: [part], timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        return vm
    }

    private func notes(_ vm: ScoreViewModel) -> [NoteEvent] {
        vm.score.parts[0].staves[0].measures[0].events.filter { !$0.isRest }
    }

    func testRhythmTapIsNoOpOutsideRhythmMode() {
        let vm = viewModel()
        vm.inputMode = .note        // wrong mode
        vm.addRhythmNote()
        XCTAssertTrue(notes(vm).isEmpty, "addRhythmNote must do nothing unless in .rhythm mode")
    }

    func testFirstRhythmTapUsesClefMiddleLine() {
        let vm = viewModel()
        vm.inputMode = .rhythm
        vm.selectedDuration = .quarter
        vm.addRhythmNote()
        let out = notes(vm)
        XCTAssertEqual(out.count, 1, "one note entered")
        // Treble middle line = B4 (Clef.treble.referencePitch).
        XCTAssertEqual(out.first?.pitches.first?.name, .B)
        XCTAssertEqual(out.first?.pitches.first?.octave, 4)
        XCTAssertEqual(out.first?.duration.value, .quarter)
    }

    func testRunOfTapsReusesPreviousPitch() {
        let vm = viewModel()
        vm.inputMode = .rhythm
        vm.selectedDuration = .eighth
        vm.addRhythmNote()
        vm.addRhythmNote()
        vm.addRhythmNote()
        let out = notes(vm)
        XCTAssertEqual(out.count, 3, "three notes laid down")
        let pitches = out.compactMap { $0.pitches.first }
        XCTAssertEqual(Set(pitches.map { "\($0.name)\($0.octave)" }).count, 1,
                       "rhythm mode keeps the same pitch across a run")
    }

    func testRhythmRespectsSelectedDurationAndDots() {
        let vm = viewModel()
        vm.inputMode = .rhythm
        vm.selectedDuration = .eighth
        vm.dotCount = 1                 // dotted eighth
        vm.addRhythmNote()
        let first = notes(vm).first
        XCTAssertEqual(first?.duration.value, .eighth)
        XCTAssertEqual(first?.duration.dots, 1, "current dot count flows into the rhythm note")
    }

    func testRhythmModeIsDistinctInputMode() {
        // Guards the toolbar toggle: entering rhythm mode is not the same as note/navigate.
        XCTAssertNotEqual(InputMode.rhythm, .note)
        XCTAssertNotEqual(InputMode.rhythm, .navigate)
    }
}
