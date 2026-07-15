import XCTest
@testable import Composer_s_Notebook

/// Locks core MusicXML export invariants that Verovio depends on: a fixed
/// divisions resolution, exact bar sums for binary durations, non-zero
/// `<duration>` for the shortest notes (a `<duration>0</duration>` makes a note
/// vanish in other readers), and that the exporter reflects the model verbatim
/// rather than inventing measure padding (padding is the model's job).
final class MusicXMLExportTests: XCTestCase {

    private func totalDurations(in xml: String) -> Int {
        let regex = try! NSRegularExpression(pattern: "<duration>(\\d+)</duration>")
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        return matches.reduce(0) { $0 + (Int(ns.substring(with: $1.range(at: 1))) ?? 0) }
    }

    private func durationValues(in xml: String) -> [Int] {
        let regex = try! NSRegularExpression(pattern: "<duration>(\\d+)</duration>")
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
    }

    func testDivisionsHeaderIs480() {
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure.wholeRest()])])
        let xml = MusicXMLExporter().export(score: score)
        XCTAssertTrue(xml.contains("<divisions>480</divisions>"),
                      "divisions must stay 480 so binary + tuplet durations are integers")
    }

    func testBinaryFullBarSumsToBar() {
        // Quarter note on beat 1 + real rests filling beats 2..4.
        var events: [NoteEvent] = [.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter))]
        events.append(contentsOf: Measure.restEvents(fillingBeats: 3.0, startBeat: 1.0))
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure(events: events)])])
        let xml = MusicXMLExporter().export(score: score)
        XCTAssertEqual(totalDurations(in: xml), 4 * 480, "binary bar must sum to 1920 exactly")
    }

    func testShortestNoteHasNonZeroDuration() {
        // A 1024th note must not round to <duration>0</duration> (would disappear).
        let events: [NoteEvent] = [.note(Pitch(name: .C, octave: 4),
                                          duration: Duration(value: .oneThousandTwentyFourth))]
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure(events: events)])])
        let xml = MusicXMLExporter().export(score: score)
        XCTAssertTrue(durationValues(in: xml).allSatisfy { $0 >= 1 },
                      "no exported <duration> may be zero")
    }

    func testExporterDoesNotPadIncompleteMeasure() {
        // A lone quarter note (quarter of a bar) must export exactly one duration
        // of 480 — the exporter mirrors the model, it does not invent fill.
        let events: [NoteEvent] = [.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter))]
        let score = Score(parts: [Part(instrument: .flute, measures: [Measure(events: events)])])
        let xml = MusicXMLExporter().export(score: score)
        XCTAssertEqual(durationValues(in: xml), [480],
                       "incomplete measure exports as-is; padding is the model's responsibility")
    }
}
