import SwiftUI

enum InputKeyboardMode: String, CaseIterable {
    case piano = "Пианино"
    case letters = "Буквы"
}

struct ScoreEditorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ScoreViewModel
    @StateObject private var midiReceiver = ExternalMIDIReceiver.shared
    @StateObject private var soundFontManager = SoundFontManager.shared
    @State private var showSettings = false
    @State private var showPartPicker = false
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var keyboardMode: InputKeyboardMode = .piano
    @State private var showMeasureMenu = false
    @State private var showTimeSignaturePicker = false
    @State private var showKeySignaturePicker = false
    @State private var showSoundSettings = false
    @State private var showImportPicker = false
    @State private var showTempoPicker = false
    @State private var showExportSheet = false
    @State private var showShareSheet = false
    @State private var showThemeSettings = false
    @State private var shareURL: URL?
    @State private var alertMessage: String?
    @State private var showAlert = false

    init(score: Score) {
        _viewModel = StateObject(wrappedValue: ScoreViewModel(score: score))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar: score info
            scoreInfoBar

            Divider()

            // Staff area (scrollable, pinch-to-zoom via adaptive rendering)
            ScrollView([.horizontal, .vertical]) {
                StaffAreaView(viewModel: viewModel)
                    .padding()
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = baseZoomScale * value.magnification
                        viewModel.zoomScale = min(max(newScale, 0.5), 3.0)
                    }
                    .onEnded { _ in
                        baseZoomScale = viewModel.zoomScale
                    }
            )
            .onTapGesture(count: 2) {
                // Double-tap: toggle between 100% and 150%
                withAnimation(.easeInOut(duration: 0.25)) {
                    if viewModel.zoomScale > 1.1 {
                        viewModel.zoomScale = 1.0
                        baseZoomScale = 1.0
                    } else {
                        viewModel.zoomScale = 1.5
                        baseZoomScale = 1.5
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Metronome + Playback bar
            playbackBar

            Divider()

            // Note input toolbar
            NoteToolbarView(viewModel: viewModel)

            Divider()

            // Keyboard mode selector + input (hidden in navigate mode)
            if viewModel.inputMode != .navigate {
                inputArea
            }
        }
        .navigationTitle(viewModel.score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    appState.currentScore = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)

                Button { viewModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)

                Menu {
                    // Save
                    Button {
                        saveCNB()
                        HapticManager.success()
                    } label: {
                        Label(String(localized: "Save"), systemImage: "square.and.arrow.down")
                    }

                    Divider()

                    // Export submenu
                    Menu {
                        Button(String(localized: "Export as CNB")) { exportCNB() }
                        Button(String(localized: "Export as MusicXML")) { exportMusicXML() }
                        Button(String(localized: "Export as MIDI")) { exportMIDI() }
                        Button(String(localized: "Export as PDF")) { exportPDF() }
                    } label: {
                        Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                    }

                    // Import
                    Button { showImportPicker = true } label: {
                        Label(String(localized: "Import File"), systemImage: "square.and.arrow.down.on.square")
                    }

                    Divider()

                    // Sound settings
                    Button { showSoundSettings = true } label: {
                        Label(String(localized: "Sound Settings"), systemImage: "speaker.wave.2")
                    }

                    // Theme settings
                    Button { showThemeSettings = true } label: {
                        Label(String(localized: "Theme"), systemImage: "paintpalette")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            setupMIDIReceiver()
        }
        .sheet(isPresented: $showSoundSettings) {
            if let part = viewModel.currentPart {
                SoundSettingsView(
                    soundFontManager: soundFontManager,
                    instrument: part.instrument,
                    onPreview: {
                        MIDIEngine.shared.previewSound(midiProgram: part.instrument.midiProgram)
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPickerView(
                contentTypes: [.cnb, .musicXML, .midiFile, .xml, .midi],
                onPick: { url in importFile(at: url) }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("OK") {}
        }
        .sheet(isPresented: $showThemeSettings) {
            ThemeSettingsView()
                .presentationDetents([.large])
        }
    }

    // MARK: - MIDI Receiver Setup

    private func setupMIDIReceiver() {
        midiReceiver.onNoteOn = { midiNote, _ in
            let pitch = Pitch.fromMIDI(midiNote)
            viewModel.addNote(pitch: pitch)
        }
    }

    // MARK: - Playback Bar (with pause/resume)

    private var playbackBar: some View {
        HStack(spacing: 16) {
            MetronomeView(
                timeSignature: viewModel.effectiveTimeSignature,
                bpm: viewModel.score.tempo.bpm
            )

            Spacer()

            // MIDI indicator
            if midiReceiver.isConnected {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("MIDI")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Playback controls: |<< | Play/Pause | Stop | >>|
            HStack(spacing: 12) {
                Button {
                    viewModel.selectedMeasureIndex = 0
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                }

                Button {
                    if viewModel.midiEngine.isPlaying {
                        viewModel.midiEngine.pause()
                    } else {
                        viewModel.midiEngine.playScore(viewModel.score, fromMeasure: viewModel.selectedMeasureIndex)
                    }
                } label: {
                    Image(systemName: viewModel.midiEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                }

                Button {
                    viewModel.midiEngine.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                }
                .disabled(!viewModel.midiEngine.isPlaying)

                Button {
                    viewModel.selectedMeasureIndex = max(0, viewModel.score.measureCount - 1)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Input Area (Piano / Letters)

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Mode selector
            HStack(spacing: 8) {
                ForEach(InputKeyboardMode.allCases, id: \.self) { mode in
                    Button {
                        keyboardMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(keyboardMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(Capsule())
                            .foregroundColor(keyboardMode == mode ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Measure operations
                Menu {
                    Button { viewModel.insertMeasureBefore() } label: {
                        Label("Вставить такт до", systemImage: "arrow.left.to.line")
                    }
                    Button { viewModel.insertMeasureAfter() } label: {
                        Label("Вставить такт после", systemImage: "arrow.right.to.line")
                    }
                    Divider()
                    Button(role: .destructive) { viewModel.deleteMeasure() } label: {
                        Label("Удалить такт", systemImage: "trash")
                    }
                    .disabled(viewModel.score.measureCount <= 1)
                    Divider()
                    Button { showTimeSignaturePicker = true } label: {
                        Label("Сменить размер", systemImage: "number")
                    }
                    Button { showKeySignaturePicker = true } label: {
                        Label("Сменить тональность", systemImage: "music.note")
                    }
                    Button { showTempoPicker = true } label: {
                        Label("Сменить темп", systemImage: "metronome")
                    }
                } label: {
                    Image(systemName: "ruler")
                        .font(.system(size: 14))
                        .padding(6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Keyboard
            switch keyboardMode {
            case .piano:
                PianoKeyboardView(viewModel: viewModel)
                    .frame(height: 100)
            case .letters:
                LetterInputView(viewModel: viewModel)
                    .frame(height: 100)
            }
        }
        .sheet(isPresented: $showTimeSignaturePicker) {
            TimeSignaturePickerSheet(viewModel: viewModel)
                .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showKeySignaturePicker) {
            KeySignaturePickerSheet(viewModel: viewModel)
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showTempoPicker) {
            TempoPickerSheet(viewModel: viewModel)
                .presentationDetents([.height(300)])
        }
    }

    // MARK: - Score Info Bar

    private var scoreInfoBar: some View {
        HStack(spacing: 16) {
            // Part selector
            Menu {
                ForEach(Array(viewModel.score.parts.enumerated()), id: \.offset) { index, part in
                    Button {
                        viewModel.selectPart(at: index)
                    } label: {
                        HStack {
                            Text(part.instrument.name)
                            if index == viewModel.selectedPartIndex {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "music.mic")
                    Text(viewModel.currentPart?.instrument.shortName ?? "—")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }

            // Key signature
            Text(viewModel.effectiveKeySignature.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Time signature
            Text(viewModel.effectiveTimeSignature.displayString)
                .font(.caption)
                .fontWeight(.bold)

            // Tempo
            Text(viewModel.score.tempo.displayString)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Button {
                    viewModel.zoomScale = max(0.5, viewModel.zoomScale - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12))
                }
                Text("\(Int(viewModel.zoomScale * 100))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                Button {
                    viewModel.zoomScale = min(3.0, viewModel.zoomScale + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12))
                }
            }

            // Measure info
            Text("Такт \(viewModel.selectedMeasureIndex + 1)/\(viewModel.score.measureCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Save CNB

    private func saveCNB() {
        let fileManager = CNBFileManager.shared
        let url = fileManager.fileURL(for: viewModel.score)
        do {
            try fileManager.save(score: viewModel.score, to: url)
        } catch {
            showError("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Export

    private func exportCNB() {
        let fileManager = CNBFileManager.shared
        let url = fileManager.fileURL(for: viewModel.score)
        do {
            try fileManager.save(score: viewModel.score, to: url)
            shareFile(url)
        } catch {
            showError("Export failed: \(error.localizedDescription)")
        }
    }

    private func exportMusicXML() {
        let exporter = MusicXMLExporter()
        let xml = exporter.export(score: viewModel.score)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = viewModel.score.title.replacingOccurrences(of: " ", with: "_") + ".musicxml"
        let url = docs.appendingPathComponent(filename)

        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            shareFile(url)
        } catch {
            showError("MusicXML export failed: \(error.localizedDescription)")
        }
    }

    private func exportMIDI() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = viewModel.score.title.replacingOccurrences(of: " ", with: "_") + ".mid"
        let url = docs.appendingPathComponent(filename)

        do {
            try MIDIExporter.exportToFile(score: viewModel.score, url: url)
            shareFile(url)
        } catch {
            showError("MIDI export failed: \(error.localizedDescription)")
        }
    }

    private func exportPDF() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = viewModel.score.title.replacingOccurrences(of: " ", with: "_") + ".pdf"
        let url = docs.appendingPathComponent(filename)

        do {
            try PDFExporter.exportToFile(score: viewModel.score, url: url)
            shareFile(url)
        } catch {
            showError("PDF export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    private func importFile(at url: URL) {
        do {
            let ext = url.pathExtension.lowercased()
            let score: Score

            switch ext {
            case "cnb":
                let container = try CNBFileManager.shared.load(from: url)
                score = container.score
            case "musicxml", "mxl", "xml":
                score = try MusicXMLImporter.importFile(at: url)
            case "mid", "midi":
                score = try MIDIImporter.importFile(at: url)
            default:
                showError("Unsupported file format: .\(ext)")
                return
            }

            appState.currentScore = score
            HapticManager.success()
        } catch {
            showError("Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func shareFile(_ url: URL) {
        shareURL = url
        showShareSheet = true
        HapticManager.success()
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
        HapticManager.error()
    }
}

// MARK: - Time Signature Picker Sheet

struct TSPreset: Identifiable {
    let id: String
    let label: String
    let ts: TimeSignature
    init(_ label: String, _ ts: TimeSignature) { self.id = label; self.label = label; self.ts = ts }
}

struct TimeSignaturePickerSheet: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) var dismiss

    private let presets: [TSPreset] = [
        TSPreset("4/4", .fourFour),
        TSPreset("3/4", .threeFour),
        TSPreset("2/4", .twoFour),
        TSPreset("6/8", .sixEight),
        TSPreset("5/8", .fiveEight),
        TSPreset("3/8", .threeeEight),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Сменить размер с такта \(viewModel.selectedMeasureIndex + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            viewModel.setTimeSignatureAtCurrentMeasure(preset.ts)
                            dismiss()
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 70, height: 50)
                                .background(viewModel.effectiveTimeSignature == preset.ts ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Размер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Key Signature Picker Sheet

struct KSPreset: Identifiable {
    let id: String
    let label: String
    let ks: KeySignature
    init(_ label: String, _ ks: KeySignature) { self.id = label; self.label = label; self.ks = ks }
}

struct KeySignaturePickerSheet: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) var dismiss

    private let keys: [KSPreset] = [
        KSPreset("До мажор", KeySignature(fifths: 0, mode: .major)),
        KSPreset("Соль мажор", KeySignature(fifths: 1, mode: .major)),
        KSPreset("Ре мажор", KeySignature(fifths: 2, mode: .major)),
        KSPreset("Ля мажор", KeySignature(fifths: 3, mode: .major)),
        KSPreset("Ми мажор", KeySignature(fifths: 4, mode: .major)),
        KSPreset("Си мажор", KeySignature(fifths: 5, mode: .major)),
        KSPreset("Фа мажор", KeySignature(fifths: -1, mode: .major)),
        KSPreset("Си-бемоль мажор", KeySignature(fifths: -2, mode: .major)),
        KSPreset("Ми-бемоль мажор", KeySignature(fifths: -3, mode: .major)),
        KSPreset("Ля-бемоль мажор", KeySignature(fifths: -4, mode: .major)),
        KSPreset("ля минор", KeySignature(fifths: 0, mode: .minor)),
        KSPreset("ми минор", KeySignature(fifths: 1, mode: .minor)),
        KSPreset("си минор", KeySignature(fifths: 2, mode: .minor)),
        KSPreset("ре минор", KeySignature(fifths: -1, mode: .minor)),
        KSPreset("соль минор", KeySignature(fifths: -2, mode: .minor)),
        KSPreset("до минор", KeySignature(fifths: -3, mode: .minor)),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("Сменить тональность с такта \(viewModel.selectedMeasureIndex + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                List(keys) { preset in
                    Button {
                        viewModel.setKeySignatureAtCurrentMeasure(preset.ks)
                        dismiss()
                    } label: {
                        HStack {
                            Text(preset.label)
                            Spacer()
                            if viewModel.effectiveKeySignature == preset.ks {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Тональность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tempo Picker Sheet

struct TempoPickerSheet: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) var dismiss
    @State private var customBPM: Double = 120

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Сменить темп с такта \(viewModel.selectedMeasureIndex + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Custom BPM slider
                VStack(spacing: 4) {
                    HStack {
                        Text("♩= \(Int(customBPM))")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        Button("Применить") {
                            viewModel.setTempo(TempoMarking(bpm: customBPM))
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Slider(value: $customBPM, in: 20...300, step: 1)
                }
                .padding(.horizontal)

                Divider()

                // Preset tempos
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                    ForEach(TempoMarking.commonTempos, id: \.0) { name, bpm in
                        Button {
                            viewModel.setTempo(TempoMarking(bpm: bpm, name: name))
                            dismiss()
                        } label: {
                            HStack {
                                Text(name)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("♩=\(Int(bpm))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Темп")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear {
                customBPM = viewModel.score.tempo.bpm
            }
        }
    }
}
