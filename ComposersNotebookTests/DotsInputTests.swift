import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore parity #8 — 3rd and 4th augmentation dots. The model migrated
/// from two bools (`dotted`/`doubleDotted`) to `dots: Int` (0…4). These tests
/// pin the multiplier math, clamping, Codable round-trip (incl. legacy bool
/// documents), MusicXML `<dot/>` emission, and the input-state wrappers so a
/// regression to the old 2-dot ceiling can't slip back in.
@MainActor
final class DotsInputTests: XCTestCase {

    private let eps = 1e-9

    // MARK: - Multiplier math

    func testDotMultiplierMatchesMuseScore() {
        XCTAssertEqual(Duration.dotMultiplier(0), 1.0, accuracy: eps)
        XCTAssertEqual(Duration.dotMultiplier(1), 1.5, accuracy: eps)
        XCTAssertEqual(Duration.dotMultiplier(2), 1.75, accuracy: eps)
        XCTAssertEqual(Duration.dotMultiplier(3), 1.875, accuracy: eps)
        XCTAssertEqual(Duration.dotMultiplier(4), 1.9375, accuracy: eps)
    }

    func testTripleDottedQuarterBeats() {
        let d = Duration(value: .quarter, dots: 3)
        XCTAssertEqual(d.beats, 1.875, accuracy: eps, "1/4 with 3 dots = ×1.875 of a beat")
    }

    func testQuadrupleDottedHalfBeats() {
        let d = Duration(value: .half, dots: 4)
        XCTAssertEqual(d.beats, 2.0 * 1.9375, accuracy: eps, "1/2 with 4 dots = 2 × 1.9375")
    }

    // MARK: - Clamping

    func testDotsClampToZeroFour() {
        XCTAssertEqual(Duration(value: .quarter, dots: 9).dots, 4, "over 4 clamps to 4")
        XCTAssertEqual(Duration(value: .quarter, dots: -3).dots, 0, "negative clamps to 0")
    }

    // MARK: - Codable

    func testCodableRoundTripPreservesThreeDots() throws {
        let d = Duration(value: .eighth, dots: 3, triplet: false)
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Duration.self, from: data)
        XCTAssertEqual(back.dots, 3)
        XCTAssertEqual(back.value, .eighth)
        XCTAssertEqual(back.beats, d.beats, accuracy: eps)
    }

    func testEncodeMirrorsLegacyBoolsForForwardCompat() throws {
        let data = try JSONEncoder().encode(Duration(value: .quarter, dots: 4))
        let json = String(data: data, encoding: .utf8) ?? ""
        // 4 dots still reads as dotted+doubleDotted true for an older reader.
        XCTAssertTrue(json.contains("\"dots\":4"))
        XCTAssertTrue(json.contains("\"dotted\":true"))
        XCTAssertTrue(json.contains("\"doubleDotted\":true"))
    }

    func testDecodeLegacyBoolDocument() throws {
        // Old document with no `dots` field, doubleDotted=true → dots=2.
        let legacy = #"{"value":2,"dotted":true,"doubleDotted":true,"triplet":false}"#
        let d = try JSONDecoder().decode(Duration.self, from: Data(legacy.utf8))
        XCTAssertEqual(d.dots, 2, "legacy double-dot maps to 2 dots")
    }

    func testDecodeLegacySingleDotDocument() throws {
        let legacy = #"{"value":2,"dotted":true,"doubleDotted":false,"triplet":false}"#
        let d = try JSONDecoder().decode(Duration.self, from: Data(legacy.utf8))
        XCTAssertEqual(d.dots, 1)
    }

    // MARK: - MusicXML export

    func testExportEmitsOneDotPerAugmentation() {
        let events: [NoteEvent] = [.note(Pitch(name: .C, octave: 4),
                                          duration: Duration(value: .whole, dots: 3))]
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure(events: events)])])
        let xml = MusicXMLExporter().export(score: score)
        let dotCount = xml.components(separatedBy: "<dot/>").count - 1
        XCTAssertEqual(dotCount, 3, "3-dot note must export exactly three <dot/> elements")
    }

    func testExportFourDots() {
        let events: [NoteEvent] = [.note(Pitch(name: .C, octave: 4),
                                          duration: Duration(value: .whole, dots: 4))]
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure(events: events)])])
        let xml = MusicXMLExporter().export(score: score)
        XCTAssertEqual(xml.components(separatedBy: "<dot/>").count - 1, 4)
    }

    // MARK: - Input-state wrappers (toolbar backs onto dotCount)

    func testViewModelDotCountFlowsToInsertedNote() {
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure.wholeRest()])],
                          timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedDuration = .quarter
        vm.dotCount = 3
        // isDotted/isDoubleDotted are computed views over dotCount.
        XCTAssertTrue(vm.isDotted, "≥1 dot reads as dotted")
        XCTAssertTrue(vm.isDoubleDotted, "≥2 dots reads as doubleDotted")
    }

    func testLegacyIsDottedSetterKeepsHigherDotCount() {
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure.wholeRest()])])
        let vm = ScoreViewModel(score: score)
        vm.dotCount = 3
        vm.isDotted = true            // must not knock 3 dots down to 1
        XCTAssertEqual(vm.dotCount, 3)
        vm.isDotted = false           // false clears all
        XCTAssertEqual(vm.dotCount, 0)
    }
}
