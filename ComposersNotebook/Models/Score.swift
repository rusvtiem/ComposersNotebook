import Foundation

// MARK: - Score (Партитура)

struct Score: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var composer: String
    var parts: [Part]
    var tempo: TempoMarking
    var timeSignature: TimeSignature
    var keySignature: KeySignature
    var createdAt: Date
    var modifiedAt: Date

    init(
        title: String = "",
        composer: String = "",
        parts: [Part] = [],
        tempo: TempoMarking = TempoMarking(bpm: 120, name: "Allegro"),
        timeSignature: TimeSignature = .fourFour,
        keySignature: KeySignature = .cMajor
    ) {
        self.id = UUID()
        self.title = title
        self.composer = composer
        self.parts = parts
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Add a new instrument part
    mutating func addPart(instrument: Instrument) {
        var part = Part(instrument: instrument)
        // Ensure the new part has the same number of measures as existing parts
        let targetCount = parts.first?.measureCount ?? 1
        while part.measures.count < targetCount {
            part.appendEmptyMeasure()
        }
        parts.append(part)
        touch()
    }

    /// Remove a part by index
    mutating func removePart(at index: Int) {
        guard index < parts.count else { return }
        parts.remove(at: index)
        touch()
    }

    /// Add an empty measure to all parts
    mutating func appendMeasure() {
        for i in parts.indices {
            parts[i].appendEmptyMeasure()
        }
        touch()
    }

    /// Insert a measure at a specific index in all parts
    mutating func insertMeasure(at index: Int) {
        for i in parts.indices {
            parts[i].insertMeasure(.wholeRest(), at: index)
        }
        touch()
    }

    /// Remove a measure at index from all parts
    mutating func removeMeasure(at index: Int) {
        for i in parts.indices {
            parts[i].removeMeasure(at: index)
        }
        touch()
    }

    /// Total number of measures (based on first part, all parts should be equal)
    var measureCount: Int {
        parts.first?.measureCount ?? 0
    }

    /// Update modification timestamp
    mutating func touch() {
        modifiedAt = Date()
    }

    /// Sort parts by orchestral order
    mutating func sortPartsByOrchestralOrder() {
        parts.sort { a, b in
            if a.instrument.group.scoreOrder != b.instrument.group.scoreOrder {
                return a.instrument.group.scoreOrder < b.instrument.group.scoreOrder
            }
            return a.instrument.midiProgram < b.instrument.midiProgram
        }
    }

    // MARK: - Quick constructors

    /// Piano solo score
    static func pianoSolo(title: String = "") -> Score {
        Score(
            title: title,
            parts: [Part(instrument: .piano)]
        )
    }

    /// Empty score with given instruments
    static func withInstruments(_ instruments: [Instrument], title: String = "") -> Score {
        var score = Score(title: title)
        for instrument in instruments {
            score.addPart(instrument: instrument)
        }
        score.sortPartsByOrchestralOrder()
        return score
    }
}

// MARK: - Score Templates

struct ScoreTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let instruments: [Instrument]

    func createScore(title: String = "", composer: String = "") -> Score {
        var score = Score(
            title: title.isEmpty ? name : title,
            composer: composer
        )
        for instrument in instruments {
            score.addPart(instrument: instrument)
        }
        score.sortPartsByOrchestralOrder()
        return score
    }
}

extension ScoreTemplate {

    // MARK: Solo

    static let pianoSolo = ScoreTemplate(
        name: "Фортепиано соло",
        icon: "pianokeys",
        description: "Одна партия фортепиано",
        instruments: [.piano]
    )

    static let guitarSolo = ScoreTemplate(
        name: "Гитара соло",
        icon: "guitars",
        description: "Классическая гитара",
        instruments: [.classicalGuitar]
    )

    static let violinSolo = ScoreTemplate(
        name: "Скрипка соло",
        icon: "music.note",
        description: "Одна партия скрипки",
        instruments: [.violin]
    )

