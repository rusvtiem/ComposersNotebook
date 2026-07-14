import Foundation

// MARK: - Playback Scheduler
//
// Превращает Score со всеми spanner'ами (повторы, voltas, D.S./D.C./Coda,
// tempo changes, hairpins, octave shifts, tuplets) в плоский список
// PlaybackEvent — кортеж (время, midi-нота, velocity, длительность, instrument).
//
// MIDIEngine берёт этот список и просто проигрывает события по времени.
// Никакой логики jumps в самом MIDIEngine не нужно.
//
// Никакого ИИ — чистый алгоритм expansion (раскрытие повторов / навигаций).

struct PlaybackEvent {
    var startBeat: Double          // глобальная позиция в долях с начала плейбека
    var durationBeats: Double      // длительность в долях
    var midiNote: Int              // 0..127
    var velocity: Int              // 0..127
    var partIndex: Int             // какая партия
    var voice: VoiceLayer
    var bpmAtStart: Double         // темп на момент старта (для конвертации в секунды)
    var tiedToNext: Bool
}

enum PlaybackScheduler {

    /// Развернуть всю партитуру в плоский список нот для плейбека.
    /// `partIndex == nil` — мультитрек (все партии). `partIndex == N` — только одна.
    static func expand(score: Score, partIndex: Int? = nil) -> [PlaybackEvent] {
        let parts: [(Int, Part)]
        if let pi = partIndex, pi < score.parts.count {
            parts = [(pi, score.parts[pi])]
        } else {
            parts = score.parts.enumerated().map { ($0, $1) }
        }

        var allEvents: [PlaybackEvent] = []
        for (partIdx, part) in parts {
            let partEvents = expandPart(part: part, partIndex: partIdx, score: score)
            allEvents.append(contentsOf: partEvents)
        }
        return allEvents.sorted { $0.startBeat < $1.startBeat }
    }

    // MARK: - Single part expansion

