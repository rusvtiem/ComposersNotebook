import Foundation

// MARK: - Plugin Protocol

protocol ComposerPlugin: Identifiable {
    var id: String { get }
    var name: String { get }
    var version: String { get }
    var description: String { get }

    func onNoteAdded(_ event: NoteEvent, in score: Score) -> NoteEvent?
    func onScoreExport(_ score: Score) -> Score?
    func onPlayback(_ event: NoteEvent) -> NoteEvent?
}

// Default implementations
extension ComposerPlugin {
    func onNoteAdded(_ event: NoteEvent, in score: Score) -> NoteEvent? { nil }
    func onScoreExport(_ score: Score) -> Score? { nil }
    func onPlayback(_ event: NoteEvent) -> NoteEvent? { nil }
}

// MARK: - Plugin Manager

class PluginManager: ObservableObject {
    static let shared = PluginManager()

    @Published private(set) var plugins: [any ComposerPlugin] = []

    func register(_ plugin: any ComposerPlugin) {
        plugins.append(plugin)
    }

    func unregister(id: String) {
        plugins.removeAll { $0.id == id }
    }

    // Hook: note added
    func processNoteAdded(_ event: NoteEvent, in score: Score) -> NoteEvent {
        var result = event
        for plugin in plugins {
            if let modified = plugin.onNoteAdded(result, in: score) {
                result = modified
            }
        }
        return result
    }

    // Hook: before export
    func processExport(_ score: Score) -> Score {
        var result = score
        for plugin in plugins {
            if let modified = plugin.onScoreExport(result) {
                result = modified
            }
        }
        return result
    }

    // Hook: playback
    func processPlayback(_ event: NoteEvent) -> NoteEvent {
        var result = event
        for plugin in plugins {
            if let modified = plugin.onPlayback(result) {
                result = modified
            }
        }
        return result
    }
}

// MARK: - Example: Range Check Plugin

struct RangeCheckPlugin: ComposerPlugin {
    let id = "range-check"
    let name = "Проверка диапазона"
    let version = "1.0"
    let description = "Предупреждает если нота выходит за диапазон инструмента"

    func onNoteAdded(_ event: NoteEvent, in score: Score) -> NoteEvent? {
        // Future: check instrument range and warn
        nil
    }
}
