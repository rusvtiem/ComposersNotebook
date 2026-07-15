import XCTest
@testable import Composer_s_Notebook

/// Locks MuseScore custom-tuplet parity (Тимур parity point 5): a free ratio from
/// the "Other…" dialog, plus bracket/number display choices, applied as a group and
/// round-tripped through MusicXML so Verovio engraves the chosen bracket/number.
@MainActor
final class CustomTupletTests: XCTestCase {

    private func viewModel(eighths: Int) -> ScoreViewModel {
        let events = (0..<eighths).map { _ in
            NoteEvent.note(Pitch(name: .C, octave: 5, accidental: .natural),
                           duration: Duration(value: .eighth))
        }
        let measure = Measure(events: events, timeSignature: .fourFour)
        let part = Part(instrument: .flute, measures: [measure])
        let score = Score(parts: [part], timeSignature: .fourFour)
        let vm = ScoreViewModel(score: score)
        vm.selectedPartIndex = 0
        vm.selectedStaffIndex = 0
        vm.selectedMeasureIndex = 0
        vm.selectedEventIndex = 0
        return vm
    }

    private func groupTuplets(_ vm: ScoreViewModel) -> [Tuplet] {
        vm.score.parts[0].staves[0].measures[0].events.compactMap { $0.tuplet }
    }

    // MARK: - Ratio validation

    func testRatioNeedsAtLeastTwoActual() {
        XCTAssertNil(ScoreViewModel.normalizedTupletRatio(actual: 1, normal: 2), "1-note tuplet is nonsense")
        XCTAssertNotNil(ScoreViewModel.normalizedTupletRatio(actual: 2, normal: 3))
    }

    func testRatioClampsToCeiling() {
        let r = ScoreViewModel.normalizedTupletRatio(actual: 500, normal: 0)
        XCTAssertEqual(r?.actual, 99, "actual capped")
        XCTAssertEqual(r?.normal, 1, "normal floored to 1")
    }

    // MARK: - Apply custom ratio

    func testApplyCustomRatioTagsWholeGroup() {
        let vm = viewModel(eighths: 5)
        vm.applyTupletGroupStartingAtSelected(actualCount: 5, normalCount: 4,
                                              bracket: .shown, numberStyle: .ratio)
        let tuplets = groupTuplets(vm)
        XCTAssertEqual(tuplets.count, 5, "all five eighths joined the quintuplet")
        XCTAssertTrue(tuplets.allSatisfy { $0.actualCount == 5 && $0.normalCount == 4 })
        XCTAssertEqual(Set(tuplets.map(\.groupID)).count, 1, "one shared group id")
        XCTAssertTrue(tuplets.allSatisfy { $0.bracket == .shown && $0.numberStyle == .ratio })
    }

    // MARK: - Change display only

    func testDisplayChangeLeavesRatioIntact() {
        let vm = viewModel(eighths: 3)
        vm.applyTupletGroupStartingAtSelected(actualCount: 3, normalCount: 2)
        vm.setTupletDisplayForSelectedGroup(bracket: .hidden, numberStyle: .noNumber)
        let tuplets = groupTuplets(vm)
        XCTAssertTrue(tuplets.allSatisfy { $0.actualCount == 3 && $0.normalCount == 2 }, "ratio untouched")
        XCTAssertTrue(tuplets.allSatisfy { $0.bracket == .hidden && $0.numberStyle == .noNumber })
    }

    // MARK: - displayLabel honours the number style

    func testDisplayLabelRespectsNumberStyle() {
        func t(_ n: TupletNumberStyle?) -> Tuplet {
            Tuplet(actualCount: 3, normalCount: 2, numberStyle: n)
        }
        XCTAssertEqual(t(.noNumber).displayLabel, "")
        XCTAssertEqual(t(.ratio).displayLabel, "3:2")
        XCTAssertEqual(t(.count).displayLabel, "3")
        XCTAssertEqual(t(nil).displayLabel, "3", "auto keeps classic 3:2 as just 3")
    }

    // MARK: - MusicXML carries the display choices

    func testExportEmitsBracketAndShowNumber() {
        let vm = viewModel(eighths: 3)
        vm.applyTupletGroupStartingAtSelected(actualCount: 3, normalCount: 2,
                                              bracket: .shown, numberStyle: .ratio)
        let xml = MusicXMLExporter().export(score: vm.score, colorizeVoices: false)
        XCTAssertTrue(xml.contains("type=\"start\""), "tuplet start emitted")
        XCTAssertTrue(xml.contains("bracket=\"yes\""), "shown bracket exported")
        XCTAssertTrue(xml.contains("show-number=\"both\""), "ratio number exported")
    }
}
