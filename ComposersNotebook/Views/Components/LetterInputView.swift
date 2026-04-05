import SwiftUI

// MARK: - Letter Input Mode

enum LetterInputMode: String, CaseIterable {
    case note = "Нота"
    case chord = "Аккорд"
    case chord7 = "Септ."
}

// MARK: - Letter Note Input (До, Ре, Ми / C, D, E + Chords)

struct LetterInputView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var currentOctave: Int = 4
    @State private var letterMode: LetterInputMode = .note

    private let notes: [(PitchName, String, String)] = [
        (.C, "До", "C"),
        (.D, "Ре", "D"),
        (.E, "Ми", "E"),
        (.F, "Фа", "F"),
        (.G, "Соль", "G"),
        (.A, "Ля", "A"),
        (.B, "Си", "B"),
    ]

    var body: some View {
        VStack(spacing: 4) {
            // Top row: octave + mode selector
            HStack {
                Button {
                    if currentOctave > 1 { currentOctave -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 24)
                }
                .disabled(currentOctave <= 1)

                Text("Октава \(currentOctave)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(width: 80)

                Button {
                    if currentOctave < 7 { currentOctave += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 24)
                }
                .disabled(currentOctave >= 7)

                Spacer()

                // Note / Chord toggle
                ForEach(LetterInputMode.allCases, id: \.self) { mode in
                    Button {
                        letterMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(letterMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(Capsule())
                            .foregroundColor(letterMode == mode ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            // Note/Chord buttons
            HStack(spacing: 4) {
                ForEach(notes, id: \.0) { pitchName, ruName, enName in
                    Button {
                        inputNote(pitchName)
                    } label: {
                        VStack(spacing: 1) {
                            Text(enName)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            if letterMode == .chord || letterMode == .chord7 {
                                Text(chordLabel(for: pitchName) + (letterMode == .chord7 ? "7" : ""))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.accentColor)
                            } else {
                                Text(ruName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(letterMode != .note ? Color.accentColor.opacity(0.05) : Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Input Logic

    private func inputNote(_ pitchName: PitchName) {
        let accidental = viewModel.selectedAccidental ?? .natural

        switch letterMode {
        case .note:
            let pitch = Pitch(name: pitchName, octave: currentOctave, accidental: accidental)
            viewModel.addNote(pitch: pitch)
        case .chord:
            let chord = buildDiatonicTriad(root: pitchName, octave: currentOctave)
            viewModel.addChord(pitches: chord)
        case .chord7:
            let chord = buildDiatonicSeventh(root: pitchName, octave: currentOctave)
            viewModel.addChord(pitches: chord)
        }
    }

    // MARK: - Diatonic Chord Building

    /// Build a triad on the given root using the current key signature's scale
    private func buildDiatonicTriad(root: PitchName, octave: Int) -> [Pitch] {
        let ks = viewModel.effectiveKeySignature
        let scale = diatonicScale(fifths: ks.fifths, mode: ks.mode)

        // Find the accidental for root, third, fifth in the scale
        let scaleNotes: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
        let rootIndex = scaleNotes.firstIndex(of: root)!

        let thirdIndex = (rootIndex + 2) % 7
        let fifthIndex = (rootIndex + 4) % 7

        let rootPitch = Pitch(name: root, octave: octave, accidental: scale[root] ?? .natural)
        let thirdOctave = thirdIndex < rootIndex ? octave + 1 : octave
        let thirdPitch = Pitch(name: scaleNotes[thirdIndex], octave: thirdOctave, accidental: scale[scaleNotes[thirdIndex]] ?? .natural)
        let fifthOctave = fifthIndex <= rootIndex ? octave + 1 : octave
        let fifthPitch = Pitch(name: scaleNotes[fifthIndex], octave: fifthOctave, accidental: scale[scaleNotes[fifthIndex]] ?? .natural)

        return [rootPitch, thirdPitch, fifthPitch]
    }

    /// Build a seventh chord on the given root using the current key signature's scale
    private func buildDiatonicSeventh(root: PitchName, octave: Int) -> [Pitch] {
        let ks = viewModel.effectiveKeySignature
        let scale = diatonicScale(fifths: ks.fifths, mode: ks.mode)
        let scaleNotes: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
        let rootIndex = scaleNotes.firstIndex(of: root)!

        let thirdIndex = (rootIndex + 2) % 7
        let fifthIndex = (rootIndex + 4) % 7
        let seventhIndex = (rootIndex + 6) % 7

        let rootPitch = Pitch(name: root, octave: octave, accidental: scale[root] ?? .natural)
        let thirdOctave = thirdIndex < rootIndex ? octave + 1 : octave
        let thirdPitch = Pitch(name: scaleNotes[thirdIndex], octave: thirdOctave, accidental: scale[scaleNotes[thirdIndex]] ?? .natural)
        let fifthOctave = fifthIndex <= rootIndex ? octave + 1 : octave
        let fifthPitch = Pitch(name: scaleNotes[fifthIndex], octave: fifthOctave, accidental: scale[scaleNotes[fifthIndex]] ?? .natural)
        let seventhOctave = seventhIndex <= rootIndex ? octave + 1 : octave
        let seventhPitch = Pitch(name: scaleNotes[seventhIndex], octave: seventhOctave, accidental: scale[scaleNotes[seventhIndex]] ?? .natural)

        return [rootPitch, thirdPitch, fifthPitch, seventhPitch]
    }

    /// Returns the accidentals for each note in the scale based on key signature (fifths)
    private func diatonicScale(fifths: Int, mode: KeySignatureType) -> [PitchName: Accidental] {
        var accidentals: [PitchName: Accidental] = [:]

        // Sharp order: F C G D A E B
        let sharpOrder: [PitchName] = [.F, .C, .G, .D, .A, .E, .B]
        // Flat order: B E A D G C F
        let flatOrder: [PitchName] = [.B, .E, .A, .D, .G, .C, .F]

        if fifths > 0 {
            for i in 0..<min(fifths, 7) {
                accidentals[sharpOrder[i]] = .sharp
            }
        } else if fifths < 0 {
            for i in 0..<min(-fifths, 7) {
                accidentals[flatOrder[i]] = .flat
            }
        }

        return accidentals
    }

    /// Label showing chord quality (maj/min/dim) for the button
    private func chordLabel(for root: PitchName) -> String {
        let ks = viewModel.effectiveKeySignature
        let scale = diatonicScale(fifths: ks.fifths, mode: ks.mode)
        let scaleNotes: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
        let rootIndex = scaleNotes.firstIndex(of: root)!

        // Calculate intervals in semitones
        let rootSemitone = semitonesFromC(root, accidental: scale[root] ?? .natural)
        let thirdName = scaleNotes[(rootIndex + 2) % 7]
        let thirdSemitone = semitonesFromC(thirdName, accidental: scale[thirdName] ?? .natural)
        let fifthName = scaleNotes[(rootIndex + 4) % 7]
        let fifthSemitone = semitonesFromC(fifthName, accidental: scale[fifthName] ?? .natural)

        let thirdInterval = (thirdSemitone - rootSemitone + 12) % 12
        let fifthInterval = (fifthSemitone - rootSemitone + 12) % 12

        if thirdInterval == 4 && fifthInterval == 7 { return "мажор" }
        if thirdInterval == 3 && fifthInterval == 7 { return "минор" }
        if thirdInterval == 3 && fifthInterval == 6 { return "ум." }
        if thirdInterval == 4 && fifthInterval == 8 { return "ув." }
        return ""
    }

    private func semitonesFromC(_ name: PitchName, accidental: Accidental) -> Int {
        let base: [PitchName: Int] = [.C: 0, .D: 2, .E: 4, .F: 5, .G: 7, .A: 9, .B: 11]
        return (base[name] ?? 0) + accidental.semitoneOffset
    }
}
