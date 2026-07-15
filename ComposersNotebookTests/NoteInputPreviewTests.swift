import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore shadow-note parity (Тимур parity point 4): note-input mode must
/// expose a deterministic preview of what the pen would drop at the cursor — the
/// duration currently on the pen and the vertical position (diatonic steps above the
/// focused staff's middle line) where the head should sit. The view draws the ghost
/// from this descriptor, so testing the descriptor locks the behaviour headless.
@MainActor
final class NoteInputPreviewTests: XCTestCase {

    private func viewModel() -> ScoreViewModel {
        let part = Part(instrument: .flute, measures: [.wholeRest()])
        let score = Score(parts: [part], timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        return vm
    }

    /// Navigate mode shows no shadow — the preview is add-mode only.
    func testNoPreviewInNavigateMode() {
        let vm = viewModel()
        vm.inputMode = .navigate
        XCTAssertNil(vm.noteInputPreview, "navigation must stay uncluttered")
    }

    /// In note mode on an empty staff the shadow previews the pen's duration and
    /// sits on the middle line (steps 0), the clef-reference fallback.
    func testPreviewMirrorsPenDurationAndSitsOnMiddleLineWhenEmpty() {
        let vm = viewModel()
        vm.inputMode = .note
        vm.selectedDuration = .half
        vm.isDotted = true

        let preview = vm.noteInputPreview
        XCTAssertNotNil(preview)
        XCTAssertFalse(preview!.isRest)
        XCTAssertEqual(preview!.duration.value, .half, "pen duration mirrored")
        XCTAssertTrue(preview!.duration.dotted, "pen dot mirrored")
        XCTAssertEqual(preview!.stepsAboveMiddle, 0, "empty staff → middle line")
    }

    /// After entering a note the pen remembers its pitch, so the shadow rides that
    /// line. C5 is one diatonic step above the treble middle line (B4) → steps 1.
    func testPreviewFollowsLastEnteredPitch() {
        let vm = viewModel()
        vm.inputMode = .note
        vm.selectedDuration = .quarter
        vm.insertNoteAtCursor(Pitch(name: .C, octave: 5))

        let preview = vm.noteInputPreview
        XCTAssertNotNil(preview)
        XCTAssertEqual(preview!.stepsAboveMiddle, 1, "shadow rides the last entered pitch (C5 = +1 over B4)")
    }

    /// Rest mode previews a rest anchored on the middle line (steps 0), never a head.
    func testRestModePreviewIsRestOnMiddleLine() {
        let vm = viewModel()
        vm.inputMode = .rest
        vm.selectedDuration = .eighth

        let preview = vm.noteInputPreview
        XCTAssertNotNil(preview)
        XCTAssertTrue(preview!.isRest)
        XCTAssertEqual(preview!.duration.value, .eighth)
        XCTAssertEqual(preview!.stepsAboveMiddle, 0)
    }
}
