import SwiftUI

// MARK: - Measure Properties View
//
// Sheet для редактирования всех свойств текущего выбранного такта.
// Открывается из меню "..." в редакторе партитуры.
//
// Закрывает блок 5 плана Слоя 2 ("Меню редактирования существующих элементов"):
// тип тактовой черты, вольта, rehearsal mark, navigation mark (D.C./D.S./Coda),
// hairpins (cresc/dim), octave shifts (8va/8vb/15ma/15mb), tempo change
// (accel/rit), expression texts (espressivo/dolce/...), multi-measure rest.

struct MeasurePropertiesView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if viewModel.currentMeasure == nil {
                ContentUnavailableView(
                    String(localized: "No measure selected"),
                    systemImage: "music.note.list",
                    description: Text(String(localized: "Tap a measure in the score to select it, then reopen this menu."))
                )
                .navigationTitle(String(localized: "Measure Properties"))
                .toolbar { toolbarDone }
            } else {
                content
                    .navigationTitle(String(localized: "Measure Properties"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarDone }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarDone: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "Done")) { dismiss() }
        }
    }

    private var content: some View {
        List {
            measureHeaderSection
            barlineSection
            voltaSection
            rehearsalMarkSection
            navigationMarkSection
            hairpinsSection
            octaveShiftsSection
            tempoChangeSection
            expressionTextsSection
            multiMeasureRestSection
        }
    }

    // MARK: - Header (current measure info)

    private var measureHeaderSection: some View {
        Section {
            HStack {
                Text(String(localized: "Measure"))
                Spacer()
                Text("#\(viewModel.selectedMeasureIndex + 1)")
                    .foregroundStyle(.secondary)
            }
            if let part = viewModel.currentPart {
                HStack {
                    Text(String(localized: "Part"))
                    Spacer()
                    Text(part.instrument.shortName)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Barline

    private var barlineSection: some View {
        Section(String(localized: "Ending barline")) {
            Picker(
                String(localized: "Type"),
                selection: Binding(
                    get: { viewModel.currentMeasure?.barlineEnd ?? .regular },
                    set: { viewModel.setBarline($0) }
                )
            ) {
                Text(String(localized: "Regular")).tag(BarlineType.regular)
                Text(String(localized: "Double")).tag(BarlineType.double)
                Text(String(localized: "Final")).tag(BarlineType.final_)
                Text(String(localized: "Repeat start")).tag(BarlineType.repeatStart)
                Text(String(localized: "Repeat end")).tag(BarlineType.repeatEnd)
                Text(String(localized: "Repeat both")).tag(BarlineType.repeatBoth)
            }
        }
    }

    // MARK: - Volta

    private var voltaSection: some View {
        let measure = viewModel.currentMeasure
        let hasVolta = measure?.volta != nil

        return Section(String(localized: "Volta (ending bracket)")) {
            Toggle(String(localized: "Has volta"), isOn: Binding(
                get: { hasVolta },
                set: { newValue in
                    if newValue {
                        let m = viewModel.selectedMeasureIndex
                        viewModel.setVolta(Volta(number: 1, startMeasure: m, endMeasure: m))
                    } else {
                        viewModel.setVolta(nil)
                    }
                }
            ))

            if let volta = measure?.volta {
                Stepper(
                    String(format: NSLocalizedString("Volta number: %d", comment: ""), volta.number),
                    value: Binding(
                        get: { volta.number },
                        set: { newVal in
                            viewModel.setVolta(Volta(number: max(1, newVal), startMeasure: volta.startMeasure, endMeasure: volta.endMeasure))
                        }
                    ),
                    in: 1...8
                )
            }
        }
    }

    // MARK: - Rehearsal Mark

    private var rehearsalMarkSection: some View {
        let mark = viewModel.currentMeasure?.rehearsalMark

        return Section(String(localized: "Rehearsal mark")) {
            Toggle(String(localized: "Has rehearsal mark"), isOn: Binding(
                get: { mark != nil },
                set: { newValue in
                    if newValue {
                        viewModel.setRehearsalMark(RehearsalMark(text: "A", style: .boxed))
                    } else {
                        viewModel.setRehearsalMark(nil)
                    }
                }
            ))

            if let mark = mark {
                TextField(
                    String(localized: "Text (A, B, 1, ...)"),
                    text: Binding(
                        get: { mark.text },
                        set: { newText in
                            viewModel.setRehearsalMark(RehearsalMark(text: newText, style: mark.style))
                        }
                    )
                )

                Picker(
                    String(localized: "Style"),
                    selection: Binding(
                        get: { mark.style },
                        set: { newStyle in
                            viewModel.setRehearsalMark(RehearsalMark(text: mark.text, style: newStyle))
                        }
                    )
                ) {
                    Text(String(localized: "Boxed")).tag(RehearsalMark.Style.boxed)
                    Text(String(localized: "Bold")).tag(RehearsalMark.Style.bold)
                    Text(String(localized: "Plain")).tag(RehearsalMark.Style.plain)
                }
            }
        }
    }

    // MARK: - Navigation Mark (D.C./D.S./Coda/Segno/Fine)

    private var navigationMarkSection: some View {
        Section(String(localized: "Navigation mark")) {
            Picker(
                String(localized: "Mark"),
                selection: Binding<NavigationMark?>(
                    get: { viewModel.currentMeasure?.navigationMark },
                    set: { viewModel.setNavigationMark($0) }
                )
            ) {
                Text(String(localized: "None")).tag(NavigationMark?.none)
                ForEach(navigationMarkCases, id: \.self) { mark in
                    Text(mark.displayString).tag(Optional(mark))
                }
            }
        }
    }

    private var navigationMarkCases: [NavigationMark] {
        [.segno, .coda, .dcAlFine, .dcAlCoda, .dsAlFine, .dsAlCoda, .fine]
    }

    // MARK: - Hairpins (crescendo/diminuendo)

    private var hairpinsSection: some View {
        let hairpins = viewModel.currentMeasure?.hairpins ?? []

        return Section(String(localized: "Crescendo / Diminuendo (hairpins)")) {
            ForEach(hairpins) { hairpin in
                HairpinRow(
                    hairpin: hairpin,
                    onUpdate: { type, start, end in
                        viewModel.updateHairpin(id: hairpin.id, type: type, startBeat: start, endBeat: end)
                    },
                    onDelete: {
                        viewModel.removeHairpin(id: hairpin.id)
                    }
                )
            }
            Button {
                let end = viewModel.currentMeasure.map(\.usedBeats) ?? 1.0
                viewModel.addHairpin(Hairpin(type: .crescendo, startBeat: 0, endBeat: end))
                HapticManager.buttonTap()
            } label: {
                Label(String(localized: "Add hairpin"), systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Octave shifts (8va/8vb/15ma/15mb)

    private var octaveShiftsSection: some View {
        let shifts = viewModel.currentMeasure?.octaveShifts ?? []

        return Section(String(localized: "Octave shift (8va / 8vb / 15ma / 15mb)")) {
            ForEach(shifts) { shift in
                OctaveShiftRow(
                    shift: shift,
                    onUpdate: { kind, start, end in
                        viewModel.updateOctaveShift(id: shift.id, kind: kind, startBeat: start, endBeat: end)
                    },
                    onDelete: {
                        viewModel.removeOctaveShift(id: shift.id)
                    }
                )
            }
            Button {
                let end = viewModel.currentMeasure.map(\.usedBeats) ?? 1.0
                viewModel.addOctaveShift(OctaveShift(kind: .ottavaAlta, startBeat: 0, endBeat: end))
                HapticManager.buttonTap()
            } label: {
                Label(String(localized: "Add octave shift"), systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Tempo change (accel/rit/...)

    private var tempoChangeSection: some View {
        let change = viewModel.currentMeasure?.tempoChange

        return Section(String(localized: "Tempo change (accel / rit)")) {
            Toggle(String(localized: "Has tempo change"), isOn: Binding(
                get: { change != nil },
                set: { newValue in
                    if newValue {
                        let currentBPM = viewModel.score.tempo.bpm
                        let newEndBPM = currentBPM + 20
                        viewModel.setTempoChange(TempoChange(
                            kind: .accelerando,
                            startBeat: 0,
                            endBeat: 4,
                            startBPM: currentBPM,
                            endBPM: newEndBPM
                        ))
                    } else {
                        viewModel.setTempoChange(nil)
                    }
                }
            ))

            if let change = change {
                Picker(
                    String(localized: "Kind"),
                    selection: Binding(
                        get: { change.kind },
                        set: { newKind in
                            viewModel.setTempoChange(TempoChange(
                                kind: newKind,
                                startBeat: change.startBeat,
                                endBeat: change.endBeat,
                                startBPM: change.startBPM,
                                endBPM: change.endBPM
                            ))
                        }
                    )
                ) {
                    Text("accel.").tag(TempoChange.Kind.accelerando)
                    Text("rit.").tag(TempoChange.Kind.ritardando)
                    Text("rall.").tag(TempoChange.Kind.rallentando)
                    Text("string.").tag(TempoChange.Kind.stringendo)
                    Text("allarg.").tag(TempoChange.Kind.allargando)
                }

                HStack {
                    Text(String(localized: "Target BPM"))
                    Spacer()
                    TextField("", value: Binding(
                        get: { change.endBPM },
                        set: { newBPM in
                            viewModel.setTempoChange(TempoChange(
                                kind: change.kind,
                                startBeat: change.startBeat,
                                endBeat: change.endBeat,
                                startBPM: change.startBPM,
                                endBPM: max(20, min(400, newBPM))
                            ))
                        }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Expression texts (espressivo/dolce/...)

    private var expressionTextsSection: some View {
        let texts = viewModel.currentMeasure?.expressionTexts ?? []

        return Section(String(localized: "Expression texts (espressivo, dolce, ...)")) {
            ForEach(Array(texts.enumerated()), id: \.offset) { idx, text in
                ExpressionTextRow(
                    text: text,
                    onUpdate: { newText, italian, beat in
                        viewModel.updateExpressionText(at: idx, text: newText, italianTerm: italian, attachToBeat: beat)
                    },
                    onDelete: {
                        viewModel.removeExpressionText(at: idx)
                    }
                )
            }
            Menu {
                ForEach(ExpressionText.commonExpressions, id: \.self) { expr in
                    Button(expr) {
                        viewModel.addExpressionText(ExpressionText(text: expr, italianTerm: true, attachToBeat: 0))
                        HapticManager.buttonTap()
                    }
                }
                Divider()
                Button(String(localized: "Custom text...")) {
                    viewModel.addExpressionText(ExpressionText(text: "", italianTerm: true, attachToBeat: 0))
                    HapticManager.buttonTap()
                }
            } label: {
                Label(String(localized: "Add expression text"), systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Multi-measure rest

    private var multiMeasureRestSection: some View {
        let count = viewModel.currentMeasure?.multiMeasureRestCount ?? 0

        return Section(String(localized: "Multi-measure rest")) {
            Stepper(
                String(format: NSLocalizedString("Combine into %d-bar rest", comment: ""), count),
                value: Binding(
                    get: { count },
                    set: { viewModel.setMultiMeasureRestCount($0) }
                ),
                in: 0...32
            )
            Text(String(localized: "0 means no multi-bar rest. Higher values display a single rest block spanning N measures."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hairpin row

private struct HairpinRow: View {
    let hairpin: Hairpin
    let onUpdate: (HairpinType, Double, Double) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                String(localized: "Type"),
                selection: Binding(
                    get: { hairpin.type },
                    set: { onUpdate($0, hairpin.startBeat, hairpin.endBeat) }
                )
            ) {
                Text(String(localized: "Crescendo (<)")).tag(HairpinType.crescendo)
                Text(String(localized: "Diminuendo (>)")).tag(HairpinType.diminuendo)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(String(localized: "Start beat"))
                Spacer()
                TextField("", value: Binding(
                    get: { hairpin.startBeat },
                    set: { onUpdate(hairpin.type, $0, hairpin.endBeat) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            }

            HStack {
                Text(String(localized: "End beat"))
                Spacer()
                TextField("", value: Binding(
                    get: { hairpin.endBeat },
                    set: { onUpdate(hairpin.type, hairpin.startBeat, $0) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Octave shift row

private struct OctaveShiftRow: View {
    let shift: OctaveShift
    let onUpdate: (OctaveShiftKind, Double, Double) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                String(localized: "Direction"),
                selection: Binding(
                    get: { shift.kind },
                    set: { onUpdate($0, shift.startBeat, shift.endBeat) }
                )
            ) {
                Text("8va").tag(OctaveShiftKind.ottavaAlta)
                Text("8vb").tag(OctaveShiftKind.ottavaBassa)
                Text("15ma").tag(OctaveShiftKind.quindicesimaAlta)
                Text("15mb").tag(OctaveShiftKind.quindicesimaBassa)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(String(localized: "Start beat"))
                Spacer()
                TextField("", value: Binding(
                    get: { shift.startBeat },
                    set: { onUpdate(shift.kind, $0, shift.endBeat) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            }

            HStack {
                Text(String(localized: "End beat"))
                Spacer()
                TextField("", value: Binding(
                    get: { shift.endBeat },
                    set: { onUpdate(shift.kind, shift.startBeat, $0) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Expression text row

private struct ExpressionTextRow: View {
    let text: ExpressionText
    let onUpdate: (String, Bool, Double) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                String(localized: "espressivo, dolce, ..."),
                text: Binding(
                    get: { text.text },
                    set: { onUpdate($0, text.italianTerm, text.attachToBeat) }
                )
            )
            Toggle(String(localized: "Italian (italic)"), isOn: Binding(
                get: { text.italianTerm },
                set: { onUpdate(text.text, $0, text.attachToBeat) }
            ))

            HStack {
                Text(String(localized: "Attach to beat"))
                Spacer()
                TextField("", value: Binding(
                    get: { text.attachToBeat },
                    set: { onUpdate(text.text, text.italianTerm, $0) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
}
