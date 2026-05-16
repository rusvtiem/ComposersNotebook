import Foundation

// MARK: - ChordSymbol (G7, Am, C/E)
//
// Аккордовый символ над нотой — стандарт для гитарной/джазовой записи.
// Парсим строку формата:
//   "C"        — мажорное трезвучие до
//   "Am"       — минорное трезвучие ля
//   "G7"       — доминантсептаккорд соль
//   "Cmaj7"    — мажорный септаккорд до
//   "C#m7b5"   — полууменьшённый си-бемоль на до-диез
//   "C/E"      — до-мажор с басом ми

struct ChordSymbol: Codable, Equatable, Hashable {

    enum Quality: String, Codable, Hashable {
        case major          // ""
        case minor          // "m"
        case diminished     // "dim" / "°"
        case augmented      // "aug" / "+"
        case sus2           // "sus2"
        case sus4           // "sus4"
        case dominant7      // "7"
        case major7         // "maj7"
        case minor7         // "m7"
        case minorMajor7    // "mMaj7"
        case diminished7    // "dim7" / "°7"
        case halfDiminished // "m7b5" / "ø7"
        case dominant9      // "9"
        case major9         // "maj9"
        case minor9         // "m9"
        case dominant11     // "11"
        case dominant13     // "13"
        case sixth          // "6"
        case minorSixth     // "m6"
        case add9           // "add9"
        case add11          // "add11"
        case fifth          // "5" (power chord)

        var suffix: String {
            switch self {
            case .major: return ""
            case .minor: return "m"
            case .diminished: return "dim"
            case .augmented: return "aug"
            case .sus2: return "sus2"
            case .sus4: return "sus4"
            case .dominant7: return "7"
            case .major7: return "maj7"
            case .minor7: return "m7"
            case .minorMajor7: return "mMaj7"
            case .diminished7: return "dim7"
            case .halfDiminished: return "m7b5"
            case .dominant9: return "9"
            case .major9: return "maj9"
            case .minor9: return "m9"
            case .dominant11: return "11"
            case .dominant13: return "13"
            case .sixth: return "6"
            case .minorSixth: return "m6"
            case .add9: return "add9"
            case .add11: return "add11"
            case .fifth: return "5"
            }
        }

        /// Интервалы аккорда от корня в полутонах.
        var intervals: [Int] {
            switch self {
            case .major: return [0, 4, 7]
            case .minor: return [0, 3, 7]
            case .diminished: return [0, 3, 6]
            case .augmented: return [0, 4, 8]
            case .sus2: return [0, 2, 7]
            case .sus4: return [0, 5, 7]
            case .dominant7: return [0, 4, 7, 10]
            case .major7: return [0, 4, 7, 11]
            case .minor7: return [0, 3, 7, 10]
            case .minorMajor7: return [0, 3, 7, 11]
            case .diminished7: return [0, 3, 6, 9]
            case .halfDiminished: return [0, 3, 6, 10]
            case .dominant9: return [0, 4, 7, 10, 14]
            case .major9: return [0, 4, 7, 11, 14]
            case .minor9: return [0, 3, 7, 10, 14]
            case .dominant11: return [0, 4, 7, 10, 14, 17]
            case .dominant13: return [0, 4, 7, 10, 14, 21]
            case .sixth: return [0, 4, 7, 9]
            case .minorSixth: return [0, 3, 7, 9]
            case .add9: return [0, 4, 7, 14]
            case .add11: return [0, 4, 7, 17]
            case .fifth: return [0, 7]
            }
        }
    }

    /// Корень аккорда — высота без октавы (C, C#, D, ..., B).
    var root: PitchName
    var rootAccidental: Accidental

    /// Качество аккорда (major/minor/7/maj7/...).
    var quality: Quality

    /// Бас-нота для slash-аккордов (например, C/E — бас E).
    /// nil = бас совпадает с корнем.
    var bassNote: PitchName?
    var bassAccidental: Accidental?