    private static func expandPart(part: Part, partIndex: Int, score: Score) -> [PlaybackEvent] {
        let measures = part.measures
        guard !measures.isEmpty else { return [] }

        var events: [PlaybackEvent] = []
        var globalBeat: Double = 0
        var currentBPM = score.tempo.bpm
        var visitedDC: Bool = false
        var visitedDS: Bool = false
        var fineHit: Bool = false
        var headedToCoda: Bool = false

        // Map measure idx → segno / coda location
        var segnoIdx: Int? = nil
        var codaIdx: Int? = nil
        for (i, m) in measures.enumerated() {
            if m.navigationMark == .segno {
                segnoIdx = i
            } else if m.navigationMark == .coda && codaIdx == nil {
                // Тегом ".coda" помечается и точка прибытия к Coda, и сам знак
                codaIdx = i
            }
        }

        // Стек точек репризы — стартовая позиция для каждого repeatStart.
        // По умолчанию первая точка — начало пьесы.
        var repeatStarts: [Int] = [0]
        // Сколько раз уже сыграли каждый repeatEnd (по индексу такта)
        var repeatPlayed: [Int: Int] = [:]

        var i = 0
        let maxIterations = measures.count * 6 // защита от бесконечного цикла
        var iter = 0

        while i < measures.count && iter < maxIterations {
            iter += 1
            let measure = measures[i]

            // Volta: если 2-й проход — пропускаем volta=1; если 1-й проход — пропускаем volta=2
            if let v = measure.volta {
                let onFirstPass = (repeatPlayed[i] ?? 0) == 0
                if v.number == 1 && !onFirstPass {
                    i = v.endMeasure + 1
                    continue
                }
                if v.number >= 2 && onFirstPass {
                    i = v.endMeasure + 1
                    continue
                }
            }

            // Записываем repeat-start для последующего возврата
            if measure.barlineEnd == .repeatStart || measureHasLeftRepeat(measure) {
                if repeatStarts.last != i {
                    repeatStarts.append(i)
                }
            }

            // Tempo
            if let tm = measure.tempoMarking {
                currentBPM = tm.bpm
            }

            // Generate events for this measure
            let measureBeats = (measure.timeSignature ?? score.timeSignature).totalBeats
            let measureEvents = generateMeasureEvents(
                measure: measure,
                measureIndex: i,
                partIndex: partIndex,
                globalBeatOffset: globalBeat,
                bpm: currentBPM,
                octaveShiftSemitones: computeOctaveShift(measure: measure),
                instrumentTransposition: part.instrument.transposition
            )
            events.append(contentsOf: measureEvents)
            globalBeat += measureBeats

            // Apply tempo change (linear BPM transition)
            if let tc = measure.tempoChange {
                currentBPM = tc.endBPM
            }

            // End-of-measure handling: navigation marks, repeats
            let nav = measure.navigationMark

            // 1) Fine: останавливаемся если мы уже прошли DC/DS
            if nav == .fine && (visitedDC || visitedDS) {
                fineHit = true
                break
            }

            // 2) Coda marker — если мы шли "to Coda", прыгаем сюда
            if measure.navigationMark == .coda && headedToCoda {
                // продолжаем играть из этой позиции (уже сыграно)
                headedToCoda = false
                // нечего делать, edge: coda как точка прибытия
            }

            // 3) DC al Fine / DC al Coda — возврат к началу
            if (nav == .dcAlFine || nav == .dcAlCoda) && !visitedDC {
                visitedDC = true
                if nav == .dcAlCoda { headedToCoda = true }
                i = 0
                continue
            }

            // 4) DS al Fine / DS al Coda — возврат к Segno
            if (nav == .dsAlFine || nav == .dsAlCoda) && !visitedDS {
                visitedDS = true
                if nav == .dsAlCoda { headedToCoda = true }
                if let s = segnoIdx {
                    i = s
                    continue
                }
            }

            // 5) Repeat end — возврат к ближайшему repeat-start
            if measure.barlineEnd == .repeatEnd || measure.barlineEnd == .repeatBoth {
                let played = repeatPlayed[i] ?? 0
                if played == 0 {
                    repeatPlayed[i] = played + 1
                    if let target = repeatStarts.last {
                        i = target
                        continue
                    }
                }
                // Уже играли репризу — идём дальше; убираем точку из стека если она поверх
                if measure.barlineEnd == .repeatBoth {
                    repeatStarts.append(i)
                }
            }

            i += 1
        }

        _ = fineHit  // hint suppression
        return events
    }

    // MARK: - Helpers

    /// MusicXML позволяет помечать левую границу такта как начало повтора через
    /// `barlineEnd` соседнего такта; для простоты считаем repeatStart как
    /// "у этого такта слева повтор".
    private static func measureHasLeftRepeat(_ measure: Measure) -> Bool {
        // В нашей упрощённой модели barlineEnd относится к концу. Поэтому
        // отдельное поле leftRepeat не вводим: repeatStart на barlineEnd означает
        // "следующий такт — начало секции". Всё уже учтено в expandPart.
        return false
    }

    /// Суммарный полутоновый сдвиг всех octave shift'ов, активных в этом такте.
    /// Грубо: первый OctaveShift в массиве. Полная логика — на per-note уровне,
    /// но даже это даёт ощутимое преимущество над "нет октавных переносов".
    private static func computeOctaveShift(measure: Measure) -> Int {
        measure.octaveShifts.first?.kind.semitones ?? 0
    }

    /// Ограничить MIDI-ноту допустимым диапазоном 0…127 после сдвигов
    /// (транспозиция + октавы могут вывести крайние ноты за границу).
    private static func clampMIDI(_ note: Int) -> Int {
        min(127, max(0, note))
    }

