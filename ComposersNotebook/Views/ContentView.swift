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
    @State private var showImportPicker = false
    @State private var recentFiles: [URL] = []

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)

            Text("Composer's Notebook")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "Composer's Sketchbook"))
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    startQuickNote()
                    HapticManager.buttonTap()
                } label: {
                    Label(String(localized: "Quick Note"), systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showNewScoreSheet = true
                    HapticManager.buttonTap()
                } label: {
                    Label(String(localized: "New Score"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showImportPicker = true
                    HapticManager.buttonTap()
                } label: {
                    Label(String(localized: "Open File"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 32)

            // Recent files
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Recent"))
                        .font(.headline)
                        .padding(.horizontal, 32)

                    ForEach(recentFiles.prefix(5), id: \.absoluteString) { url in
                        Button {
                            openCNBFile(url)
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.body)
                                    Text(fileDate(url))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

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
        .onAppear {
            recentFiles = CNBFileManager.shared.listFiles()
        }
        .sheet(isPresented: $showNewScoreSheet) {
            NewScoreSheet { score in
                appState.currentScore = score
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPickerView(
                contentTypes: [.cnb, .musicXML, .midiFile, .xml, .midi],
                onPick: { url in importFile(url) }
            )
        }
    }

    private func startQuickNote() {
        appState.isQuickNoteMode = true
        appState.currentScore = Score.pianoSolo(title: String(localized: "Quick Note"))
    }

    private func openCNBFile(_ url: URL) {
        do {
            let container = try CNBFileManager.shared.load(from: url)
            appState.currentScore = container.score
            HapticManager.success()
        } catch {
            print("Error opening file: \(error)")
        }
    }

    private func importFile(_ url: URL) {
        do {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "cnb":
                let container = try CNBFileManager.shared.load(from: url)
                appState.currentScore = container.score
            case "musicxml", "mxl", "xml":
                appState.currentScore = try MusicXMLImporter.importFile(at: url)
            case "mid", "midi":
                appState.currentScore = try MIDIImporter.importFile(at: url)
            default:
                print("Unsupported format: \(ext)")
            }
            HapticManager.success()
        } catch {
            print("Import error: \(error)")
        }
    }

    private func fileDate(_ url: URL) -> String {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return ""
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
