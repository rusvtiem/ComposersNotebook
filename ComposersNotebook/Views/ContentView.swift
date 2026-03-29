import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            if let score = appState.currentScore {
                ScoreEditorView(score: score)
            } else {
                HomeView()
            }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewScoreSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)

            Text("Composer's Notebook")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Блокнот композитора")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 16) {
                // Быстрая заметка
                Button {
                    startQuickNote()
                } label: {
                    Label("Быстрая заметка", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Новая партитура
                Button {
                    showNewScoreSheet = true
                } label: {
                    Label("Новая партитура", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.isDarkMode.toggle()
                } label: {
                    Image(systemName: appState.isDarkMode ? "sun.max.fill" : "moon.fill")
                }
            }
        }
        .sheet(isPresented: $showNewScoreSheet) {
            NewScoreSheet { score in
                appState.currentScore = score
            }
        }
    }

    private func startQuickNote() {
        appState.isQuickNoteMode = true
        appState.currentScore = Score.pianoSolo(title: "Быстрая заметка")
    }
}

// MARK: - New Score Sheet

struct NewScoreSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var composer = ""
    @State private var selectedInstruments: [Instrument] = []
    @State private var selectedTimeSignature = TimeSignature.fourFour
    @State private var selectedKeyFifths = 0
    @State private var selectedKeyMode = KeySignatureType.major
    @State private var selectedTempoBPM: Double = 120

    let onCreate: (Score) -> Void

    private let timeSignatures: [TimeSignature] = [
        .fourFour, .threeFour, .twoFour, .sixEight, .fiveEight, .threeeEight
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название", text: $title)
                    TextField("Композитор", text: $composer)
                }

                Section("Размер") {
                    Picker("Размер такта", selection: $selectedTimeSignature) {
                        ForEach(timeSignatures, id: \.displayString) { ts in
                            Text(ts.displayString).tag(ts)
                        }
                    }
                }

                Section("Тональность") {
                    Picker("Знаки", selection: $selectedKeyFifths) {
                        ForEach(-7...7, id: \.self) { fifths in
                            let ks = KeySignature(fifths: fifths, mode: selectedKeyMode)
                            Text(ks.displayName).tag(fifths)
                        }
                    }
                    Picker("Лад", selection: $selectedKeyMode) {
                        Text("Мажор").tag(KeySignatureType.major)
                        Text("Минор").tag(KeySignatureType.minor)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Темп") {
                    HStack {
                        Text("♩= \(Int(selectedTempoBPM))")
                            .monospacedDigit()
                        Slider(value: $selectedTempoBPM, in: 20...240, step: 1)
                    }
                    tempoPresets
                }

                Section("Инструменты") {
                    if selectedInstruments.isEmpty {
                        Button("Добавить инструмент") {
                            selectedInstruments.append(.piano)
                        }
                    } else {
                        ForEach(Array(selectedInstruments.enumerated()), id: \.offset) { index, instrument in
                            HStack {
                                Text(instrument.name)
                                Spacer()
                                Text(instrument.group.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { indices in
                            selectedInstruments.remove(atOffsets: indices)
                        }

                        instrumentPicker
                    }
                }
            }
            .navigationTitle("Новая партитура")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        createScore()
                    }
                    .disabled(selectedInstruments.isEmpty)
                }
            }
        }
    }

    private var tempoPresets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TempoMarking.commonTempos, id: \.0) { name, bpm in
                    Button {
                        selectedTempoBPM = bpm
                    } label: {
                        Text(name)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                abs(selectedTempoBPM - bpm) < 5
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.2)
                            )
                            .foregroundStyle(
                                abs(selectedTempoBPM - bpm) < 5 ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var instrumentPicker: some View {
        Menu("Добавить инструмент") {
            ForEach(InstrumentGroup.allCases, id: \.self) { group in
                Menu(group.displayName) {
                    ForEach(Instrument.instruments(for: group), id: \.name) { instrument in
                        Button(instrument.name) {
                            selectedInstruments.append(instrument)
                        }
                    }
                }
            }
        }
    }

    private func createScore() {
        let tempo = TempoMarking(bpm: selectedTempoBPM,
            name: TempoMarking.commonTempos.first { abs($0.1 - selectedTempoBPM) < 5 }?.0)
        let keySignature = KeySignature(fifths: selectedKeyFifths, mode: selectedKeyMode)

        var score = Score(
            title: title.isEmpty ? "Без названия" : title,
            composer: composer,
            tempo: tempo,
            timeSignature: selectedTimeSignature,
            keySignature: keySignature
        )
        for instrument in selectedInstruments {
            score.addPart(instrument: instrument)
        }
        score.sortPartsByOrchestralOrder()

        onCreate(score)
        dismiss()
    }
}
