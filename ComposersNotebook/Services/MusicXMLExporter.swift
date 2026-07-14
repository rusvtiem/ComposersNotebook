import Foundation

// MARK: - MusicXML Exporter

class MusicXMLExporter {

    /// Делений на четверть в экспортируемом MusicXML. 480 = 2⁵·3·5 — все простые
    /// длительности до 32-й с двойной точкой И триоли/квинтоли выражаются целым
    /// числом делений. Со старым значением 4 тридцать вторая давала duration=0
    /// (нота исчезала в стороннем редакторе), точки и триоли округлялись в мусор.
    private let divisionsPerQuarter = 480

    /// On-screen only: tint voices 2–4 so multiple voices read at a glance
    /// (MuseScore's ambient voice-colour cue). Off for PDF/file export so a
    /// printed or saved sheet is always black ink. Set per `export(...)` call.
    private var colorizeVoices = false

    /// MuseScore-parity voice colours. Voice 1 stays black (the common single-voice
    /// case is unchanged); voices 2–4 get green/orange/purple. Verovio honours the
    /// MusicXML `color` attribute on `<note>`, colouring notehead+stem+flag.
    private func colorAttribute(for event: NoteEvent) -> String {
        guard colorizeVoices else { return "" }
        switch event.voice {
        case .voice1: return ""
        case .voice2: return " color=\"#0E8A16\""
        case .voice3: return " color=\"#D2691E\""
        case .voice4: return " color=\"#8B2FC9\""
        }
    }

