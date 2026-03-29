import SwiftUI

struct ScoreEditorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ScoreViewModel
    @State private var showSettings = false
    @State private var showPartPicker = false

    init(score: Score) {
        _viewModel = StateObject(wrappedValue: ScoreViewModel(score: score))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar: score info
            scoreInfoBar

            Divider()

            // Staff area (scrollable)
            ScrollView([.horizontal, .vertical]) {
                StaffAreaView(viewModel: viewModel)
                    .padding()
            }
            .frame(maxHeight: .infinity)

            // Metronome + Playback bar
            HStack(spacing: 16) {
                MetronomeView(
                    timeSignature: viewModel.effectiveTimeSignature,
                    bpm: viewModel.score.tempo.bpm
                )

                Spacer()

                // Play/Stop
                Button {
                    if viewModel.midiEngine.isPlaying {
                        viewModel.midiEngine.stop()
                    } else {
                        viewModel.midiEngine.playScore(viewModel.score, fromMeasure: viewModel.selectedMeasureIndex)
                    }
                } label: {
                    Image(systemName: viewModel.midiEngine.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Note input toolbar
            NoteToolbarView(viewModel: viewModel)

            Divider()

            // Piano keyboard
            PianoKeyboardView(viewModel: viewModel)
                .frame(height: 120)
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
                    Button("Экспорт MusicXML") { exportMusicXML() }
                    Button { appState.isDarkMode.toggle() } label: {
                        Label(
                            appState.isDarkMode ? "Светлая тема" : "Тёмная тема",
                            systemImage: appState.isDarkMode ? "sun.max.fill" : "moon.fill"
                        )
                    }
                    Button("Сохранить") { viewModel.save() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
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
                .background(.fill.tertiary)
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

            // Measure info
            Text("Такт \(viewModel.selectedMeasureIndex + 1)/\(viewModel.score.measureCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Export

    private func exportMusicXML() {
        let exporter = MusicXMLExporter()
        let xml = exporter.export(score: viewModel.score)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = viewModel.score.title.replacingOccurrences(of: " ", with: "_") + ".musicxml"
        let url = docs.appendingPathComponent(filename)

        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            // Share sheet
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Ошибка экспорта: \(error)")
        }
    }
}
