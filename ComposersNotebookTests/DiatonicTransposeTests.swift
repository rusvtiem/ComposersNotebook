import XCTest
@testable import Composer_s_Notebook

/// Locks M1: diatonic transposition must follow the key signature's spelling,
/// not a hard-coded C-major scale. Previously "Диат↑/↓" always spelled naturals.
@MainActor
final class DiatonicTransposeTests: XCTestCase {

    func testStepUpInCMajorIsNatural() {
        let c4 = Pitch(name: .C, octave: 4)
        let up = ScoreViewModel.diatonicShift(c4, steps: 1, key: .cMajor)
        XCTAssertEqual(up.name, .D)
        XCTAssertEqual(up.octave, 4)
        XCTAssertEqual(up.accidental, .natural)
    }

    func testStepDownCrossesBarlineOfOctave() {
        let c4 = Pitch(name: .C, octave: 4)
        let down = ScoreViewModel.diatonicShift(c4, steps: -1, key: .cMajor)
        XCTAssertEqual(down.name, .B)
        XCTAssertEqual(down.octave, 3, "stepping below C4 lands on B3")
    }

    func testStepUpCrossesIntoNextOctave() {
        let b4 = Pitch(name: .B, octave: 4)
        let up = ScoreViewModel.diatonicShift(b4, steps: 1, key: .cMajor)
        XCTAssertEqual(up.name, .C)
        XCTAssertEqual(up.octave, 5)
    }

    func testLandingNoteSpelledByKeyGMajor() {
        // G major (fifths +1) sharpens F. Stepping E4 up one degree lands on F,
        // which the key must spell as F♯ — not F natural.
        let e4 = Pitch(name: .E, octave: 4)
        let up = ScoreViewModel.diatonicShift(e4, steps: 1, key: KeySignature(fifths: 1, mode: .major))
        XCTAssertEqual(up.name, .F)
        XCTAssertEqual(up.accidental, .sharp, "F in G major is F♯")
    }

    func testLandingNoteSpelledByKeyFMajor() {
        // F major (fifths -1) flattens B. Stepping A4 up one degree lands on B → B♭.
        let a4 = Pitch(name: .A, octave: 4)
        let up = ScoreViewModel.diatonicShift(a4, steps: 1, key: KeySignature(fifths: -1, mode: .major))
        XCTAssertEqual(up.name, .B)
        XCTAssertEqual(up.accidental, .flat, "B in F major is B♭")
    }

    func testZeroStepsIsIdentityLetter() {
        let f4 = Pitch(name: .F, octave: 4, accidental: .sharp)
        let same = ScoreViewModel.diatonicShift(f4, steps: 0, key: .cMajor)
        XCTAssertEqual(same.name, .F)
        XCTAssertEqual(same.octave, 4)
    }
}