    func export(score: Score, colorizeVoices: Bool = false) -> String {
        self.colorizeVoices = colorizeVoices
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN"
          "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work>
            <work-title>\(escapeXML(score.title))</work-title>
          </work>
          <identification>
            <creator type="composer">\(escapeXML(score.composer))</creator>
            <encoding>
              <software>Composer's Notebook</software>
              <encoding-date>\(dateString())</encoding-date>
            </encoding>
          </identification>
          <part-list>
        """

        // Part list
        for (index, part) in score.parts.enumerated() {
            let partId = "P\(index + 1)"
            xml += """

                <score-part id="\(partId)">
                  <part-name>\(escapeXML(part.instrument.name))</part-name>
                  <part-abbreviation>\(escapeXML(part.instrument.shortName))</part-abbreviation>
                  <midi-instrument id="\(partId)-I1">
                    <midi-channel>1</midi-channel>
                    <midi-program>\(part.instrument.midiProgram + 1)</midi-program>
                  </midi-instrument>
                </score-part>
            """
        }

        xml += "\n  </part-list>"

        // Parts
        for (index, part) in score.parts.enumerated() {
            let partId = "P\(index + 1)"
            xml += "\n  <part id=\"\(partId)\">"

            let measureCount = part.staves.first?.measures.count ?? 0
            for measureIndex in 0..<measureCount {
                xml += exportMeasure(index: measureIndex, score: score, part: part)
            }

            xml += "\n  </part>"
        }

        xml += "\n</score-partwise>"
        return xml
    }

    // MARK: - Measure

    private func exportMeasure(index: Int, score: Score, part: Part) -> String {
        let staves = part.staves
        let isGrand = staves.count >= 2
        // Staff 0's measure carries shared measure-level content (time/key/tempo,
        // directions, barline). Per-staff notes and clefs come from each staff below.
        let measure = staves[0].measures[index]

        // Effective time signature at this bar — the last one set at or before it,
        // else the score default. Drives beam grouping (a bar with no <time> change
        // still needs the inherited meter to beam correctly).
        var effectiveTS = score.timeSignature
        for i in 0...index {
            if let t = staves[0].measures[i].timeSignature { effectiveTS = t }
        }

        var xml = "\n    <measure number=\"\(index + 1)\">"

        // Attributes (first measure or when changed)
        let anyClefChange = staves.contains { $0.measures[index].clefChange != nil }
        let needsAttributes = index == 0
            || measure.timeSignature != nil
            || measure.keySignature != nil
            || anyClefChange
            || measure.multiMeasureRestCount > 0

        if needsAttributes {
            xml += "\n      <attributes>"

            if index == 0 {
                xml += "\n        <divisions>\(divisionsPerQuarter)</divisions>"
            }

            if let ks = measure.keySignature ?? (index == 0 ? score.keySignature : nil) {
                xml += """

                        <key>
                          <fifths>\(ks.fifths)</fifths>
                          <mode>\(ks.mode.rawValue)</mode>
                        </key>
                """
            }

            if let ts = measure.timeSignature ?? (index == 0 ? score.timeSignature : nil) {
                xml += """

                        <time>
                          <beats>\(ts.beats)</beats>
                          <beat-type>\(ts.beatValue)</beat-type>
                        </time>
                """
            }

            if isGrand {
                xml += "\n        <staves>\(staves.count)</staves>"
            }

            // One clef per staff. On measure 0 emit each staff's clef; later measures
            // only emit a staff's clef if it actually changed there.
            for (k, staff) in staves.enumerated() {
                let clef = staff.measures[index].clefChange ?? (index == 0 ? staff.clef : nil)
                if let clef = clef {
                    xml += exportClef(clef, number: isGrand ? k + 1 : nil)
                }
            }

            // Multi-measure rest — <measure-style> follows clef per MusicXML order.
            if measure.multiMeasureRestCount > 0 {
                xml += "\n        <measure-style>\n          <multiple-rest>\(measure.multiMeasureRestCount)</multiple-rest>\n        </measure-style>"
            }

            xml += "\n      </attributes>"
        }

        // Tempo
        if let tempo = measure.tempoMarking ?? (index == 0 ? score.tempo : nil) {
            xml += """

                  <direction placement="above">
                    <direction-type>
                      <metronome>
                        <beat-unit>quarter</beat-unit>
                        <per-minute>\(Int(tempo.bpm))</per-minute>
                      </metronome>
                    </direction-type>
                    <sound tempo="\(Int(tempo.bpm))"/>
                  </direction>
            """
        }

        // Rehearsal mark (e.g. boxed letter A, B)
        if let mark = measure.rehearsalMark {
            xml += """

                  <direction placement="above">
                    <direction-type>
                      <rehearsal enclosure="\(mark.style == .boxed ? "rectangle" : "none")">\(escapeXML(mark.text))</rehearsal>
                    </direction-type>
                  </direction>
            """
        }

        // Expression texts (espressivo, dolce)
        for expr in measure.expressionTexts {
            xml += """

                  <direction placement="above">
                    <direction-type>
                      <words \(expr.italianTerm ? "font-style=\"italic\"" : "")>\(escapeXML(expr.text))</words>
                    </direction-type>
                  </direction>
            """
        }

        // Tempo change (accel./rit.)
        if let tc = measure.tempoChange {
            xml += """

                  <direction placement="above">
                    <direction-type>
                      <words font-style="italic">\(escapeXML(tc.kind.symbol))</words>
                    </direction-type>
                  </direction>
            """
        }

        // Hairpins (crescendo/diminuendo wedges)
        for hp in measure.hairpins {
            let wedge = hp.type == .crescendo ? "crescendo" : "diminuendo"
            xml += """

                  <direction placement="below">
                    <direction-type>
                      <wedge type="\(wedge)"/>
                    </direction-type>
                  </direction>
                  <direction placement="below">
                    <direction-type>
                      <wedge type="stop"/>
                    </direction-type>
                  </direction>
            """
        }

        // Octave shifts (8va/15ma)
        for os in measure.octaveShifts {
            let size: Int
            let type: String
            switch os.kind {
            case .ottavaAlta: size = 8; type = "down"   // "down" means notes are written lower than they sound
            case .ottavaBassa: size = 8; type = "up"
            case .quindicesimaAlta: size = 15; type = "down"
            case .quindicesimaBassa: size = 15; type = "up"
            }
            xml += """

                  <direction>
                    <direction-type>
                      <octave-shift type="\(type)" size="\(size)"/>
                    </direction-type>
                  </direction>
                  <direction>
                    <direction-type>
                      <octave-shift type="stop"/>
                    </direction-type>
                  </direction>
            """
        }

        // Navigation marks (D.C., D.S., Coda, Segno, Fine)
        if let nav = measure.navigationMark {
            xml += exportNavigationMark(nav)
        }

        // Volta brackets (1st/2nd ending)
        if let volta = measure.volta {
            xml += """

                  <barline location="left">
                    <ending number="\(volta.number)" type="start"/>
                  </barline>
            """
        }

        // Notes — one staff at a time, and within a staff one voice-group at a time.
        // Between voice groups AND between staves, <backup> rewinds the cursor to the
        // measure start so the next stream aligns from beat 1. Without the cross-staff
        // backup the lower staff of a grand staff was dropped (Verovio showed half a
        // piano). A single-voice staff emits exactly one group, so its output — and the
        // cross-staff backup size — is byte-identical to before this voice split.
        // Chord symbols are emitted as <harmony> *before* the note they attach to.
        var previousStaffTailDivisions = 0  // where the cursor sits past measure start after prev staff
        for (k, staff) in staves.enumerated() {
            let staffMeasure = staff.measures[index]
            if k > 0 && previousStaffTailDivisions > 0 {
                xml += "\n      <backup>\n        <duration>\(previousStaffTailDivisions)</duration>\n      </backup>"
            }
            let sNum = isGrand ? k + 1 : nil

            // Полнотактовая пауза: MusicXML требует <rest measure="yes"/> с
            // <duration> = длине такта и БЕЗ <type> — тогда Verovio рисует целую
            // паузу по центру такта в ЛЮБОМ размере. Раньше шла как обычная целая
            // (<type>whole>, duration=1920) — в 3/4 (такт 1440) это переполняло
            // такт: сумма <duration> голоса ≠ длине такта → Verovio сдвигал
            // геометрию → тап промахивался. Длину берём из размера, не из ноты.
            if staffMeasure.isFullMeasureRest, let restEvent = staffMeasure.events.first {
                let measureDiv = Int((effectiveTS.totalBeats * Double(divisionsPerQuarter)).rounded())
                xml += exportMeasureRest(restEvent, staffNumber: sNum, voice: sNum, divisions: measureDiv)
                previousStaffTailDivisions = measureDiv
                continue
            }

            let groups = groupEventsByVoice(staffMeasure.events)
            let multiVoice = groups.count > 1
            var previousGroupDivisions = 0
            for (gi, group) in groups.enumerated() {
                if gi > 0 && previousGroupDivisions > 0 {
                    xml += "\n      <backup>\n        <duration>\(previousGroupDivisions)</duration>\n      </backup>"
                }
                // Distinct MusicXML voice number: staff 1 → 1…4, staff 2 → 5…8, so voices
                // never collide across a grand staff. Single-voice keeps voice == staff number.
                let vNum: Int? = multiVoice ? ((sNum ?? 1) - 1) * 4 + group.voice.rawValue : sNum
                let beams = beamDirectives(for: group.events, timeSig: effectiveTS)
                var lastTechnique: PlaybackTechnique?
                for event in group.events {
                    if let chord = event.chordSymbol {
                        xml += exportHarmony(chord)
                    }
                    // Playback-technique text (pizz./arco/…) — printed once when it
                    // changes, matching the classic renderer which draws italianName.
                    if let tech = event.technique, tech != lastTechnique {
                        xml += """

                              <direction placement="above">
                                <direction-type>
                                  <words font-style="italic">\(escapeXML(tech.italianName))</words>
                                </direction-type>
                              </direction>
                        """
                        lastTechnique = tech
                    }
                    xml += exportNoteEvent(event, staffNumber: sNum, voiceNumber: vNum, multiVoice: multiVoice, beam: beams[event.id])
                }
                previousGroupDivisions = groupDivisions(group.events)
            }
            previousStaffTailDivisions = previousGroupDivisions
        }

        // Barline. The final measure of the piece always closes with a final
        // (light-heavy) barline by engraving convention — MuseScore/Dorico do this
        // automatically — unless the user set an explicit barline (repeat, etc.).
        let isLastMeasure = index == staves[0].measures.count - 1
        if measure.barlineEnd != .regular {
            xml += exportBarline(measure.barlineEnd)
        } else if isLastMeasure {
            xml += exportBarline(.final_)
        }

        xml += "\n    </measure>"
        return xml
    }

    // MARK: - Navigation Marks

    private func exportNavigationMark(_ mark: NavigationMark) -> String {
        let soundAttr: String
        let words: String
        switch mark {
        case .segno:      soundAttr = "segno=\"segno\"";      words = "𝄋"
        case .coda:       soundAttr = "coda=\"coda\"";        words = "𝄌"
        case .dcAlFine:   soundAttr = "dacapo=\"yes\"";       words = "D.C. al Fine"
        case .dcAlCoda:   soundAttr = "dacapo=\"yes\"";       words = "D.C. al Coda"
        case .dsAlFine:   soundAttr = "dalsegno=\"segno\"";   words = "D.S. al Fine"
        case .dsAlCoda:   soundAttr = "dalsegno=\"segno\"";   words = "D.S. al Coda"
        case .fine:       soundAttr = "fine=\"yes\"";         words = "Fine"
        }
        return """

              <direction placement="above">
                <direction-type>
                  <words>\(escapeXML(words))</words>
                </direction-type>
                <sound \(soundAttr)/>
              </direction>
        """
    }

    // MARK: - Harmony (chord symbol)

    private func exportHarmony(_ chord: ChordSymbol) -> String {
        // Map our Quality enum to MusicXML <kind>
        let kindText: String
        switch chord.quality {
        case .major:          kindText = "major"
        case .minor:          kindText = "minor"
        case .augmented:      kindText = "augmented"
        case .diminished:     kindText = "diminished"
        case .dominant7:      kindText = "dominant"
        case .major7:         kindText = "major-seventh"
        case .minor7:         kindText = "minor-seventh"
        case .minorMajor7:    kindText = "major-minor"
        case .diminished7:    kindText = "diminished-seventh"
        case .halfDiminished: kindText = "half-diminished"
        case .dominant9:      kindText = "dominant-ninth"
        case .major9:         kindText = "major-ninth"
        case .minor9:         kindText = "minor-ninth"
        case .dominant11:     kindText = "dominant-11th"
        case .dominant13:     kindText = "dominant-13th"
        case .sixth:          kindText = "major-sixth"
        case .minorSixth:     kindText = "minor-sixth"
        case .sus2:           kindText = "suspended-second"
        case .sus4:           kindText = "suspended-fourth"
        case .add9, .add11:   kindText = "major"  // MusicXML 4 has separate <degree>; simplification
        case .fifth:          kindText = "power"
        }

        var xml = "\n      <harmony>"
        xml += "\n        <root>"
        xml += "\n          <root-step>\(chord.root.englishName)</root-step>"
        if chord.rootAccidental != .natural {
            xml += "\n          <root-alter>\(chord.rootAccidental.semitoneOffset)</root-alter>"
        }
        xml += "\n        </root>"
        xml += "\n        <kind>\(kindText)</kind>"
        if let bass = chord.bassNote {
            xml += "\n        <bass>"
            xml += "\n          <bass-step>\(bass.englishName)</bass-step>"
            if let ba = chord.bassAccidental, ba != .natural {
                xml += "\n          <bass-alter>\(ba.semitoneOffset)</bass-alter>"
            }
            xml += "\n        </bass>"
        }
        xml += "\n      </harmony>"
        return xml
    }

    // MARK: - Note Event

    private func exportNoteEvent(_ event: NoteEvent, staffNumber: Int? = nil, voiceNumber: Int? = nil, multiVoice: Bool = false, beam: String? = nil) -> String {
        var xml = ""

        switch event.type {
        case .note(let pitch):
            xml += exportNote(pitch: pitch, duration: event.duration, event: event, staffNumber: staffNumber, voiceNumber: voiceNumber, multiVoice: multiVoice, beam: beam)

        case .chord(let pitches):
            for (i, pitch) in pitches.enumerated() {
                xml += exportNote(pitch: pitch, duration: event.duration, event: event, isChord: i > 0, staffNumber: staffNumber, chordIndex: i, voiceNumber: voiceNumber, multiVoice: multiVoice, beam: beam)
            }

        case .rest:
            xml += "\n      <note\(Self.idAttribute(event.id))\(colorAttribute(for: event))>"
            xml += "\n        <rest/>"
            xml += exportDuration(event, voice: voiceNumber ?? staffNumber)
            if let staffNumber = staffNumber {
                xml += "\n        <staff>\(staffNumber)</staff>"
            }
            xml += "\n      </note>"
        }

        return xml
    }

    /// Full-measure rest: `<rest measure="yes"/>` with `<duration>` equal to the
    /// measure length and NO `<type>` — Verovio then centers a whole-rest glyph in
    /// the bar for ANY meter, and the voice's `<duration>` sum matches the bar so
    /// the geometry does not shift (a mismatch pushed tap coordinates off-note).
    private func exportMeasureRest(_ event: NoteEvent, staffNumber: Int? = nil, voice: Int? = nil, divisions: Int) -> String {
        var xml = "\n      <note\(Self.idAttribute(event.id))\(colorAttribute(for: event))>"
        xml += "\n        <rest measure=\"yes\"/>"
        xml += "\n        <duration>\(divisions)</duration>"
        if let voice = voice {
            xml += "\n        <voice>\(voice)</voice>"
        }
        if let staffNumber = staffNumber {
            xml += "\n        <staff>\(staffNumber)</staff>"
        }
        xml += "\n      </note>"
        return xml
    }

    /// Emits our stable `NoteEvent.id` as the MusicXML `id` attribute so Verovio
    /// preserves it as `@xml:id` on the rendered `<g class="note">` — this is the
    /// round-trip that lets a tap on a Verovio-drawn note resolve back to our event.
    /// Chord notes share one event, so non-first noteheads get a `-N` suffix to stay unique.
    /// The `e` prefix guarantees a valid XML Name (must not start with a digit).
    static func idAttribute(_ id: UUID, chordIndex: Int = 0) -> String {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let suffix = chordIndex > 0 ? "-\(chordIndex)" : ""
        return " id=\"e\(hex)\(suffix)\""
    }

    private func exportNote(pitch: Pitch, duration: Duration, event: NoteEvent, isChord: Bool = false, staffNumber: Int? = nil, chordIndex: Int = 0, voiceNumber: Int? = nil, multiVoice: Bool = false, beam: String? = nil) -> String {
        var xml = "\n      <note\(Self.idAttribute(event.id, chordIndex: chordIndex))\(colorAttribute(for: event))>"

        // Grace — ПЕРВЫЙ ребёнок <note> по порядку MusicXML, до <chord/> и <pitch>.
        // slash="yes" — acciaccatura (короткий перечёркнутый), appoggiatura — без.
        if let grace = event.grace {
            xml += grace == .acciaccatura ? "\n        <grace slash=\"yes\"/>" : "\n        <grace/>"
        }

        if isChord {
            xml += "\n        <chord/>"
        }

        // Pitch
        xml += "\n        <pitch>"
        xml += "\n          <step>\(pitch.name.englishName)</step>"
        if pitch.accidental != .natural {
            xml += "\n          <alter>\(pitch.accidental.semitoneOffset)</alter>"
        }
        xml += "\n          <octave>\(pitch.octave)</octave>"
        xml += "\n        </pitch>"

        // Duration — у форшлага <duration> отсутствует по MusicXML (grace note
        // не имеет длительности); <voice>/<type>/<dot> сохраняются.
        xml += exportDuration(event, voice: voiceNumber ?? staffNumber, graceMode: event.isGrace)

        // Tuplet time-modification (3:2, 5:4, etc.)
        if let tuplet = event.tuplet {
            xml += "\n        <time-modification>"
            xml += "\n          <actual-notes>\(tuplet.actualCount)</actual-notes>"
            xml += "\n          <normal-notes>\(tuplet.normalCount)</normal-notes>"
            xml += "\n        </time-modification>"
        }

        // Tie
        if event.tiedToNext {
            xml += "\n        <tie type=\"start\"/>"
        }

        // Accidental display
        if pitch.accidental != .natural {
            let accName: String
            switch pitch.accidental {
            case .sharp: accName = "sharp"
            case .flat: accName = "flat"
            case .doubleSharp: accName = "double-sharp"
            case .doubleFlat: accName = "flat-flat"
            case .natural: accName = "natural"
            }
            xml += "\n        <accidental>\(accName)</accidental>"
        }

        // Stem direction — emitted when the user explicitly flipped the stem
        // (X in MuseScore) OR when a staff carries multiple voices (V1/V3 up,
        // V2/V4 down, как в MuseScore). Default single-voice notes emit nothing,
        // so Verovio keeps its own auto-stem and output stays byte-identical.
        // Must precede <staff> per MusicXML <note> child order.
        if let stem = stemValue(for: event, multiVoice: multiVoice) {
            xml += "\n        <stem>\(stem)</stem>"
        }

        // Staff assignment (grand staff) — must precede <notations> per MusicXML order.
        if let staffNumber = staffNumber {
            xml += "\n        <staff>\(staffNumber)</staff>"
        }

        // Beam (begin/continue/end) — grouped by meter in beamDirectives. Emitted on
        // the primary notehead of a chord only (Verovio reads the beam from the first
        // note); secondary beamlets for 16th+ Verovio derives from note durations.
        if !isChord, let beam = beam {
            xml += "\n        <beam number=\"1\">\(beam)</beam>"
        }

        // Notations
        var notations: [String] = []

        if event.tiedToNext {
            notations.append("          <tied type=\"start\"/>")
        }
        if event.slurStart {
            notations.append("          <slur type=\"start\"/>")
        }
        if event.slurEnd {
            notations.append("          <slur type=\"stop\"/>")
        }

        for art in event.articulations {
            switch art {
            case .staccato:
                notations.append("          <articulations><staccato/></articulations>")
            case .accent:
                notations.append("          <articulations><accent/></articulations>")
            case .tenuto:
                notations.append("          <articulations><tenuto/></articulations>")
            case .marcato:
                notations.append("          <articulations><strong-accent/></articulations>")
            case .fermata:
                notations.append("          <fermata/>")
            case .legato:
                break  // handled via slur
            }
        }

        // Tuplet bracket on notations (start/stop on first/last note in group)
        if let tuplet = event.tuplet {
            if tuplet.isFirstInGroup {
                notations.append("          <tuplet number=\"1\" type=\"start\"/>")
            }
            if tuplet.isLastInGroup {
                notations.append("          <tuplet number=\"1\" type=\"stop\"/>")
            }
        }

        // Fingering as technical notation
        if let fingering = event.fingering, !fingering.isEmpty {
            notations.append("          <technical><fingering>\(escapeXML(fingering))</fingering></technical>")
        }

        if !notations.isEmpty {
            xml += "\n        <notations>"
            for n in notations {
                xml += "\n\(n)"
            }
            xml += "\n        </notations>"
        }

        // Dynamics
        if let dynamic = event.dynamic {
            xml += """

                    <dynamics>
                      <\(dynamic.rawValue)/>
                    </dynamics>
            """
        }

        // Lyric — attached to the first notehead only (chord's extra notes share
        // the event, so !isChord avoids duplicate syllables). <syllabic>single</>
        // keeps each word standalone; word-splitting isn't modeled yet.
        if !isChord, let lyric = event.lyric, !lyric.isEmpty {
            xml += "\n        <lyric number=\"1\">\n          <syllabic>single</syllabic>\n          <text>\(escapeXML(lyric))</text>\n        </lyric>"
        }

        xml += "\n      </note>"
        return xml
    }

    // MARK: - Stem

    /// MusicXML `<stem>` value for an event, or nil to leave it to Verovio's
    /// auto-stem. An explicit flip (`event.stemDirection` .up/.down — the X button)
    /// always wins. Otherwise a stem is forced only when the staff is polyphonic:
    /// odd voices point up, even voices down, matching MuseScore's V1↑/V2↓ default.
    /// Rests never carry a stem.
    private func stemValue(for event: NoteEvent, multiVoice: Bool) -> String? {
        if event.isRest { return nil }
        switch event.stemDirection {
        case .up: return "up"
        case .down: return "down"
        case .auto:
            guard multiVoice else { return nil }
            switch event.voice {
            case .voice1, .voice3: return "up"
            case .voice2, .voice4: return "down"
            }
        }
    }

    // MARK: - Beaming

    /// begin/continue/end beam directives keyed by event id, grouping beamable notes
    /// (eighth and shorter) by the metrical beat, as MuseScore does. A note that
    /// starts a new metrical group, follows a rest/longer note, or stands alone in
    /// its group gets no beam (rendered with a flag). Verovio adds the secondary
    /// beamlets for 16th+ from the note durations, so only the primary level is coded.
    ///
    /// Group size (in quarter-beats): 4/4 and 2/2 beam eighths across the half-bar
    /// (2.0), compound meters (6/8, 9/8, 12/8) by the dotted-quarter beat (1.5), and
    /// everything else by the beat (1.0). Notes shorter than an eighth always break
    /// at the beat so a run of sixteenths beams per beat, not across the half-bar.
    private func beamDirectives(for events: [NoteEvent], timeSig: TimeSignature) -> [UUID: String] {
        let compound = timeSig.beatValue == 8 && timeSig.beats % 3 == 0 && timeSig.beats > 3
        let fineBeats = compound ? 1.5 : 1.0
        let coarseBeats: Double
        if timeSig.beats == 4 && timeSig.beatValue == 4 { coarseBeats = 2.0 }
        else if timeSig.beats == 2 && timeSig.beatValue == 2 { coarseBeats = 2.0 }
        else if compound { coarseBeats = 1.5 }
        else { coarseBeats = fineBeats }

        // Per-event: metrical offset, whether it can be beamed, and its group size
        // (eighths use the coarse group, shorter values the fine/beat group).
        struct Info { let id: UUID; let offset: Double; let beamable: Bool; let boundary: Double }
        var infos: [Info] = []
        var offset = 0.0
        for e in events {
            let raw = e.duration.value.rawValue           // 8=eighth, 16, 32, 64; ≤4 not beamable
            let beamable = !e.isRest && raw >= 8
            infos.append(Info(id: e.id, offset: offset,
                              beamable: beamable,
                              boundary: raw == 8 ? coarseBeats : fineBeats))
            offset += e.actualBeats
        }

        var directives: [UUID: String] = [:]
        let eps = 1e-6
        var i = 0
        while i < infos.count {
            guard infos[i].beamable else { i += 1; continue }
            var j = i
            while j + 1 < infos.count && infos[j + 1].beamable {
                let g = min(infos[j].boundary, infos[j + 1].boundary)
                let gPrev = Int((infos[j].offset / g + eps).rounded(.down))
                let gNext = Int((infos[j + 1].offset / g + eps).rounded(.down))
                if gPrev != gNext { break }
                j += 1
            }
            if j > i {   // a run of ≥2 beamable notes → beam them
                directives[infos[i].id] = "begin"
                if j > i + 1 {
                    for k in (i + 1)..<j { directives[infos[k].id] = "continue" }
                }
                directives[infos[j].id] = "end"
            }
            i = j + 1
        }
        return directives
    }

    // MARK: - Duration

    private func exportDuration(_ event: NoteEvent, voice: Int? = nil, graceMode: Bool = false) -> String {
        // <duration> — звучащая длительность в делениях, с учётом tuplet
        // (event.actualBeats — единый источник тайминга, как в плейбеке). Раньше
        // бралось duration.beats × 4: tuplet игнорировался (триоль занимала полную
        // долю → переполнение такта у стороннего читателя), а 32-я × 4 = 0 → нота
        // пропадала. max(1) — страховка, чтобы duration никогда не был нулевым.
        let divisions = max(1, Int((event.actualBeats * Double(divisionsPerQuarter)).rounded()))
        let typeName: String
        switch event.duration.value {
        case .longa: typeName = "long"
        case .breve: typeName = "breve"
        case .whole: typeName = "whole"
        case .half: typeName = "half"
        case .quarter: typeName = "quarter"
        case .eighth: typeName = "eighth"
        case .sixteenth: typeName = "16th"
        case .thirtySecond: typeName = "32nd"
        case .sixtyFourth: typeName = "64th"
        }

        // Форшлаг: <duration> опускается (grace note не занимает времени), но
        // <voice>/<type>/<dot> нужны для правильной отрисовки мелкой ноты.
        var xml = graceMode ? "" : "\n        <duration>\(divisions)</duration>"
        // <voice> must precede <type> per MusicXML order. Emitted only for grand
        // staff (voice == staff number) so single-staff output stays as validated.
        if let voice = voice {
            xml += "\n        <voice>\(voice)</voice>"
        }
        xml += "\n        <type>\(typeName)</type>"

        // doubleDotted проверяется раньше dotted (как в Duration.beats): импортёры
        // на двойную точку ставят ОБА флага — иначе экспорт дал бы три <dot/>.
        if event.duration.doubleDotted {
            xml += "\n        <dot/>"
            xml += "\n        <dot/>"
        } else if event.duration.dotted {
            xml += "\n        <dot/>"
        }

        return xml
    }

    // MARK: - Clef

    private func exportClef(_ clef: Clef, number: Int? = nil) -> String {
        let (sign, line): (String, Int)
        switch clef {
        case .treble: (sign, line) = ("G", 2)
        case .bass: (sign, line) = ("F", 4)
        case .alto: (sign, line) = ("C", 3)
        case .tenor: (sign, line) = ("C", 4)
        }
        let numberAttr = number.map { " number=\"\($0)\"" } ?? ""
        return """

                <clef\(numberAttr)>
                  <sign>\(sign)</sign>
                  <line>\(line)</line>
                </clef>
        """
    }

    /// Total sounding divisions in a measure — the sum of each event's duration
    /// (a chord counts once). Used to size <backup> when writing multiple staves.
    private func measureDivisions(_ measure: Measure) -> Int {
        groupDivisions(measure.events)
    }

    /// Sounding divisions for an arbitrary event stream (a voice group or a whole
    /// measure). Sizes the <backup> that rewinds the cursor to the measure start.
    private func groupDivisions(_ events: [NoteEvent]) -> Int {
        var total = 0
        for event in events {
            total += max(1, Int((event.actualBeats * Double(divisionsPerQuarter)).rounded()))
        }
        return total
    }

    /// Partition a staff-measure's events into per-voice streams for polyphonic
    /// export. The common single-voice case returns exactly one group in original
    /// order (so its MusicXML is unchanged). When several voices share the staff,
    /// each voice's internal order is preserved and groups come out voice-1 first,
    /// then 2, 3, 4 — the order MuseScore writes and Verovio expects for stacking.
    private func groupEventsByVoice(_ events: [NoteEvent]) -> [(voice: VoiceLayer, events: [NoteEvent])] {
        if events.isEmpty { return [] }
        let voicesPresent = Set(events.map { $0.voice })
        if voicesPresent.count <= 1 {
            return [(voice: events[0].voice, events: events)]
        }
        var buckets: [VoiceLayer: [NoteEvent]] = [:]
        for event in events { buckets[event.voice, default: []].append(event) }
        return buckets.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map { (voice: $0, events: buckets[$0]!) }
    }

    // MARK: - Barline

    private func exportBarline(_ type: BarlineType) -> String {
        let style: String
        switch type {
        case .regular: return ""
        case .double: style = "light-light"
        case .final_: style = "light-heavy"
        case .repeatStart: return """

                  <barline location="left">
                    <bar-style>heavy-light</bar-style>
                    <repeat direction="forward"/>
                  </barline>
        """
        case .repeatEnd: return """

                  <barline location="right">
                    <bar-style>light-heavy</bar-style>
                    <repeat direction="backward"/>
                  </barline>
        """
        case .repeatBoth: return """

                  <barline location="right">
                    <bar-style>light-heavy</bar-style>
                    <repeat direction="backward"/>
                  </barline>
        """
        }

        return """

              <barline location="right">
                <bar-style>\(style)</bar-style>
              </barline>
        """
    }

    // MARK: - Helpers

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
