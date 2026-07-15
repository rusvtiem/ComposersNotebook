import XCTest
@testable import Composer_s_Notebook

/// Locks M3: a voice's exported `<duration>` values must sum EXACTLY to the bar
/// length. Rounding each tuplet note independently drifts (a 7:4 septuplet of
/// eighths summed to 959 instead of 960 divisions), which shifts Verovio's
/// geometry so taps land off-note. The fix rounds the running offset instead,
/// so the per-note divisions telescope to the exact bar total.
final class TupletTimingTests: XCTestCase {

    private let divisionsPerQuarter = 480
    // 4/4 bar = 4 quarters × 480 divisions.
    private let barDivisions = 4 * 480

    /// Sum every `<duration>N</duration>` in an exported document. For a
    /// single-staff, single-voice part there is no `<backup>`, so this equals the
    /// sounding length of the one measure.
    private func totalDurations(in xml: String) -> Int {
        let regex = try! NSRegularExpression(pattern: "<duration>(\\d+)</duration>")
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        return matches.reduce(0) { acc, m in
            acc + (Int(ns.substring(with: m.range(at: 1))) ?? 0)
        }
    }

    /// A full 4/4 bar: a 7:4 septuplet of eighths (2 beats) followed by real
    /// rests filling the remaining 2 beats.
    private func septupletBarScore() -> Score {
        let group = Tuplet.makeGroup(actualCount: 7, normalCount: 4)
        var events: [NoteEvent] = []
        for i in 0..<7 {
            var e = NoteEvent.note(Pitch(name: .C, octave: 5), duration: Duration(value: .eighth))
            e.tuplet = group[i]
            events.append(e)
        }
        // Fill beats 2..4 with metrically-aligned real rests (a single half rest).
        events.append(contentsOf: Measure.restEvents(fillingBeats: 2.0, startBeat: 2.0))

        let measure = Measure(events: events)
        let part = Part(instrument: .flute, measures: [measure])
        return Score(title: "Septuplet", parts: [part])
    }

    func testSeptupletBarDurationsSumExactlyToBar() {
        let xml = MusicXMLExporter().export(score: septupletBarScore())
        XCTAssertEqual(totalDurations(in: xml), barDivisions,
                       "voice <duration> sum must equal the 4/4 bar (1920), not drift")
    }

    func testSeptupletEmitsTimeModification() {
        let xml = MusicXMLExporter().export(score: septupletBarScore())
        XCTAssertTrue(xml.contains("<time-modification>"), "tuplet needs <time-modification>")
        XCTAssertTrue(xml.contains("<actual-notes>7</actual-notes>"))
        XCTAssertTrue(xml.contains("<normal-notes>4</normal-notes>"))
    }

    func testTripletBarDurationsSumExactlyToBar() {
        // Classic 3:2 eighth triplet = 1 beat; fill the other 3 beats.
        let group = Tuplet.makeGroup(actualCount: 3, normalCount: 2)
        var events: [NoteEvent] = []
        for i in 0..<3 {
            var e = NoteEvent.note(Pitch(name: .G, octave: 4), duration: Duration(value: .eighth))
            e.tuplet = group[i]
            events.append(e)
        }
        events.append(contentsOf: Measure.restEvents(fillingBeats: 3.0, startBeat: 1.0))

        let score = Score(title: "Triplet",
                          parts: [Part(instrument: .flute, measures: [Measure(events: events)])])
        let xml = MusicXMLExporter().export(score: score)
        XCTAssertEqual(totalDurations(in: xml), barDivisions,
                       "eighth triplet + fill must still sum to the full bar")
    }
}
