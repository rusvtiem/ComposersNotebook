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

        // Notes
        for event in measure.events {
            xml += exportNoteEvent(event)
        }

        // Barline
        if measure.barlineEnd != .regular {
            xml += exportBarline(measure.barlineEnd)
        }

        xml += "\n    </measure>"
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