    /// Превратить ноты одного такта в PlaybackEvent.
    /// Учитывается:
    ///   - actualBeats (tuplet timing),
    ///   - octaveShift (полутоновый сдвиг),
    ///   - instrumentTransposition (концертный строй: written → sounding),
    ///   - hairpin (линейная интерполяция velocity от текущей dynamic к целевой),
    ///   - tempo change (BPM меняется в течение такта).
    private static func generateMeasureEvents(
        measure: Measure,
        measureIndex: Int,
        partIndex: Int,
        globalBeatOffset: Double,
        bpm: Double,
        octaveShiftSemitones: Int,
        instrumentTransposition: Int
    ) -> [PlaybackEvent] {
        var events: [PlaybackEvent] = []
        var localBeat: Double = 0

        // Суммарный полутоновый сдвиг записанной ноты до звучащей (концертной):
        // октавные переносы + строй инструмента (Bb-кларнет -2, валторна F -7,
        // пикколо +12). MIDI-нота клампится в 0…127.
        let semitoneShift = octaveShiftSemitones + instrumentTransposition

        let baseVelocity = DynamicMarking.mf.velocity
        let measureBeats = (measure.timeSignature?.totalBeats ?? 4.0)

        for event in measure.events {
            let beats = event.actualBeats
            // Форшлаг не занимает времени такта (actualBeats == 0, localBeat не
            // двигается), но должен ЗВУЧАТЬ. Даём ему короткую длительность звука,
            // не сдвигая метрическую позицию следующей ноты.
            let soundBeats = event.isGrace ? min(0.125, measureBeats) : beats

            // Velocity: либо от dynamic ноты, либо интерполяция hairpin'а
            var vel = event.dynamic?.velocity ?? baseVelocity
            if let hp = measure.hairpins.first(where: { localBeat >= $0.startBeat && localBeat <= $0.endBeat }) {
                let t = (hp.endBeat > hp.startBeat)
                    ? (localBeat - hp.startBeat) / (hp.endBeat - hp.startBeat)
                    : 0.0
                let direction = hp.type == .crescendo ? 1.0 : -1.0
                let velocityDelta = Int(direction * t * 40) // ±40 на длину hairpin
                vel = max(0, min(127, vel + velocityDelta))
            }
            // Артикуляции акцент/маркато играются громче (паритет MuseScore 4 §8.3):
            // marcato — самый сильный удар, accent — заметное усиление. Marcato имеет
            // приоритет, если проставлены обе.
            if event.articulations.contains(.marcato) {
                vel += 25
            } else if event.articulations.contains(.accent) {
                vel += 15
            }
            // Пол громкости = velocity ppp (16) как в MuseScore: тише — уже неслышимо,
            // а diminuendo/тихая динамика не должны срываться в MIDI note-off (vel 0).
            vel = max(16, min(127, vel))

            // BPM в этой ноте (учёт tempo change)
            var noteBPM = bpm
            if let tc = measure.tempoChange {
                noteBPM = tc.interpolatedBPM(at: globalBeatOffset + localBeat, defaultStartBPM: bpm)
            }

            switch event.type {
            case .note(let pitch):
                events.append(PlaybackEvent(
                    startBeat: globalBeatOffset + localBeat,
                    durationBeats: soundBeats,
                    midiNote: clampMIDI(pitch.midiNote + semitoneShift),
                    velocity: vel,
                    partIndex: partIndex,
                    voice: event.voice,
                    bpmAtStart: noteBPM,
                    tiedToNext: event.tiedToNext
                ))
            case .chord(let pitches):
                for p in pitches {
                    events.append(PlaybackEvent(
                        startBeat: globalBeatOffset + localBeat,
                        durationBeats: soundBeats,
                        midiNote: clampMIDI(p.midiNote + semitoneShift),
                        velocity: vel,
                        partIndex: partIndex,
                        voice: event.voice,
                        bpmAtStart: noteBPM,
                        tiedToNext: event.tiedToNext
                    ))
                }
            case .rest:
                break  // паузы не добавляют событий, только продвигают localBeat
            }

            localBeat += beats
            if localBeat > measureBeats + 0.001 { break }  // защита от переполнения такта
        }

        return events
    }
}
