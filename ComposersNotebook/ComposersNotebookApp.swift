import SwiftUI

@main
struct ComposersNotebookApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.isDarkMode ? .dark : .light)
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
