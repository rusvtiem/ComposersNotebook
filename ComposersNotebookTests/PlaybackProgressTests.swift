import XCTest
@testable import Composer_s_Notebook

/// Locks the playback-cursor schedule: the moving line must track the same timing
/// the player uses, so `PlaybackProgress` maps elapsed seconds to the measure and
/// fraction that are actually sounding. Default score = 4/4 at 120 bpm, so every
/// measure lasts exactly 2.0 s.
final class PlaybackProgressTests: XCTestCase {

    private func score(measures: Int) -> Score {
        let ms = (0..<measures).map { _ in Measure.wholeRest() }
        return Score(parts: [Part(instrument: .flute, measures: ms)])
    }

    func testOnsetsCountMonotonicAndZeroBased() {
        let progress = PlaybackProgress.build(score: score(measures: 3), fromMeasure: 0)
        XCTAssertEqual(progress.measureOnsets.count, 4, "3 measures → 3 onsets + 1 end")
        XCTAssertEqual(progress.measureOnsets.first, 0, "schedule starts at t=0")
        XCTAssertEqual(progress.firstMeasure, 0)
        for i in 1..<progress.measureOnsets.count {
            XCTAssertGreaterThan(progress.measureOnsets[i], progress.measureOnsets[i - 1],
                                 "onsets strictly increase")
        }
    }

    func testMeasureDurationMatchesTempo() {
        // 4/4 @ 120 bpm → 4 beats × 0.5 s/beat = 2.0 s per measure.
        let progress = PlaybackProgress.build(score: score(measures: 2), fromMeasure: 0)
        XCTAssertEqual(progress.measureOnsets, [0, 2, 4])
        XCTAssertEqual(progress.totalDuration, 4, accuracy: 1e-9)
    }

    func testLocateAtStart() {
        let progress = PlaybackProgress.build(score: score(measures: 2), fromMeasure: 0)
        let loc = progress.locate(elapsed: 0)
        XCTAssertEqual(loc?.measure, 0)
        XCTAssertEqual(loc?.fraction ?? -1, 0, accuracy: 1e-9)
    }

    func testLocateMidFirstMeasure() {
        // 1.0 s into a 2.0 s measure = halfway.
        let progress = PlaybackProgress.build(score: score(measures: 2), fromMeasure: 0)
        let loc = progress.locate(elapsed: 1.0)
        XCTAssertEqual(loc?.measure, 0)
        XCTAssertEqual(loc?.fraction ?? -1, 0.5, accuracy: 1e-9)
    }

    func testLocateIntoSecondMeasure() {
        // 2.5 s = 0.5 s into the second (2.0 s) measure = quarter through it.
        let progress = PlaybackProgress.build(score: score(measures: 2), fromMeasure: 0)
        let loc = progress.locate(elapsed: 2.5)
        XCTAssertEqual(loc?.measure, 1)
        XCTAssertEqual(loc?.fraction ?? -1, 0.25, accuracy: 1e-9)
    }

    func testLocateAtOrBeyondEndIsNil() {
        let progress = PlaybackProgress.build(score: score(measures: 2), fromMeasure: 0)
        XCTAssertNil(progress.locate(elapsed: 4.0), "exactly at the end shows no cursor")
        XCTAssertNil(progress.locate(elapsed: 9.0), "past the end shows no cursor")
    }

    func testLocateBeforeStartIsNil() {
        let progress = PlaybackProgress.build(score: score(measures: 2), fromMeasure: 0)
        XCTAssertNil(progress.locate(elapsed: -0.1))
    }

    func testFromMeasureOffsetsGlobalIndex() {
        // Playback started at measure 1 of a 3-measure score: the schedule covers
        // measures 1 and 2, and locate reports the global measure index.
        let progress = PlaybackProgress.build(score: score(measures: 3), fromMeasure: 1)
        XCTAssertEqual(progress.firstMeasure, 1)
        XCTAssertEqual(progress.measureOnsets.count, 3, "2 played measures + 1 end")
        XCTAssertEqual(progress.locate(elapsed: 0)?.measure, 1, "first played measure is global #1")
        XCTAssertEqual(progress.locate(elapsed: 2.5)?.measure, 2, "second played measure is global #2")
    }
}
