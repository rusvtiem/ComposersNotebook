import SwiftUI

// MARK: - Note Input Toolbar

struct NoteToolbarView: View {
    @ObservedObject var viewModel: ScoreViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Input mode
                modeButtons

                Divider().frame(height: 30)

                // Duration
                durationButtons

                Divider().frame(height: 30)

                // Modifiers
                modifierButtons

                Divider().frame(height: 30)

                // Accidentals
                accidentalButtons

                Divider().frame(height: 30)

                // Articulations
                articulationButtons

                Divider().frame(height: 30)

                // Actions
                actionButtons
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    // MARK: - Mode

    private var modeButtons: some View {
        HStack(spacing: 4) {
            NoteToolbarButton(
                icon: "pencil",
                label: "Нота",
                isActive: viewModel.inputMode == .note
            ) { viewModel.inputMode = .note }

            NoteToolbarButton(
                icon: "pause.fill",
                label: "Пауза",
                isActive: viewModel.inputMode == .rest
            ) {
                viewModel.inputMode = .rest
                viewModel.addRest()
                viewModel.inputMode = .note
            }
        }
    }

    // MARK: - Duration

    private var durationButtons: some View {
        HStack(spacing: 2) {
            ForEach(DurationValue.allCases, id: \.self) { dur in
                NoteToolbarButton(
                    icon: nil,
                    label: dur.symbol,
                    isActive: viewModel.selectedDuration == dur,
                    fontSize: 18
                ) { viewModel.selectedDuration = dur }
            }
        }
    }

    // MARK: - Modifiers

    private var modifierButtons: some View {
        HStack(spacing: 4) {
            NoteToolbarButton(
                icon: nil,
                label: "•",
                isActive: viewModel.isDotted,
                fontSize: 20
            ) { viewModel.isDotted.toggle() }

            NoteToolbarButton(
                icon: "link",
                label: "Лига",
                isActive: viewModel.tieNext
            ) { viewModel.tieNext.toggle() }

            NoteToolbarButton(
                icon: nil,
                label: "⁀",
                isActive: viewModel.slurActive,
                fontSize: 16
            ) { viewModel.slurActive.toggle() }
        }
    }

    // MARK: - Accidentals

    private var accidentalButtons: some View {
        HStack(spacing: 2) {
            ForEach([Accidental.flat, .natural, .sharp], id: \.self) { acc in
                NoteToolbarButton(
                    icon: nil,
                    label: acc.displaySymbol,
                    isActive: viewModel.selectedAccidental == acc,
                    fontSize: 16
                ) { viewModel.selectedAccidental = acc }
            }
        }
    }

    // MARK: - Articulations

    private var articulationButtons: some View {
        HStack(spacing: 2) {
            ForEach([Articulation.staccato, .accent, .tenuto, .fermata], id: \.self) { art in
                NoteToolbarButton(
                    icon: nil,
                    label: art.displaySymbol,
                    isActive: viewModel.selectedArticulation == art,
                    fontSize: 14
                ) {
                    viewModel.selectedArticulation = viewModel.selectedArticulation == art ? nil : art
                }
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.deleteLastEvent()
            } label: {
                Image(systemName: "delete.backward")
                    .frame(width: 32, height: 32)
            }

            Button {
                viewModel.advanceMeasure()
            } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 32, height: 32)
            }

            Button {
                viewModel.previousMeasure()
            } label: {
                Image(systemName: "backward.fill")
                    .frame(width: 32, height: 32)
            }
        }
    }
}

// MARK: - Toolbar Toggle Button

struct NoteToolbarButton: View {
    let icon: String?
    let label: String
    let isActive: Bool
    var fontSize: CGFloat = 11
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let icon = icon {
                    VStack(spacing: 2) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                        Text(label)
                            .font(.system(size: 8))
                    }
                } else {
                    Text(label)
                        .font(.system(size: fontSize))
                }
            }
            .frame(minWidth: 32, minHeight: 32)
            .padding(.horizontal, 4)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundColor(isActive ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
