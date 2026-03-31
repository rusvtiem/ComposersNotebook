import SwiftUI
import UniformTypeIdentifiers

@main
struct ComposersNotebookApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.isDarkMode ? .dark : .light)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
    }

    private func handleOpenURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()

        do {
            switch ext {
            case "cnb":
                let container = try CNBFileManager.shared.load(from: url)
                appState.currentScore = container.score
            case "musicxml", "mxl", "xml":
                appState.currentScore = try MusicXMLImporter.importFile(at: url)
            case "mid", "midi":
                appState.currentScore = try MIDIImporter.importFile(at: url)
            case "sf2":
                _ = try SoundFontManager.shared.importSoundFont(from: url)
            default:
                print("Unsupported file type: \(ext)")
            }
        } catch {
            print("Error opening file: \(error)")
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var isDarkMode: Bool {
        didSet { UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode") }
    }
    @Published var currentScore: Score?
    @Published var isQuickNoteMode: Bool = false

    init() {
        self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
    }
}
