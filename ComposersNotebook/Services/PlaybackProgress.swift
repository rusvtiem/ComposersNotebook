import Foundation

/// Time→position schedule for the playback cursor (the moving vertical line that
/// sweeps the score during Play, like a video scrubber — MuseScore's playback
/// cursor, distinct from the note-input caret).
///
/// Built once when playback starts, it holds the wall-clock onset (seconds from
/// the start of playback) of every played measure. The view samples `locate` on
/// each animation frame to get the current measure and how far through it the
/// music is, then maps that to an x on the engraved page.
///
/// The schedule mirrors `MIDIEngine.playScore` exactly (same per-measure tempo
/// and time-signature resolution), so the cursor stays in step with the sound.
/// Keeping it a pure value type makes it unit-testable without audio.
struct PlaybackProgress: Equatable {
    /// Absolute onset seconds of each played measure, plus a final entry for the
    /// end of the last measure. `count == playedMeasureCount + 1`.
    let measureOnsets: [Double]
    /// Global model-measure index that `measureOnsets[0]` corresponds to (playback
    /// can start mid-score from the selected measure).
    let firstMeasure: Int

    var totalDuration: Double { measureOnsets.last ?? 0 }

    /// The played measure (global index) and the fraction 0..<1 through it at
    /// `elapsed` seconds since playback began. `nil` before the start or once the
    /// music has finished, so the caller hides the cursor outside playback.
    func locate(elapsed: Double) -> (measure: Int, fraction: Double)? {
        guard elapsed >= 0, measureOnsets.count >= 2,
              elapsed < (measureOnsets.last ?? 0) else { return nil }
        for k in 0..<(measureOnsets.count - 1) {
            let start = measureOnsets[k]
            let end = measureOnsets[k + 1]
            if elapsed >= start, elapsed < end {
                let span = end - start
                let fraction = span > 0 ? (elapsed - start) / span : 0
                return (firstMeasure + k, fraction)
            }
        }
        return nil
    }

    /// Build the schedule for `playScore(score, fromMeasure:)`. Resolves each
    /// measure's tempo and time signature the same way the player does: the base
    /// score tempo unless a measure carries its own `tempoMarking`, and the score
    /// time signature unless a measure carries its own — last one found across the
    /// parts/staves wins, matching `MIDIEngine.playScore`.
    static func build(score: Score, fromMeasure: Int) -> PlaybackProgress {
        let baseBPM = score.tempo.bpm
        let start = max(0, fromMeasure)
        var onsets: [Double] = [0]
        var t = 0.0
        guard start < score.measureCount else {
            return PlaybackProgress(measureOnsets: onsets, firstMeasure: start)
        }
        for measureIndex in start..<score.measureCount {
            var currentBPM = baseBPM
            for part in score.parts where measureIndex < part.measures.count {
                if let tempo = part.measures[measureIndex].tempoMarking {
                    currentBPM = tempo.bpm
                }
            }
            let secPerBeat = currentBPM > 0 ? 60.0 / currentBPM : 0.5

            var timeSig = score.timeSignature
            for part in score.parts {
                for staff in part.staves where measureIndex < staff.measures.count {
                    if let ts = staff.measures[measureIndex].timeSignature { timeSig = ts }
                }
            }

            t += timeSig.totalBeats * secPerBeat
            onsets.append(t)
        }
        return PlaybackProgress(measureOnsets: onsets, firstMeasure: start)
    }
}
