import SwiftUI

// MARK: - Note Input Toolbar

struct NoteToolbarView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @EnvironmentObject var themeManager: ThemeManager

    private var isEditing: Bool {
        viewModel.selectedEventIndex != nil
    }

    private var isChordSelected: Bool {
        if case .chord = viewModel.selectedEvent?.type { return true }
        return false
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

                    // Dynamics
                    dynamicButtons

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
            Text(String(localized: "Edit"))
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
            ForEach([Articulation.staccato, .legato, .accent, .tenuto, .marcato, .fermata], id: \.self) { art in
                let isActive = viewModel.selectedEvent?.articulations.contains(art) == true
                NoteToolbarButton(
                    icon: nil,
                    label: art.displaySymbol,
                    isActive: isActive,
                    fontSize: 14
                ) { viewModel.updateSelectedEventArticulation(art) }
            }

            Divider().frame(height: 30)

            // Dynamics
            ForEach([DynamicMarking.pp, .p, .mp, .mf, .f, .ff], id: \.self) { dyn in
                let isActive = viewModel.selectedEvent?.dynamic == dyn
                NoteToolbarButton(
                    icon: nil,
                    label: dyn.displayName,
                    isActive: isActive,
                    fontSize: 14
                ) { viewModel.updateSelectedEventDynamic(dyn) }
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

            // Copy / Cut / Paste
            NoteToolbarButton(
                icon: "doc.on.doc",
                label: "Коп.",
                isActive: false,
                tooltip: "Копировать выбранную ноту"
            ) { viewModel.copySelectedEvent() }

            NoteToolbarButton(
                icon: "scissors",
                label: "Выр.",
                isActive: false,
                tooltip: "Вырезать выбранную ноту"
            ) { viewModel.cutSelectedEvent() }

            NoteToolbarButton(
                icon: "doc.on.clipboard",
                label: "Вст.",
                isActive: false,
                tooltip: "Вставить из буфера"
            ) { viewModel.paste() }

            Divider().frame(height: 30)

            // Transpose
            NoteToolbarButton(
                icon: "arrow.up",
                label: "+1",
                isActive: false,
                tooltip: "Транспозиция вверх на полутон"
            ) { viewModel.transposeSelectedEvent(semitones: 1) }

            NoteToolbarButton(
                icon: "arrow.down",
                label: "-1",
                isActive: false,
                tooltip: "Транспозиция вниз на полутон"
            ) { viewModel.transposeSelectedEvent(semitones: -1) }

            NoteToolbarButton(
                icon: "arrow.up.to.line",
                label: "Окт↑",
                isActive: false,
                tooltip: "Транспозиция вверх на октаву"
            ) { viewModel.transposeSelectedEvent(semitones: 12) }

            NoteToolbarButton(
                icon: "arrow.down.to.line",
                label: "Окт↓",
                isActive: false,
                tooltip: "Транспозиция вниз на октаву"
            ) { viewModel.transposeSelectedEvent(semitones: -12) }

            Divider().frame(height: 30)

            // Chord editing: remove single pitch
            if isChordSelected {
                NoteToolbarButton(
                    icon: "minus.circle",
                    label: "Удл.н.",
                    isActive: false,
                    tooltip: "Удалить выбранную ноту из аккорда"
                ) {
                    if let pitchIdx = viewModel.selectedPitchIndex {
                        viewModel.removePitchFromChord(at: pitchIdx)
                    }
                }
            }

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
                icon: "hand.tap",
                label: "Навиг.",
                isActive: viewModel.inputMode == .navigate,
                tooltip: "Навигация — выбор тактов и нот"
            ) { viewModel.inputMode = .navigate }

            NoteToolbarButton(
                icon: "pencil",
                label: "Нота",
                isActive: viewModel.inputMode == .note,
                tooltip: "Ввод нот — нажми на стан для размещения"
            ) { viewModel.inputMode = .note }

            NoteToolbarButton(
                icon: "pause.fill",
                label: "Пауза",
                isActive: viewModel.inputMode == .rest,
                tooltip: "Ввод пауз (rest) — нажми для вставки"
            ) { viewModel.inputMode = .rest }
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
                    fontSize: 18,
                    tooltip: durationTooltip(dur)
                ) { viewModel.selectedDuration = dur }
            }
        }
    }

    private func durationTooltip(_ dur: DurationValue) -> String {
        switch dur {
        case .whole: return "Целая (semibreve) — 4 доли"
        case .half: return "Половинная (minim) — 2 доли"
        case .quarter: return "Четвертная (crotchet/semiminima) — 1 доля"
        case .eighth: return "Восьмая (quaver/croma) — ½ доли"
        case .sixteenth: return "Шестнадцатая (semiquaver/semicroma) — ¼ доли"
        case .thirtySecond: return "Тридцать вторая (demisemiquaver/biscroma) — ⅛ доли"
        }
    }

    // MARK: - Modifiers

    private var modifierButtons: some View {
        HStack(spacing: 4) {
            NoteToolbarButton(
                icon: nil,
                label: "•",
                isActive: viewModel.isDotted,
                fontSize: 20,
                tooltip: "Точка (dotted) — увеличивает длительность в 1.5 раза"
            ) {
                viewModel.isDotted.toggle()
                if viewModel.isDotted { viewModel.isDoubleDotted = false }
            }

            NoteToolbarButton(
                icon: nil,
                label: "••",
                isActive: viewModel.isDoubleDotted,
                fontSize: 16,
                tooltip: "Двойная точка (double dotted) — увеличивает в 1.75 раза"
            ) {
                viewModel.isDoubleDotted.toggle()
                if viewModel.isDoubleDotted { viewModel.isDotted = false }
            }

            NoteToolbarButton(
                icon: "link",
                label: "Лига",
                isActive: viewModel.tieNext,
                tooltip: "Залиговка (tie) — связать с следующей нотой"
            ) { viewModel.tieNext.toggle() }

            NoteToolbarButton(
                icon: nil,
                label: "⁀",
                isActive: viewModel.slurActive,
                fontSize: 16,
                tooltip: "Фразировочная лига (slur) — legato"
            ) { viewModel.slurActive.toggle() }

            NoteToolbarButton(
                icon: nil,
                label: stemDirectionLabel,
                isActive: viewModel.stemDirection != .auto,
                fontSize: 14,
                tooltip: "Направление штиля: авто / вверх / вниз"
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
                    fontSize: 16,
                    tooltip: accidentalTooltip(acc)
                ) {
                    if viewModel.selectedAccidental == acc {
                        viewModel.selectedAccidental = nil
                    } else {
                        viewModel.selectedAccidental = acc
                    }
                }
            }
        }
    }

    private func accidentalTooltip(_ acc: Accidental) -> String {
        switch acc {
        case .doubleFlat: return "Дубль-бемоль (doppio bemolle) — понижение на 2 полутона"
        case .flat: return "Бемоль (bemolle) — понижение на полутон"
        case .natural: return "Бекар (bequadro) — отмена знака альтерации"
        case .sharp: return "Диез (diesis) — повышение на полутон"
        case .doubleSharp: return "Дубль-диез (doppio diesis) — повышение на 2 полутона"
        }
    }

    // MARK: - Articulations

    private var articulationButtons: some View {
        HStack(spacing: 2) {
            ForEach([Articulation.staccato, .legato, .accent, .tenuto, .marcato, .fermata], id: \.self) { art in
                NoteToolbarButton(
                    icon: nil,
                    label: art.displaySymbol,
                    isActive: viewModel.selectedArticulation == art,
                    fontSize: 14,
                    tooltip: articulationTooltip(art)
                ) {
                    viewModel.selectedArticulation = viewModel.selectedArticulation == art ? nil : art
                }
            }
        }
    }

    private func articulationTooltip(_ art: Articulation) -> String {
        switch art {
        case .staccato: return "Стаккато (staccato) — коротко, отрывисто"
        case .legato: return "Легато (legato) — связно, плавно"
        case .accent: return "Акцент (accento) — подчёркнутый удар"
        case .tenuto: return "Тенуто (tenuto) — выдержанно, полная длительность"
        case .marcato: return "Маркато (marcato) — подчёркнуто, сильнее акцента"
        case .fermata: return "Фермата (fermata) — задержка, свободная длительность"
        }
    }

    // MARK: - Dynamics

    private var dynamicButtons: some View {
        HStack(spacing: 2) {
            ForEach([DynamicMarking.pp, .p, .mp, .mf, .f, .ff], id: \.self) { dyn in
                NoteToolbarButton(
                    icon: nil,
                    label: dyn.displayName,
                    isActive: viewModel.selectedDynamic == dyn,
                    fontSize: 14,
                    tooltip: dynamicTooltip(dyn)
                ) {
                    viewModel.selectedDynamic = viewModel.selectedDynamic == dyn ? nil : dyn
                }
            }
        }
    }

    private func dynamicTooltip(_ dyn: DynamicMarking) -> String {
        switch dyn {
        case .ppp: return "Pianississimo — предельно тихо"
        case .pp: return "Pianissimo (пианиссимо) — очень тихо"
        case .p: return "Piano (пиано) — тихо"
        case .mp: return "Mezzo piano (меццо-пиано) — умеренно тихо"
        case .mf: return "Mezzo forte (меццо-форте) — умеренно громко"
        case .f: return "Forte (форте) — громко"
        case .ff: return "Fortissimo (фортиссимо) — очень громко"
        case .fff: return "Fortississimo — предельно громко"
        case .sfz: return "Sforzando (сфорцандо) — внезапный акцент"
        case .sfp: return "Sforzando piano — акцент с переходом в тихо"
        case .fp: return "Forte piano — громко, затем сразу тихо"
        }
    }

    // MARK: - Playback Technique

    private var techniqueButtons: some View {
        HStack(spacing: 2) {
            let techniques = techniquesForCurrentInstrument
            if !techniques.isEmpty {
                Menu {
                    Button {
                        viewModel.selectedTechnique = nil
                    } label: {
                        HStack {
                            Text(String(localized: "Default"))
                            if viewModel.selectedTechnique == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(techniques, id: \.self) { tech in
                        Button {
                            viewModel.selectedTechnique = tech
                        } label: {
                            HStack {
                                Text(tech.displayName)
                                if viewModel.selectedTechnique == tech {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    NoteToolbarButton(
                        icon: "hand.wave",
                        label: viewModel.selectedTechnique?.italianName ?? "Техн.",
                        isActive: viewModel.selectedTechnique != nil,
                        fontSize: 10,
                        tooltip: "Исполнительская техника (playback technique)"
                    ) {}
                }
            }
        }
    }

    private var techniquesForCurrentInstrument: [PlaybackTechnique] {
        guard let part = viewModel.currentPart else { return [] }
        return PlaybackTechnique.allCases.filter { $0.applicableGroups.contains(part.instrument.group) }
    }

    // MARK: - Strum Pattern

    @State private var showStrumEditor = false

    private var strumButton: some View {
        Group {
            if let part = viewModel.currentPart,
               part.instrument.group == .strings,
               [24, 25].contains(part.instrument.midiProgram) {
                NoteToolbarButton(
                    icon: "guitars",
                    label: "Бой",
                    isActive: false,
                    fontSize: 10,
                    tooltip: "Гитарный бой (strumming pattern)"
                ) { showStrumEditor = true }
                .sheet(isPresented: $showStrumEditor) {
                    StrumPatternEditorSheet(viewModel: viewModel)
                        .presentationDetents([.medium])
                }
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 4) {
            // Playback Technique
            techniqueButtons

            // Strum Pattern (guitar only)
            strumButton

            Divider().frame(height: 30)

            // Voice selector
            ForEach(VoiceLayer.allCases, id: \.self) { voice in
                NoteToolbarButton(
                    icon: nil,
                    label: "\(voice.rawValue)",
                    isActive: viewModel.selectedVoice == voice,
                    fontSize: 14,
                    tooltip: "\(voice.displayName) — независимый голос на одном нотоносце"
                ) { viewModel.selectVoice(voice) }
            }

            Divider().frame(height: 30)

            // Lyric button
            NoteToolbarButton(
                icon: "text.below.photo",
                label: "Текст",
                isActive: viewModel.isEditingLyric,
                tooltip: "Подтекстовка (lyrics) — текст под нотами"
            ) { viewModel.startLyricEditing() }

            // Paste (available in input mode without selection)
            if viewModel.hasClipboardContent {
                NoteToolbarButton(
                    icon: "doc.on.clipboard",
                    label: "Вст.",
                    isActive: false,
                    tooltip: "Вставить из буфера (paste)"
                ) { viewModel.paste() }
            }

            Button {
                viewModel.deleteLastEvent()
            } label: {
                Image(systemName: "delete.backward")
                    .frame(width: 32, height: 32)
                    .help("Удалить последнюю ноту")
            }

            Button {
                viewModel.advanceMeasure()
            } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 32, height: 32)
                    .help("Следующий такт")
            }

            Button {
                viewModel.previousMeasure()
            } label: {
                Image(systemName: "backward.fill")
                    .frame(width: 32, height: 32)
                    .help("Предыдущий такт")
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
    var tooltip: String? = nil
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
        .help(tooltip ?? label)
    }
}
