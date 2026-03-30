import SwiftUI

// MARK: - Piano Keyboard

struct PianoKeyboardView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var currentOctave: Int = 4

    private let whiteKeys: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
    private let blackKeyMap: [(PitchName, Accidental, CGFloat)] = [
        (.C, .sharp, 0),   // between C and D
        (.D, .sharp, 1),   // between D and E
        (.F, .sharp, 3),   // between F and G
        (.G, .sharp, 4),   // between G and A
        (.A, .sharp, 5),   // between A and B
    ]

    var body: some View {
        VStack(spacing: 4) {
            // Octave selector
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
            }
            .padding(.horizontal, 8)

            // Keys
            GeometryReader { geo in
                let whiteKeyWidth = geo.size.width / 14  // 2 octaves
                let blackKeyWidth = whiteKeyWidth * 0.65
                let whiteKeyHeight = geo.size.height - 4

                ZStack(alignment: .topLeading) {
                    // White keys (2 octaves)
                    HStack(spacing: 1) {
                        ForEach(0..<2, id: \.self) { octaveOffset in
                            ForEach(whiteKeys, id: \.self) { pitchName in
                                let octave = currentOctave + octaveOffset

                                WhiteKeyView(
                                    pitchName: pitchName,
                                    width: whiteKeyWidth - 1,
                                    height: whiteKeyHeight
                                )
                                .onTapGesture {
                                    let notePitch = Pitch(name: pitchName, octave: octave, accidental: viewModel.selectedAccidental)
                                    viewModel.addNote(pitch: notePitch)
                                }
                            }
                        }
                    }

                    // Black keys (2 octaves)
                    ForEach(0..<2, id: \.self) { octaveOffset in
                        ForEach(blackKeyMap, id: \.0) { pitchName, accidental, position in
                            let octave = currentOctave + octaveOffset
                            let xOffset = (CGFloat(octaveOffset) * 7 + position + 1) * whiteKeyWidth - blackKeyWidth / 2

                            BlackKeyView(
                                width: blackKeyWidth,
                                height: whiteKeyHeight * 0.6
                            )
                            .offset(x: xOffset)
                            .onTapGesture {
                                let pitch = Pitch(name: pitchName, octave: octave, accidental: accidental)
                                viewModel.addNote(pitch: pitch)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - White Key

struct WhiteKeyView: View {
    let pitchName: PitchName
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                )

            Text(pitchName.displayName)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Black Key

struct BlackKeyView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.primary)
            .frame(width: width, height: height)
    }
}
