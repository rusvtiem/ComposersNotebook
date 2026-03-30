import SwiftUI

// MARK: - Note Input Toolbar

struct NoteToolbarView: View {
    @ObservedObject var viewModel: ScoreViewModel

    private var isEditing: Bool {
        viewModel.selectedEventIndex != nil
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if isEditing {
                    editModeControls
                } else {
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(isEditing ? Color.blue.opacity(0.05) : Color.clear)
        .background(.bar)
    }

    // MARK: - Edit Mode

    private var editModeControls: some View {
        HStack(spacing: 4) {
            // Label
            Text("Ред.")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue)
                .frame(width: 32)

            Divider().frame(height: 30)

            // Duration change
            ForEach(DurationValue.allCases, id: \.self) { dur in
                let isActive = viewModel.selectedEvent?.duration.value == dur
                NoteToolbarButton(
                    icon: nil,
                    label: dur.symbol,
                    isActive: isActive,
                    fontSize: 18
                ) { viewModel.updateSelectedEventDuration(dur) }
            }

            Divider().frame(height: 30)

            // Accidentals
            ForEach([Accidental.flat, .natural, .sharp], id: \.self) { acc in
                let isActive = viewModel.selectedEvent?.pitches.first?.accidental == acc
                NoteToolbarButton(
                    icon: nil,
                    label: acc.displaySymbol,
                    isActive: isActive,
                    fontSize: 16
                ) { viewModel.updateSelectedEventAccidental(acc) }
            }

            Divider().frame(height: 30)

            // Articulations
            ForEach([Articulation.staccato, .accent, .tenuto, .fermata], id: \.self) { art in
                let isActive = viewModel.selectedEvent?.articulations.contains(art) == true
                NoteToolbarButton(
                    icon: nil,
                    label: art.displaySymbol,
                    isActive: isActive,
                    fontSize: 14
                ) { viewModel.updateSelectedEventArticulation(art) }
            }

            Divider().frame(height: 30)

            // Tie / Slur
            NoteToolbarButton(
                icon: "link",
                label: "Лига",
                isActive: viewModel.selectedEvent?.tiedToNext == true
            ) { viewModel.toggleSelectedEventTie() }

            NoteToolbarButton(
                icon: nil,
                label: "⁀",
                isActive: viewModel.selectedEvent?.slurStart == true,
                fontSize: 16
            ) { viewModel.toggleSelectedEventSlur() }

            // Stem direction
            NoteToolbarButton(
                icon: nil,
                label: editStemLabel,
                isActive: viewModel.selectedEvent?.stemDirection != .auto,
                fontSize: 14
            ) {
                guard let event = viewModel.selectedEvent else { return }
                let next: StemDirection
                switch event.stemDirection {
                case .auto: next = .up
                case .up: next = .down
                case .down: next = .auto
                }
                viewModel.updateSelectedEventStemDirection(next)
            }

            Divider().frame(height: 30)

            // Delete selected note
            Button {
                viewModel.deleteSelectedEvent()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
            }

            // Deselect
            Button {
                viewModel.deselectEvent()
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var editStemLabel: String {
        guard let event = viewModel.selectedEvent else { return "↕" }
        switch event.stemDirection {
        case .auto: return "↕"
        case .up: return "↑"
        case .down: return "↓"
        }
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

            // Stem direction toggle
            NoteToolbarButton(
                icon: nil,
                label: stemDirectionLabel,
                isActive: viewModel.stemDirection != .auto,
                fontSize: 14
            ) {
                switch viewModel.stemDirection {
                case .auto: viewModel.stemDirection = .up
                case .up: viewModel.stemDirection = .down
                case .down: viewModel.stemDirection = .auto
                }
            }
        }
    }

    private var stemDirectionLabel: String {
        switch viewModel.stemDirection {
        case .auto: return "↕"
        case .up: return "↑"
        case .down: return "↓"
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
                ) {
                    if viewModel.selectedAccidental == acc {
                        viewModel.selectedAccidental = nil  // deselect = no accidental
                    } else {
                        viewModel.selectedAccidental = acc
                    }
                }
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
