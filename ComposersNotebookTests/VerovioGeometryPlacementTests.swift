import XCTest
import CoreGraphics
@testable import Composer_s_Notebook

/// Locks where the note-input caret lands — the root of Тимур's "Уже сразу косяк"
/// (the caret band parked at the far left over the treble clef instead of on beat 1).
///
/// MuseScore parks its note-input caret on the insertion beat: for an empty measure
/// that carries clef/key/time, beat 1 sits just past those leading glyphs, NOT at the
/// staff's left edge. `insertionColumn` must reproduce that, and must span the whole
/// system (both staves of a grand staff).
///
/// The fixture is a hand-built SVG shaped exactly like Verovio's output for an empty
/// two-measure 4/4 piano score (page-margin translate(500,500), viewBox origin 0,0,
/// staffSpace 180). Coordinates were read from a real `verovio` render:
///   measure 0 carries clef(1627) + meterSig(2294); real beat-1 notehead x = 2856.
///   measure 1 is a bare interior measure (no clef/meter), staff span 4600…5800.
/// All raw coords fold by +500 (margin) − 0 (viewBox origin).
final class VerovioGeometryPlacementTests: XCTestCase {

    private let margin: CGFloat = 500

    /// clef + meterSig, then a centred mRest — Verovio's first measure of an empty score.
    private func emptyPianoSVG() -> String {
        """
        <svg width="1050px" height="1485px" viewBox="0 0 21000 29700" xmlns="http://www.w3.org/2000/svg">
        <g class="page-margin" transform="translate(500, 500)">
          <g id="measa" class="measure">
            <g id="stfa" class="staff">
              <path d="M1510 540 L4369 540" stroke-width="13"/>
              <path d="M1510 720 L4369 720" stroke-width="13"/>
              <path d="M1510 900 L4369 900" stroke-width="13"/>
              <path d="M1510 1080 L4369 1080" stroke-width="13"/>
              <path d="M1510 1260 L4369 1260" stroke-width="13"/>
              <g id="clfa" class="clef"><use xlink:href="#E050" x="0" y="0" height="720px" width="720px" transform="translate(1627, 1080) scale(0.72,0.72)"/></g>
              <g id="msa" class="meterSig"><use xlink:href="#E084" x="0" y="0" height="720px" width="720px" transform="translate(2294, 720) scale(0.72,0.72)"/><use xlink:href="#E084" transform="translate(2294, 1080) scale(0.72,0.72)"/></g>
              <g id="mra" class="mRest"><use xlink:href="#E4E1" x="0" y="0" height="720px" width="720px" transform="translate(3401, 720) scale(0.72,0.72)"/></g>
            </g>
            <g id="stfb" class="staff">
              <path d="M1510 2340 L4369 2340" stroke-width="13"/>
              <path d="M1510 2520 L4369 2520" stroke-width="13"/>
              <path d="M1510 2700 L4369 2700" stroke-width="13"/>
              <path d="M1510 2880 L4369 2880" stroke-width="13"/>
              <path d="M1510 3060 L4369 3060" stroke-width="13"/>
              <g id="clfb" class="clef"><use xlink:href="#E062" x="0" y="0" height="720px" width="720px" transform="translate(1627, 2520) scale(0.72,0.72)"/></g>
              <g id="msb" class="meterSig"><use xlink:href="#E084" x="0" y="0" height="720px" width="720px" transform="translate(2294, 2520) scale(0.72,0.72)"/></g>
              <g id="mrb" class="mRest"><use xlink:href="#E4E1" x="0" y="0" height="720px" width="720px" transform="translate(3401, 2520) scale(0.72,0.72)"/></g>
            </g>
          </g>
          <g id="measb" class="measure">
            <g id="stfc" class="staff">
              <path d="M4600 540 L5800 540" stroke-width="13"/>
              <path d="M4600 720 L5800 720" stroke-width="13"/>
              <path d="M4600 900 L5800 900" stroke-width="13"/>
              <path d="M4600 1080 L5800 1080" stroke-width="13"/>
              <path d="M4600 1260 L5800 1260" stroke-width="13"/>
              <g id="mrc" class="mRest"><use xlink:href="#E4E1" x="0" y="0" height="720px" width="720px" transform="translate(5100, 720) scale(0.72,0.72)"/></g>
            </g>
            <g id="stfd" class="staff">
              <path d="M4600 2340 L5800 2340" stroke-width="13"/>
              <path d="M4600 2520 L5800 2520" stroke-width="13"/>
              <path d="M4600 2700 L5800 2700" stroke-width="13"/>
              <path d="M4600 2880 L5800 2880" stroke-width="13"/>
              <path d="M4600 3060 L5800 3060" stroke-width="13"/>
              <g id="mrd" class="mRest"><use xlink:href="#E4E1" x="0" y="0" height="720px" width="720px" transform="translate(5100, 2520) scale(0.72,0.72)"/></g>
            </g>
          </g>
        </g>
        </svg>
        """
    }

