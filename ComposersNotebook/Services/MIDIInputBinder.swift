import Foundation

// MARK: - MIDI Input Binder
//
// Связывает ExternalMIDIReceiver (CoreMIDI) с ScoreViewModel.
// При нажатии клавиши на физической MIDI-клавиатуре или AUv3 контроллере
// вставляет ноту с текущей выбранной длительностью и акциденталом.
//
// Никакого ML — просто маршрутизация MIDI-байтов в model.

@MainActor
final class MIDIInputBinder {

    private weak var viewModel: ScoreViewModel?
    private let receiver: ExternalMIDIReceiver

    init(viewModel: ScoreViewModel, receiver: ExternalMIDIReceiver = .shared) {
        self.viewModel = viewModel
        self.receiver = receiver
        attach()
    }

    private func attach() {
        receiver.onNoteOn = { [weak self] midiNote, velocity in
            self?.handleNoteOn(midiNote: midiNote, velocity: velocity)
        }
    }

    func detach() {
        receiver.onNoteOn = nil
    }

    /// Конвертирует MIDI ноту в нашу Pitch и вставляет через ScoreViewModel.
    private func handleNoteOn(midiNote: Int, velocity: Int) {
        guard let vm = viewModel else { return }
        guard velocity > 0 else { return }   // note-off приходит как note-on с vel=0

        let pitch = Pitch.fromMIDI(midiNote)

        // Если выбран input mode = .navigate, не вставляем — а просто играем preview звук.
        switch vm.inputMode {
        case .note:
            vm.addNote(pitch: pitch)
        case .navigate, .rest:
            MIDIEngine.shared.playNote(pitch: pitch, velocity: velocity, duration: 0.3)
        }
    }
}
