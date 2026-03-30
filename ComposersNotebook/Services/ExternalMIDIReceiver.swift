import CoreMIDI
import Combine

// MARK: - External MIDI Keyboard Receiver

@MainActor
class ExternalMIDIReceiver: ObservableObject {
    static let shared = ExternalMIDIReceiver()

    @Published var isConnected = false
    @Published var connectedDeviceName: String?

    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    var onNoteOn: ((Int, Int) -> Void)?  // (midiNote, velocity)

    init() {
        setupMIDI()
    }

    private func setupMIDI() {
        let status = MIDIClientCreateWithBlock("ComposersNotebook" as CFString, &midiClient) { [weak self] notification in
            Task { @MainActor in
                self?.handleMIDINotification(notification)
            }
        }
        guard status == noErr else {
            print("MIDI Client ошибка: \(status)")
            return
        }

        MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEvents(eventList)
        }

        connectAllSources()
    }

    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, source, nil)
        }

        Task { @MainActor in
            isConnected = sourceCount > 0
            if sourceCount > 0 {
                let source = MIDIGetSource(0)
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
                connectedDeviceName = name?.takeRetainedValue() as String?
            }
        }
    }

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        if notification.pointee.messageID == .msgSetupChanged {
            connectAllSources()
        }
    }

    private nonisolated func handleMIDIEvents(_ eventList: UnsafePointer<MIDIEventList>) {
        let list = eventList.pointee
        withUnsafePointer(to: list.packet) { ptr in
            var packet = ptr.pointee
            for _ in 0..<list.numPackets {
                let words = packet.words
                let word = words.0
                let status = (word >> 16) & 0xF0
                let note = Int((word >> 8) & 0x7F)
                let velocity = Int(word & 0x7F)

                if status == 0x90 && velocity > 0 {
                    // Note On
                    Task { @MainActor [weak self] in
                        self?.onNoteOn?(note, velocity)
                    }
                }

                withUnsafePointer(to: &packet) { ptr in
                    let next = MIDIEventPacketNext(ptr)
                    packet = next.pointee
                }
            }
        }
    }
}