    func testParsesTwoMeasuresEachWithTwoStaves() {
        guard let geo = VerovioSVGGeometry.parse(emptyPianoSVG()) else {
            return XCTFail("fixture failed to parse")
        }
        XCTAssertEqual(geo.measures.count, 2)
        XCTAssertEqual(geo.measures[0].staves.count, 2)
        XCTAssertEqual(geo.measures[1].staves.count, 2)
    }

    /// The bug: caret sat at the left edge (over the clef). It must sit on beat 1,
    /// which for a clef+meter measure is a few staff-spaces past the meterSig — right
    /// of the clef, and left of the centred full-measure rest.
    func testCaretOnBeatOneOfFirstMeasureNotAtLeftEdge() {
        guard let geo = VerovioSVGGeometry.parse(emptyPianoSVG()),
              let caret = geo.insertionColumn(measureIndex: 0, staffInMeasure: 0) else {
            return XCTFail("no caret")
        }
        // meterSig folds to 2294+500 = 2794; beat 1 = 2794 + 3.1*180 = 3352.
        XCTAssertEqual(caret.x, 3352, accuracy: 1, "caret must sit on beat 1, not the left edge")

        let clefRight = 1627 + margin        // 2127
        let mRestCentre = 3401 + margin      // 3901
        XCTAssertGreaterThan(caret.x, clefRight, "caret must be right of the clef")
        XCTAssertLessThan(caret.x, mRestCentre, "caret must be left of the centred full-measure rest")

        // Within ~half a staff-space of the real notehead position (2856+500 = 3356).
        XCTAssertEqual(caret.x, 3356, accuracy: 90, "caret ≈ real beat-1 notehead x")
    }

    /// A bare interior measure carries no clef/meter and no notes. Verovio renders it
    /// compact, so the true 1-sp beat-1 point would hug the barline; the caret instead
    /// sits on the centred whole-rest (the measure's drawn content), clearing the
    /// barline — the fix for Тимур's "опять косяк" (caret glued to the barline).
    func testCaretOnWholeRestOfInteriorMeasureNotHuggingBarline() {
        guard let geo = VerovioSVGGeometry.parse(emptyPianoSVG()),
              let caret = geo.insertionColumn(measureIndex: 1, staffInMeasure: 0) else {
            return XCTFail("no caret")
        }
        // mRest folds to 5100+500 = 5600 (staff span 5100…6300, so it clears the barline).
        XCTAssertEqual(caret.x, 5600, accuracy: 1, "caret sits on the whole-rest")
        let barline = 4600 + margin  // 5100
        XCTAssertGreaterThan(caret.x - caret.width / 2, barline + 180,
                             "caret must clear the barline by more than a staff-space, not hug it")
        XCTAssertLessThan(caret.x, 5800 + margin, "still inside the measure span")
    }

    /// The band spans the whole system: from above the top staff's first line to
    /// below the bottom staff's last line — on a grand staff it crosses both staves.
    func testCaretBandSpansBothStaves() {
        guard let geo = VerovioSVGGeometry.parse(emptyPianoSVG()),
              let caret = geo.insertionColumn(measureIndex: 0, staffInMeasure: 0) else {
            return XCTFail("no caret")
        }
        let topStaffFirstLine = 540 + margin     // 1040
        let bottomStaffLastLine = 3060 + margin  // 3560
        XCTAssertLessThan(caret.top, topStaffFirstLine, "band starts above the treble staff")
        XCTAssertGreaterThan(caret.bottom, bottomStaffLastLine, "band ends below the bass staff")
        XCTAssertGreaterThan(caret.width, 0)
    }

    func testCaretNilForOutOfRangeIndices() {
        guard let geo = VerovioSVGGeometry.parse(emptyPianoSVG()) else {
            return XCTFail("fixture failed to parse")
        }
        XCTAssertNil(geo.insertionColumn(measureIndex: 5, staffInMeasure: 0))
        XCTAssertNil(geo.insertionColumn(measureIndex: 0, staffInMeasure: 9))
    }
}
