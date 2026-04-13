import SwiftUI

struct StrumPatternEditorSheet: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) var dismiss
    @State private var pattern: StrumPattern
    @State private var beatCount: Int

    init(viewModel: ScoreViewModel) {
        self.viewModel = viewModel
        let existing = viewModel.selectedEvent?.strumPattern ?? .basicAlternating
        _pattern = State(initialValue: existing)
        _beatCount = State(initialValue: existing.beats.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(String(localized: "Strum Pattern"))
                    .font(.headline)

                // Beat count
                HStack {
                    Text(String(localized: "Beats:"))
                        .font(.subheadline)
                    Stepper("\(beatCount)", value: $beatCount, in: 1...16)
                        .onChange(of: beatCount) { _, newValue in
                            adjustBeats(to: newValue)
                        }
                }
                .padding(.horizontal)

                // Pattern grid
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pattern.beats.enumerated()), id: \.offset) { index, beat in
                            beatColumn(index: index, beat: beat)
                        }
                    }
                    .padding(.horizontal)
                }

                // Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Presets"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            presetButton("↓", pattern: .basicDown)
                            presetButton("↓↑", pattern: .basicAlternating)
                            presetButton("↓ ↓↑↑↓", pattern: StrumPattern(beats: [
                                .init(direction: .down, strings: all6, accent: true),
                                .init(direction: .mute, strings: all6, accent: false),
                                .init(direction: .down, strings: all6, accent: false),
                                .init(direction: .up, strings: all6, accent: false),
                                .init(direction: .up, strings: all6, accent: false),
                                .init(direction: .down, strings: all6, accent: true)
                            ]))
                            presetButton("↓↑x↑↓↑", pattern: StrumPattern(beats: [
                                .init(direction: .down, strings: all6, accent: true),
                                .init(direction: .up, strings: all6, accent: false),
                                .init(direction: .mute, strings: all6, accent: false),
                                .init(direction: .up, strings: all6, accent: false),
                                .init(direction: .down, strings: all6, accent: true),
                                .init(direction: .up, strings: all6, accent: false)
                            ]))
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding(.top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply")) {
                        viewModel.setStrumPattern(pattern)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private var all6: [Bool] { [true, true, true, true, true, true] }

    private func beatColumn(index: Int, beat: StrumPattern.StrumBeat) -> some View {
        VStack(spacing: 6) {
            // Direction
            Button {
                cycleDirection(at: index)
            } label: {
                Text(directionSymbol(beat.direction))
                    .font(.system(size: 24, weight: beat.accent ? .bold : .regular))
                    .frame(width: 40, height: 40)
                    .background(beat.accent ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Accent toggle
            Button {
                pattern.beats[index].accent.toggle()
            } label: {
                Text(">")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(beat.accent ? .accentColor : .secondary)
                    .frame(width: 40, height: 24)
                    .background(beat.accent ? Color.accentColor.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Beat number
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func directionSymbol(_ dir: StrumPattern.StrumDirection) -> String {
        switch dir {
        case .down: return "↓"
        case .up: return "↑"
        case .mute: return "×"
        }
    }

    private func cycleDirection(at index: Int) {
        switch pattern.beats[index].direction {
        case .down: pattern.beats[index].direction = .up
        case .up: pattern.beats[index].direction = .mute
        case .mute: pattern.beats[index].direction = .down
        }
    }

    private func adjustBeats(to count: Int) {
        while pattern.beats.count < count {
            let dir: StrumPattern.StrumDirection = pattern.beats.count % 2 == 0 ? .down : .up
            pattern.beats.append(.init(direction: dir, strings: all6, accent: false))
        }
        while pattern.beats.count > count {
            pattern.beats.removeLast()
        }
    }

    private func presetButton(_ label: String, pattern preset: StrumPattern) -> some View {
        Button {
            pattern = preset
            beatCount = preset.beats.count
        } label: {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
