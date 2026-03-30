import SwiftUI

// MARK: - Letter Note Input (До, Ре, Ми / C, D, E)

struct LetterInputView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var currentOctave: Int = 4

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

            // Note buttons
            HStack(spacing: 4) {
                ForEach(notes, id: \.0) { pitchName, ruName, enName in
                    Button {
                        let accidental = viewModel.selectedAccidental ?? .natural
                        let pitch = Pitch(name: pitchName, octave: currentOctave, accidental: accidental)
                        viewModel.addNote(pitch: pitch)
                    } label: {
                        VStack(spacing: 2) {
                            Text(enName)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text(ruName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.fill.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
