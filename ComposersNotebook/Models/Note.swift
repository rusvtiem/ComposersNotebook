import Foundation

// MARK: - Note Event (note or rest)

enum NoteEventType: Codable, Equatable {
    case note(pitch: Pitch)
    case chord(pitches: [Pitch])
    case rest
}

struct NoteEvent: Codable, Equatable, Identifiable {
    let id: UUID
    var type: NoteEventType
    var duration: Duration
    var articulations: [Articulation]
    var dynamic: DynamicMarking?
    var tiedToNext: Bool     // залиговка (продление звучания)
    var slurStart: Bool      // начало фразировочной лиги
    var slurEnd: Bool        // конец фразировочной лиги

    init(
        type: NoteEventType,
        duration: Duration,
        articulations: [Articulation] = [],
        dynamic: DynamicMarking? = nil,
        tiedToNext: Bool = false,
        slurStart: Bool = false,
        slurEnd: Bool = false
    ) {
        self.id = UUID()
        self.type = type
        self.duration = duration
        self.articulations = articulations
        self.dynamic = dynamic
        self.tiedToNext = tiedToNext
        self.slurStart = slurStart
        self.slurEnd = slurEnd
    }

    var isRest: Bool {
        if case .rest = type { return true }
        return false
    }

    var pitches: [Pitch] {
        switch type {
        case .note(let pitch): return [pitch]
        case .chord(let pitches): return pitches
        case .rest: return []
        }
    }

    /// MIDI velocity based on dynamic marking
    var velocity: Int {
        dynamic?.velocity ?? DynamicMarking.mf.velocity
    }

    // Convenience constructors

    static func note(_ pitch: Pitch, duration: Duration) -> NoteEvent {
        NoteEvent(type: .note(pitch: pitch), duration: duration)
    }

    static func rest(duration: Duration) -> NoteEvent {
        NoteEvent(type: .rest, duration: duration)
    }

    static func chord(_ pitches: [Pitch], duration: Duration) -> NoteEvent {
        NoteEvent(type: .chord(pitches: pitches), duration: duration)
    }
}
