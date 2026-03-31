import UIKit

// MARK: - Haptic Feedback Manager

enum HapticManager {

    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Note placed on staff
    static func notePlaced() {
        impactLight.impactOccurred()
    }

    /// Note deleted
    static func noteDeleted() {
        impactMedium.impactOccurred()
    }

    /// Note selected (tap on existing note)
    static func noteSelected() {
        selection.selectionChanged()
    }

    /// Instrument changed
    static func instrumentChanged() {
        impactLight.impactOccurred(intensity: 0.5)
    }

    /// Undo/Redo
    static func undoRedo() {
        impactLight.impactOccurred(intensity: 0.6)
    }

    /// Error (e.g., measure full)
    static func error() {
        notification.notificationOccurred(.error)
    }

    /// Success (e.g., file saved, exported)
    static func success() {
        notification.notificationOccurred(.success)
    }

    /// Zoom changed
    static func zoomTick() {
        selection.selectionChanged()
    }

    /// Toolbar button tap
    static func buttonTap() {
        impactLight.impactOccurred(intensity: 0.3)
    }
}
