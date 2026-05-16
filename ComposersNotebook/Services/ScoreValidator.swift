import Foundation

// MARK: - Score Validator
//
// Помогает композитору находить технические проблемы партитуры:
// ноты вне диапазона инструмента, переполненные такты, недопустимая
// высота тонов. Никакого ML — чистые проверки по правилам.

enum ScoreValidator {

    struct Issue: Identifiable {
        enum Severity { case error, warning, info }
        enum Kind {
            case noteOutOfRange       // нота вне диапазона инструмента
            case measureOverflow      // событий в такте больше чем влезает
            case measureUnderflow     // такт не заполнен (только info)
            case voiceConflict        // в одном voice две ноты на одной доле
            case unsupportedTechnique // playback technique не подходит инструменту
        }

        let id = UUID()
        var kind: Kind
        var severity: Severity
        var partIndex: Int
        var measureIndex: Int
        var eventIndex: Int?
        var message: String
    }

    /// Проверить всю партитуру. Возвращает все найденные проблемы.
    static func validate(_ score: Score) -> [Issue] {
        var issues: [Issue] = []
        for (pi, part) in score.parts.enumerated() {
            for (mi, measure) in part.measures.enumerated() {
                issues.append(contentsOf: validateMeasure(measure, score: score, part: part, partIndex: pi, measureIndex: mi))
            }
        }
        return issues
    }

    /// Точечная проверка одного такта (быстро для UI-подсветки).
    static func validateMeasure(
        _ measure: Measure,
        score: Score,
        part: Part,
        partIndex: Int,
        measureIndex: Int
    ) -> [Issue] {
        var issues: [Issue] = []
        let ts = measure.timeSignature ?? score.timeSignature
        let used = measure.usedBeats
        let total = ts.totalBeats

        // 1. Overflow/Underflow
        if used > total + 0.001 {
            issues.append(Issue(
                kind: .measureOverflow,
                severity: .error,
                partIndex: partIndex,
                measureIndex: measureIndex,
                eventIndex: nil,
                message: "Такт переполнен: \(String(format: "%.2f", used)) долей вместо \(String(format: "%.2f", total))"
            ))
        }
        if used > 0 && used < total - 0.001 {
            // Underflow — это info, потому что можно осознанно оставить такт неполным
            issues.append(Issue(
                kind: .measureUnderflow,
                severity: .info,
                partIndex: partIndex,
                measureIndex: measureIndex,
                eventIndex: nil,
                message: "Такт не полный: \(String(format: "%.2f", used)) долей из \(String(format: "%.2f", total))"
            ))
        }

        // 2. Out-of-range notes
        let lowMIDI = part.instrument.lowestNote.midiNote
        let highMIDI = part.instrument.highestNote.midiNote
        for (ei, event) in measure.events.enumerated() {
            let pitches: [Pitch]
            switch event.type {
            case .note(let p): pitches = [p]
            case .chord(let ps): pitches = ps
            case .rest: continue
            }
            for p in pitches {
                if p.midiNote < lowMIDI || p.midiNote > highMIDI {
                    issues.append(Issue(
                        kind: .noteOutOfRange,
                        severity: .warning,
                        partIndex: partIndex,
                        measureIndex: measureIndex,
                        eventIndex: ei,
                        message: "Нота \(p.displayString) (MIDI \(p.midiNote)) вне диапазона \(part.instrument.name): \(part.instrument.lowestNote.displayString)…\(part.instrument.highestNote.displayString)"
                    ))
                }
            }
        }

        // 3. Voice conflicts (две ноты в одном voice на одной доле)
        var voiceBeats: [VoiceLayer: [Double]] = [:]
        var beat: Double = 0
        for event in measure.events {
            let existing = voiceBeats[event.voice] ?? []
            if existing.contains(where: { abs($0 - beat) < 0.001 }) {
                issues.append(Issue(
                    kind: .voiceConflict,
                    severity: .warning,
                    partIndex: partIndex,
                    measureIndex: measureIndex,
                    eventIndex: nil,
                    message: "Голос \(event.voice.displayName): две ноты на одной доле (\(String(format: "%.2f", beat)))"
                ))
            }
            voiceBeats[event.voice] = existing + [beat]
            beat += event.actualBeats
        }

        // 4. Unsupported playback technique
        for (ei, event) in measure.events.enumerated() {
            guard let tech = event.technique else { continue }
            if !tech.applicableGroups.contains(part.instrument.group) {
                issues.append(Issue(
                    kind: .unsupportedTechnique,
                    severity: .warning,
                    partIndex: partIndex,
                    measureIndex: measureIndex,
                    eventIndex: ei,
                    message: "Техника \(tech.italianName) обычно неприменима к \(part.instrument.name)"
                ))
            }
        }

        return issues
    }

    /// Сколько ошибок и предупреждений всего.
    static func counts(_ issues: [Issue]) -> (errors: Int, warnings: Int, info: Int) {
        var e = 0, w = 0, i = 0
        for issue in issues {
            switch issue.severity {
            case .error: e += 1
            case .warning: w += 1
            case .info: i += 1
            }
        }
        return (e, w, i)
    }
}