    /// Текстовое представление (G7, Am, C/E).
    var displayText: String {
        var s = root.englishName
        s += rootAccidental == .natural ? "" : rootAccidental.displaySymbol
        s += quality.suffix
        if let bn = bassNote {
            s += "/" + bn.englishName
            if let ba = bassAccidental, ba != .natural {
                s += ba.displaySymbol
            }
        }
        return s
    }

    init(
        root: PitchName,
        rootAccidental: Accidental = .natural,
        quality: Quality = .major,
        bassNote: PitchName? = nil,
        bassAccidental: Accidental? = nil
    ) {
        self.root = root
        self.rootAccidental = rootAccidental
        self.quality = quality
        self.bassNote = bassNote
        self.bassAccidental = bassAccidental
    }

    /// MIDI ноты аккорда в заданной октаве (по умолчанию 4-й, диапазон гитары/пианино).
    func midiNotes(rootOctave: Int = 4) -> [Int] {
        let rootSemitone = root.semitoneOffset + rootAccidental.semitoneOffset
        let rootMIDI = 12 * (rootOctave + 1) + rootSemitone
        return quality.intervals.map { rootMIDI + $0 }
    }
}

// MARK: - String Parser

extension ChordSymbol {

    /// Распарсить строку вида "Am7", "G/B", "C#maj7", "Bbm7b5".
    /// Возвращает nil если строка некорректна.
    static func parse(_ text: String) -> ChordSymbol? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var s = trimmed

        // 1. Root (A-G)
        guard let rootChar = s.first, ("A"..."G").contains(rootChar) else { return nil }
        s.removeFirst()
        let root = PitchName.fromEnglishName(String(rootChar)) ?? .C

        // 2. Root accidental
        var rootAcc: Accidental = .natural
        if s.first == "#" { rootAcc = .sharp; s.removeFirst() }
        else if s.first == "b" && s.count > 1 && !s.hasPrefix("b5") && !s.hasPrefix("b6") && !s.hasPrefix("b7") && !s.hasPrefix("b9") {
            rootAcc = .flat; s.removeFirst()
        }

        // 3. Bass note (after "/")
        var bass: (name: PitchName, acc: Accidental)? = nil
        if let slashIdx = s.firstIndex(of: "/") {
            let bassPart = String(s[s.index(after: slashIdx)...])
            s = String(s[..<slashIdx])
            if let bc = bassPart.first, ("A"..."G").contains(bc) {
                let bn = PitchName.fromEnglishName(String(bc)) ?? .C
                var ba: Accidental = .natural
                if bassPart.count > 1 {
                    let after = bassPart[bassPart.index(after: bassPart.startIndex)]
                    if after == "#" { ba = .sharp }
                    else if after == "b" { ba = .flat }
                }
                bass = (bn, ba)
            }
        }

        // 4. Quality — match longest suffix first
        let qualities: [(String, Quality)] = [
            ("mMaj7", .minorMajor7),
            ("maj9", .major9),
            ("maj7", .major7),
            ("dim7", .diminished7),
            ("m7b5", .halfDiminished),
            ("add9", .add9),
            ("add11", .add11),
            ("sus2", .sus2),
            ("sus4", .sus4),
            ("m9", .minor9),
            ("m7", .minor7),
            ("m6", .minorSixth),
            ("dim", .diminished),
            ("aug", .augmented),
            ("13", .dominant13),
            ("11", .dominant11),
            ("9", .dominant9),
            ("7", .dominant7),
            ("6", .sixth),
            ("5", .fifth),
            ("m", .minor),
        ]
        var quality: Quality = .major
        for (suffix, q) in qualities {
            if s.hasPrefix(suffix) {
                quality = q
                s.removeFirst(suffix.count)
                break
            }
        }

        return ChordSymbol(
            root: root,
            rootAccidental: rootAcc,
            quality: quality,
            bassNote: bass?.name,
            bassAccidental: bass?.acc
        )
    }
}
