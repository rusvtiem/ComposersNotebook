import SwiftUI

// MARK: - Piano Keyboard with Multitouch Support

struct PianoKeyboardView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var currentOctave: Int = 4
    @State private var pressedKeys: Set<String> = []  // "C4", "D#5" etc.

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

                Text(String(localized: "Octave \(currentOctave)"))
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

            // Keys with multitouch
            GeometryReader { geo in
                let whiteKeyWidth = geo.size.width / 14  // 2 octaves
                let blackKeyWidth = whiteKeyWidth * 0.65
                let whiteKeyHeight = geo.size.height - 4

                MultitouchPianoOverlay(
                    viewModel: viewModel,
                    currentOctave: currentOctave,
                    whiteKeyWidth: whiteKeyWidth,
                    blackKeyWidth: blackKeyWidth,
                    whiteKeyHeight: whiteKeyHeight,
                    pressedKeys: $pressedKeys
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay {
                    ZStack(alignment: .topLeading) {
                        // White keys (2 octaves)
                        HStack(spacing: 1) {
                            ForEach(0..<2, id: \.self) { octaveOffset in
                                ForEach(whiteKeys, id: \.self) { pitchName in
                                    let octave = currentOctave + octaveOffset
                                    let keyId = "\(pitchName.englishName)\(octave)"

                                    WhiteKeyView(
                                        pitchName: pitchName,
                                        width: whiteKeyWidth - 1,
                                        height: whiteKeyHeight,
                                        isPressed: pressedKeys.contains(keyId)
                                    )
                                }
                            }
                        }

                        // Black keys (2 octaves)
                        ForEach(0..<2, id: \.self) { octaveOffset in
                            ForEach(blackKeyMap, id: \.0) { pitchName, accidental, position in
                                let octave = currentOctave + octaveOffset
                                let keyId = "\(pitchName.englishName)#\(octave)"
                                let xOffset = (CGFloat(octaveOffset) * 7 + position + 1) * whiteKeyWidth - blackKeyWidth / 2

                                BlackKeyView(
                                    width: blackKeyWidth,
                                    height: whiteKeyHeight * 0.6,
                                    isPressed: pressedKeys.contains(keyId)
                                )
                                .offset(x: xOffset)
                            }
                        }
                    }
                    .allowsHitTesting(false) // Visual only — touches handled by overlay
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Multitouch Piano Overlay (UIKit for simultaneous touches)

struct MultitouchPianoOverlay: UIViewRepresentable {
    let viewModel: ScoreViewModel
    let currentOctave: Int
    let whiteKeyWidth: CGFloat
    let blackKeyWidth: CGFloat
    let whiteKeyHeight: CGFloat
    @Binding var pressedKeys: Set<String>

    func makeUIView(context: Context) -> MultitouchPianoUIView {
        let view = MultitouchPianoUIView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MultitouchPianoUIView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.currentOctave = currentOctave
        context.coordinator.whiteKeyWidth = whiteKeyWidth
        context.coordinator.blackKeyWidth = blackKeyWidth
        context.coordinator.whiteKeyHeight = whiteKeyHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, currentOctave: currentOctave,
                    whiteKeyWidth: whiteKeyWidth, blackKeyWidth: blackKeyWidth,
                    whiteKeyHeight: whiteKeyHeight, pressedKeys: $pressedKeys)
    }

    class Coordinator: NSObject, MultitouchPianoDelegate {
        var viewModel: ScoreViewModel
        var currentOctave: Int
        var whiteKeyWidth: CGFloat
        var blackKeyWidth: CGFloat
        var whiteKeyHeight: CGFloat
        var pressedKeys: Binding<Set<String>>
        private var activeTouches: [UITouch: Pitch] = [:]

        private let whiteKeys: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
        private let blackKeyPositions: [(PitchName, Accidental, CGFloat)] = [
            (.C, .sharp, 0), (.D, .sharp, 1), (.F, .sharp, 3),
            (.G, .sharp, 4), (.A, .sharp, 5)
        ]

        init(viewModel: ScoreViewModel, currentOctave: Int,
             whiteKeyWidth: CGFloat, blackKeyWidth: CGFloat,
             whiteKeyHeight: CGFloat, pressedKeys: Binding<Set<String>>) {
            self.viewModel = viewModel
            self.currentOctave = currentOctave
            self.whiteKeyWidth = whiteKeyWidth
            self.blackKeyWidth = blackKeyWidth
            self.whiteKeyHeight = whiteKeyHeight
            self.pressedKeys = pressedKeys
        }

        func touchesBegan(_ touches: Set<UITouch>, in view: UIView) {
            for touch in touches {
                let location = touch.location(in: view)
                if let pitch = pitchFromLocation(location) {
                    activeTouches[touch] = pitch
                    let keyId = keyIdentifier(pitch)
                    Task { @MainActor in
                        pressedKeys.wrappedValue.insert(keyId)
                        viewModel.addNote(pitch: pitch)
                    }
                }
            }
        }

        func touchesEnded(_ touches: Set<UITouch>, in view: UIView) {
            for touch in touches {
                if let pitch = activeTouches.removeValue(forKey: touch) {
                    let keyId = keyIdentifier(pitch)
                    Task { @MainActor in
                        pressedKeys.wrappedValue.remove(keyId)
                    }
                }
            }
        }

        func touchesCancelled(_ touches: Set<UITouch>, in view: UIView) {
            touchesEnded(touches, in: view)
        }

        private func keyIdentifier(_ pitch: Pitch) -> String {
            if pitch.accidental == .sharp {
                return "\(pitch.name.englishName)#\(pitch.octave)"
            }
            return "\(pitch.name.englishName)\(pitch.octave)"
        }

        private func pitchFromLocation(_ point: CGPoint) -> Pitch? {
            // Check black keys first (they're on top)
            let blackKeyHeight = whiteKeyHeight * 0.6
            if point.y < blackKeyHeight {
                for octaveOffset in 0..<2 {
                    for (pitchName, accidental, position) in blackKeyPositions {
                        let centerX = (CGFloat(octaveOffset) * 7 + position + 1) * whiteKeyWidth
                        if abs(point.x - centerX) < blackKeyWidth / 2 {
                            return Pitch(name: pitchName, octave: currentOctave + octaveOffset, accidental: accidental)
                        }
                    }
                }
            }

            // White keys
            let keyIndex = Int(point.x / whiteKeyWidth)
            guard keyIndex >= 0, keyIndex < 14 else { return nil }
            let octaveOffset = keyIndex / 7
            let noteIndex = keyIndex % 7
            guard noteIndex < whiteKeys.count else { return nil }
            return Pitch(name: whiteKeys[noteIndex], octave: currentOctave + octaveOffset)
        }
    }
}

// MARK: - UIView for multitouch

protocol MultitouchPianoDelegate: AnyObject {
    func touchesBegan(_ touches: Set<UITouch>, in view: UIView)
    func touchesEnded(_ touches: Set<UITouch>, in view: UIView)
    func touchesCancelled(_ touches: Set<UITouch>, in view: UIView)
}

class MultitouchPianoUIView: UIView {
    weak var delegate: MultitouchPianoDelegate?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.touchesBegan(touches, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.touchesEnded(touches, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.touchesCancelled(touches, in: self)
    }
}

// MARK: - White Key

struct WhiteKeyView: View {
    let pitchName: PitchName
    let width: CGFloat
    let height: CGFloat
    var isPressed: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isPressed ? Color.accentColor.opacity(0.3) : Color(.systemBackground))
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
    var isPressed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isPressed ? Color.accentColor : .primary)
            .frame(width: width, height: height)
    }
}