    static let celloSolo = ScoreTemplate(
        name: "Виолончель соло",
        icon: "music.note",
        description: "Одна партия виолончели",
        instruments: [.cello]
    )

    static let fluteSolo = ScoreTemplate(
        name: "Флейта соло",
        icon: "music.note",
        description: "Одна партия флейты",
        instruments: [.flute]
    )

    // MARK: Chamber

    static let stringQuartet = ScoreTemplate(
        name: "Струнный квартет",
        icon: "music.note.list",
        description: "Скрипка I, Скрипка II, Альт, Виолончель",
        instruments: [.violin, .violin, .viola, .cello]
    )

    static let pianoTrio = ScoreTemplate(
        name: "Фортепианное трио",
        icon: "music.note.list",
        description: "Скрипка, Виолончель, Фортепиано",
        instruments: [.violin, .cello, .piano]
    )

    static let windQuintet = ScoreTemplate(
        name: "Духовой квинтет",
        icon: "wind",
        description: "Флейта, Гобой, Кларнет, Валторна, Фагот",
        instruments: [.flute, .oboe, .clarinetBb, .hornF, .bassoon]
    )

    static let brassQuintet = ScoreTemplate(
        name: "Медный квинтет",
        icon: "music.note.list",
        description: "2 Трубы, Валторна, Тромбон, Туба",
        instruments: [.trumpet, .trumpet, .hornF, .trombone, .tuba]
    )

    static let guitarDuo = ScoreTemplate(
        name: "Гитарный дуэт",
        icon: "guitars",
        description: "Две классические гитары",
        instruments: [.classicalGuitar, .classicalGuitar]
    )

    // MARK: Vocal

    static let choirSATB = ScoreTemplate(
        name: "Хор SATB",
        icon: "person.3",
        description: "Сопрано, Контральто, Тенор, Бас",
        instruments: [.soprano, .alto, .tenorVoice, .bassVoice]
    )

    static let choirSATBPiano = ScoreTemplate(
        name: "Хор SATB + Фортепиано",
        icon: "person.3",
        description: "SATB хор с фортепианным аккомпанементом",
        instruments: [.soprano, .alto, .tenorVoice, .bassVoice, .piano]
    )

    static let voicePiano = ScoreTemplate(
        name: "Голос + Фортепиано",
        icon: "person.wave.2",
        description: "Сольный голос с фортепиано",
        instruments: [.soprano, .piano]
    )

    // MARK: Orchestra

    static let chamberOrchestra = ScoreTemplate(
        name: "Камерный оркестр",
        icon: "person.3.sequence",
        description: "Флейта, Гобой, 2 Скрипки, Альт, Виолончель, Контрабас",
        instruments: [.flute, .oboe, .violin, .violin, .viola, .cello, .doubleBass]
    )

    static let symphonyOrchestra = ScoreTemplate(
        name: "Симфонический оркестр",
        icon: "person.3.sequence",
        description: "Полный состав: духовые, медные, ударные, струнные",
        instruments: [
            // Woodwinds
            .flute, .flute, .oboe, .oboe, .clarinetBb, .clarinetBb, .bassoon, .bassoon,
            // Brass
            .hornF, .hornF, .hornF, .hornF, .trumpet, .trumpet, .trombone, .trombone, .tuba,
            // Percussion
            .timpani,
            // Strings
            .violin, .violin, .viola, .cello, .doubleBass,
        ]
    )

    // MARK: All templates grouped

    static let soloTemplates: [ScoreTemplate] = [
        .pianoSolo, .guitarSolo, .violinSolo, .celloSolo, .fluteSolo,
    ]

    static let chamberTemplates: [ScoreTemplate] = [
        .stringQuartet, .pianoTrio, .windQuintet, .brassQuintet, .guitarDuo,
    ]

    static let vocalTemplates: [ScoreTemplate] = [
        .choirSATB, .choirSATBPiano, .voicePiano,
    ]

    static let orchestralTemplates: [ScoreTemplate] = [
        .chamberOrchestra, .symphonyOrchestra,
    ]
}
