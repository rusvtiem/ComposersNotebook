import Foundation

// MARK: - MusicXML Exporter

class MusicXMLExporter {

    func export(score: Score) -> String {
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

            for (measureIndex, measure) in part.measures.enumerated() {
                xml += exportMeasure(measure, index: measureIndex, score: score, part: part)
            }

            xml += "\n  </part>"
        }

        xml += "\n</score-partwise>"
        return xml
    }

    // MARK: - Measure

    private func exportMeasure(_ measure: Measure, index: Int, score: Score, part: Part) -> String {
        var xml = "\n    <measure number=\"\(index + 1)\">"

        // Attributes (first measure or when changed)
        let needsAttributes = index == 0
            || measure.timeSignature != nil
            || measure.keySignature != nil
            || measure.clefChange != nil

        if needsAttributes {
            xml += "\n      <attributes>"

            if index == 0 {
                xml += "\n        <divisions>4</divisions>"  // quarter note = 4 divisions
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

            let clef = measure.clefChange ?? (index == 0 ? part.instrument.defaultClef : nil)
            if let clef = clef {
                xml += exportClef(clef)
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

        // Notes — chord symbols are emitted as <harmony> *before* the note they attach to.
        for event in measure.events {
            if let chord = event.chordSymbol {
                xml += exportHarmony(chord)
            }
            xml += exportNoteEvent(event)
        }

        // Barline
        if measure.barlineEnd != .regular {
            xml += exportBarline(measure.barlineEnd)
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

    private func exportNoteEvent(_ event: NoteEvent) -> String {
        var xml = ""

        switch event.type {
        case .note(let pitch):
            xml += exportNote(pitch: pitch, duration: event.duration, event: event)

        case .chord(let pitches):
            for (i, pitch) in pitches.enumerated() {
                xml += exportNote(pitch: pitch, duration: event.duration, event: event, isChord: i > 0)
            }

        case .rest:
            xml += "\n      <note>"
            xml += "\n        <rest/>"
            xml += exportDuration(event.duration)
            xml += "\n      </note>"
        }

        return xml
    }

    private func exportNote(pitch: Pitch, duration: Duration, event: NoteEvent, isChord: Bool = false) -> String {
        var xml = "\n      <note>"

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

        // Duration
        xml += exportDuration(duration)

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

        xml += "\n      </note>"
        return xml
    }

    // MARK: - Duration

    private func exportDuration(_ duration: Duration) -> String {
        // Divisions: quarter = 4
        let divisions = Int(duration.beats * 4)
        let typeName: String
        switch duration.value {
        case .whole: typeName = "whole"
        case .half: typeName = "half"
        case .quarter: typeName = "quarter"
        case .eighth: typeName = "eighth"
        case .sixteenth: typeName = "16th"
        case .thirtySecond: typeName = "32nd"
        }

        var xml = "\n        <duration>\(divisions)</duration>"
        xml += "\n        <type>\(typeName)</type>"

        if duration.dotted {
            xml += "\n        <dot/>"
        }
        if duration.doubleDotted {
            xml += "\n        <dot/>"
            xml += "\n        <dot/>"
        }

        return xml
    }

    // MARK: - Clef

    private func exportClef(_ clef: Clef) -> String {
        let (sign, line): (String, Int)
        switch clef {
        case .treble: (sign, line) = ("G", 2)
        case .bass: (sign, line) = ("F", 4)
        case .alto: (sign, line) = ("C", 3)
        case .tenor: (sign, line) = ("C", 4)
        }
        return """

                <clef>
                  <sign>\(sign)</sign>
                  <line>\(line)</line>
                </clef>
        """
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
