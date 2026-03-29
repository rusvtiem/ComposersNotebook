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
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // Play first beat immediately
        tick()
    }

    private func tick() {
        let isAccent = currentBeat == 0
        if isAccent {
            accentPlayer?.currentTime = 0
            accentPlayer?.play()
        } else {
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
        }

        currentBeat = (currentBeat + 1) % timeSignature.beats
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
                    Circle()
                        .fill(beat == metronome.currentBeat && metronome.isRunning
                              ? (beat == 0 ? Color.red : Color.accentColor)
                              : Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
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
