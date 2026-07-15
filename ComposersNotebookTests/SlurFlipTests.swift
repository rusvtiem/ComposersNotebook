import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore "X on a slur" parity (Тимур parity point 6): flipping a selected
/// slur's arc above/below, round-tripped through MusicXML so Verovio engraves the
/// chosen placement. Stem flip (X on a note) already existed; this covers the slur leg.
@MainActor
final class SlurFlipTests: XCTestCase {

    private func viewModel(slurOnFirst: Bool) -> ScoreViewModel {
        var first = NoteEvent.note(Pitch(name: .C, octave: 5, accidental: .natural),
                                   duration: Duration(value: .quarter))
        first.slurStart = slurOnFirst
        let second = NoteEvent.note(Pitch(name: .D, octave: 5, accidental: .natural),
                                    duration: Duration(value: .quarter))
        let measure = Measure(events: [first, second], timeSignature: .fourFour)
        let part = Part(instrument: .flute, measures: [measure])
        let score = Score(parts: [part], timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        vm.selectedEventIndex = 0
        return vm
    }

    private func firstPlacement(_ vm: ScoreViewModel) -> SlurPlacement? {
        vm.score.parts[0].staves[0].measures[0].events[0].slurPlacement
    }

    func testFlipCyclesAutoAboveBelow() {
        let vm = viewModel(slurOnFirst: true)
        XCTAssertNil(firstPlacement(vm), "starts on auto")
        vm.flipSelectedSlurPlacement()
        XCTAssertEqual(firstPlacement(vm), .above)
        vm.flipSelectedSlurPlacement()
        XCTAssertEqual(firstPlacement(vm), .below)
        vm.flipSelectedSlurPlacement()
        XCTAssertNil(firstPlacement(vm), "cycles back to auto")
    }

    func testFlipIsNoOpWithoutSlur() {
        let vm = viewModel(slurOnFirst: false)
        vm.flipSelectedSlurPlacement()
        XCTAssertNil(firstPlacement(vm), "nothing to flip on a note without a slur")
    }

    func testExportEmitsPlacementWhenFlipped() {
        let vm = viewModel(slurOnFirst: true)
        vm.flipSelectedSlurPlacement()  // -> above
        let xml = MusicXMLExporter().export(score: vm.score, colorizeVoices: false)
        XCTAssertTrue(xml.contains("<slur type=\"start\" placement=\"above\"/>"),
                      "flipped slur carries placement")
    }

    func testExportOmitsPlacementWhenAuto() {
        let vm = viewModel(slurOnFirst: true)
        let xml = MusicXMLExporter().export(score: vm.score, colorizeVoices: false)
        XCTAssertTrue(xml.contains("<slur type=\"start\"/>"), "auto slur stays attribute-free")
        // Assert on the slur element specifically — `placement` is a common attribute
        // used by other elements (e.g. <direction>), so a bare substring is too broad.
        XCTAssertFalse(xml.contains("<slur type=\"start\" placement="),
                       "auto slur carries no placement attribute")
    }

    func testSlurPlacementSurvivesFreshID() {
        var e = NoteEvent.note(Pitch(name: .C, octave: 5, accidental: .natural),
                               duration: Duration(value: .quarter))
        e.slurStart = true
        e.slurPlacement = .below
        let twin = e.withFreshID()
        XCTAssertEqual(twin.slurPlacement, .below, "paste keeps the flipped arc")
        XCTAssertNotEqual(twin.id, e.id, "but gets a fresh identity")
    }
}
