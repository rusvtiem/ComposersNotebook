import AVFoundation
import SwiftUI

// MARK: - Metronome

@MainActor
class MetronomeEngine: ObservableObject {
    @Published var isRunning = false
    @Published var bpm: Double = 120 {
        didSet { if isRunning { restart() } }
    }
    @Published var timeSignature: TimeSignature = .fourFour {
        didSet { if isRunning { restart() } }
    }
    @Published var currentBeat: Int = 0

    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var accentPlayer: AVAudioPlayer?

    init() {
        setupSounds()
    }

    // MARK: - Sound Setup

    private func setupSounds() {
        // Generate click sounds programmatically
        audioPlayer = generateClickSound(frequency: 800, duration: 0.02)
        accentPlayer = generateClickSound(frequency: 1200, duration: 0.03)
    }

    private func generateClickSound(frequency: Double, duration: Double) -> AVAudioPlayer? {
        let sampleRate = 44100.0
        let samples = Int(sampleRate * duration)
        var audioData = Data()

        // WAV header
        let dataSize = samples * 2  // 16-bit mono
        let fileSize = 36 + dataSize
        audioData.append(contentsOf: "RIFF".utf8)
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        audioData.append(contentsOf: "WAVE".utf8)
        audioData.append(contentsOf: "fmt ".utf8)
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(44100).littleEndian) { Array($0) })
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(88200).littleEndian) { Array($0) })
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        audioData.append(contentsOf: "data".utf8)
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Generate sine wave samples
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let envelope = 1.0 - (t / duration)  // linear decay
            let sample = sin(2.0 * Double.pi * frequency * t) * envelope * 0.8
            let intSample = Int16(clamping: Int(sample * 32767))
            audioData.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        return try? AVAudioPlayer(data: audioData)
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        isRunning = true
        currentBeat = 0
        scheduleTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        currentBeat = 0
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    private func restart() {
        stop()
        start()
    }

    private func scheduleTimer() {
        let interval = 60.0 / bpm
        // Play first beat immediately
        playBeat()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAndPlay()
            }
        }
    }

    private func advanceAndPlay() {
        currentBeat = (currentBeat + 1) % timeSignature.beats
        playBeat()
    }

    private func playBeat() {
        let beatStrength = beatHierarchy(beat: currentBeat, beats: timeSignature.beats)
        switch beatStrength {
        case .strong:
            accentPlayer?.volume = 1.0
            accentPlayer?.currentTime = 0
            accentPlayer?.play()
        case .medium:
            // Relatively strong beat — use accent sound at medium volume
            accentPlayer?.volume = 0.7
            accentPlayer?.currentTime = 0
            accentPlayer?.play()
        case .weak:
            audioPlayer?.volume = 0.5
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
        }
    }

    // MARK: - Beat Hierarchy (music theory)

    enum BeatStrength {
        case strong, medium, weak
    }

    func beatHierarchy(beat: Int, beats: Int) -> BeatStrength {
        if beat == 0 { return .strong }

        switch beats {
        case 2: // 2/4: strong-weak
            return .weak
        case 3: // 3/4: strong-weak-weak
            return .weak
        case 4: // 4/4: strong-weak-medium-weak
            return beat == 2 ? .medium : .weak
        case 6: // 6/8: strong-weak-weak-medium-weak-weak
            return beat == 3 ? .medium : .weak
        case 9: // 9/8: strong-weak-weak-medium-weak-weak-medium-weak-weak
            return (beat % 3 == 0) ? .medium : .weak
        case 12: // 12/8: strong-weak-weak-medium-weak-weak-medium-weak-weak-medium-weak-weak
            return (beat % 3 == 0) ? .medium : .weak
        default:
            return .weak
        }
    }
}

// MARK: - Metronome View

struct MetronomeView: View {
    @StateObject private var metronome = MetronomeEngine()
    let timeSignature: TimeSignature
    let bpm: Double

    var body: some View {
        HStack(spacing: 12) {
            // Beat indicator
            HStack(spacing: 4) {
                ForEach(0..<timeSignature.beats, id: \.self) { beat in
                    let strength = metronome.beatHierarchy(beat: beat, beats: timeSignature.beats)
                    let isActive = beat == metronome.currentBeat && metronome.isRunning
                    let activeColor: Color = strength == .strong ? .red : (strength == .medium ? .orange : .accentColor)
                    let size: CGFloat = strength == .strong ? 12 : (strength == .medium ? 11 : 10)
                    Circle()
                        .fill(isActive ? activeColor : Color.secondary.opacity(0.3))
                        .frame(width: size, height: size)
                }
            }

            // BPM display
            Text("♩= \(Int(metronome.bpm))")
                .font(.caption)
                .monospacedDigit()

            // Play/Stop
            Button {
                metronome.toggle()
            } label: {
                Image(systemName: metronome.isRunning ? "stop.fill" : "metronome.fill")
                    .font(.system(size: 16))
            }
        }
        .onAppear {
            metronome.bpm = bpm
            metronome.timeSignature = timeSignature
        }
        .onChange(of: bpm) { _, newValue in
            metronome.bpm = newValue
        }
        .onChange(of: timeSignature) { _, newValue in
            metronome.timeSignature = newValue
        }
    }
}
