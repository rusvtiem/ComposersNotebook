import XCTest
@testable import Composer_s_Notebook

/// Locks Тимур's bug 1: playback sound must stay locked to the on-screen cursor.
/// The cursor reads `PlaybackProgress` (absolute measure onsets vs. a fixed start
/// instant); the sound must ride the SAME timeline. `buildNoteSchedule` gives every
/// note an absolute onset with the identical tempo/time-signature resolution
/// `PlaybackProgress.build` uses, so the two can't drift. These tests fail if the
/// scheduler regresses to cumulative per-note sleeps (which slid the sound late).
final class NoteScheduleTimingTests: XCTestCase {

    private let eps = 1e-9

    private func quarterNotesMeasure() -> Measure {
        let notes = (0..<4).map { _ in
            NoteEvent.note(Pitch(name: .C, octave: 4), duration: Duration(value: .quarter))
        }
        return Measure(events: notes, timeSignature: .fourFour)
    }

    private func score(measures: Int) -> Score {
        let ms = (0..<measures).map { _ in quarterNotesMeasure() }
        return Score(parts: [Part(instrument: .flute, measures: ms)])
    }

    /// 4/4 @ 120 bpm → 0.5 s/beat. Four quarters land at 0, 0.5, 1.0, 1.5; the second
    /// measure's quarters continue at 2.0, 2.5, 3.0, 3.5.
    func testQuarterNoteOnsetsAreAbsoluteAndEvenlySpaced() {
        let schedule = MIDIEngine.buildNoteSchedule(score: score(measures: 2), fromMeasure: 0)
        XCTAssertEqual(schedule.count, 8, "8 quarter notes across 2 measures")
        let onsets = schedule.map(\.onset)
        let expected: [Double] = [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
        for (got, want) in zip(onsets, expected) {
            XCTAssertEqual(got, want, accuracy: eps)
        }
        for n in schedule {
            XCTAssertEqual(n.durationSec, 0.5, accuracy: eps, "quarter @ 120 bpm sounds 0.5 s")
        }
    }

    func testOnsetsAreNonDecreasing() {
        let schedule = MIDIEngine.buildNoteSchedule(score: score(measures: 3), fromMeasure: 0)
        for i in 1..<schedule.count {
            XCTAssertGreaterThanOrEqual(schedule[i].onset, schedule[i - 1].onset,
                                        "onsets never go backwards")
        }
    }

    /// The crux of the desync fix: the first note of each measure must sit exactly on
    /// that measure's cursor onset. If these diverge, sound and ползунок drift apart.
    func testMeasureBoundariesMatchPlaybackCursorOnsets() {
        let s = score(measures: 3)
        let schedule = MIDIEngine.buildNoteSchedule(score: s, fromMeasure: 0)
        let progress = PlaybackProgress.build(score: s, fromMeasure: 0)
        // measureOnsets = [0, 2, 4, 6]; each measure's first quarter is at index 0,4,8.
        for measureIndex in 0..<3 {
            let firstNoteOnset = schedule[measureIndex * 4].onset
            XCTAssertEqual(firstNoteOnset, progress.measureOnsets[measureIndex], accuracy: eps,
                           "measure \(measureIndex) sound onset == cursor onset")
        }
    }

    /// Starting mid-score: onsets are still measured from t=0 of playback (the note
    /// that starts sounding is the first of `fromMeasure`), matching the cursor which
    /// also rebases at `fromMeasure`.
    func testFromMeasureRebasesToZero() {
        let s = score(measures: 3)
        let schedule = MIDIEngine.buildNoteSchedule(score: s, fromMeasure: 1)
        XCTAssertEqual(schedule.count, 8, "measures 1 and 2 only")
        XCTAssertEqual(schedule.first?.onset ?? -1, 0, accuracy: eps, "first played note at t=0")
    }

    /// An all-rest score yields no notes to sound — the player then just sweeps the
    /// cursor to the end. The empty schedule is the signal for that path.
    func testAllRestScoreProducesEmptySchedule() {
        let rests = (0..<2).map { _ in Measure.wholeRest() }
        let s = Score(parts: [Part(instrument: .flute, measures: rests)])
        let schedule = MIDIEngine.buildNoteSchedule(score: s, fromMeasure: 0)
        XCTAssertTrue(schedule.isEmpty, "rests make no sound")
    }
}
