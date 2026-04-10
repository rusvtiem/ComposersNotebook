import SwiftUI

// MARK: - SMuFL / Bravura Music Font Manager
// Provides professional music notation symbols via the Bravura font (SMuFL standard)
// Falls back to system Unicode symbols when Bravura is not available

@MainActor
class MusicFontManager: ObservableObject {
    static let shared = MusicFontManager()

    @Published var isBravuraAvailable: Bool = false
    private let bravuraFontName = "Bravura"

    private init() {
        isBravuraAvailable = UIFont(name: bravuraFontName, size: 12) != nil
        if !isBravuraAvailable {
            registerBundledFont()
        }
    }

    /// Try to register Bravura font from app bundle
    private func registerBundledFont() {
        guard let fontURL = Bundle.main.url(forResource: "Bravura", withExtension: "otf")
                ?? Bundle.main.url(forResource: "Bravura", withExtension: "ttf") else {
            return
        }

        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
            isBravuraAvailable = true
        }
    }

    /// Get the music font at the given size
    func musicFont(size: CGFloat) -> Font {
        if isBravuraAvailable {
            return .custom(bravuraFontName, size: size)
        }
        return .system(size: size)
    }

    /// Get UIFont for Canvas drawing
    func uiMusicFont(size: CGFloat) -> UIFont {
        if isBravuraAvailable {
            return UIFont(name: bravuraFontName, size: size) ?? .systemFont(ofSize: size)
        }
        return .systemFont(ofSize: size)
    }
}

// MARK: - SMuFL Code Points
// Standard Music Font Layout Unicode code points for Bravura

enum MusicSymbol {
    // Noteheads
    static let noteheadWhole = "\u{E0A2}"         // Whole note
    static let noteheadHalf = "\u{E0A3}"           // Half note
    static let noteheadBlack = "\u{E0A4}"          // Filled notehead (quarter+)

    // Rests
    static let restWhole = "\u{E4E3}"              // Whole rest
    static let restHalf = "\u{E4E4}"               // Half rest
    static let restQuarter = "\u{E4E5}"            // Quarter rest
    static let restEighth = "\u{E4E6}"             // Eighth rest
    static let rest16th = "\u{E4E7}"               // 16th rest
    static let rest32nd = "\u{E4E8}"               // 32nd rest

    // Clefs
    static let gClef = "\u{E050}"                  // Treble clef
    static let fClef = "\u{E062}"                  // Bass clef
    static let cClef = "\u{E05C}"                  // Alto/Tenor clef

    // Accidentals
    static let accidentalFlat = "\u{E260}"         // Flat
    static let accidentalNatural = "\u{E261}"      // Natural
    static let accidentalSharp = "\u{E262}"        // Sharp
    static let accidentalDoubleSharp = "\u{E263}"  // Double sharp
    static let accidentalDoubleFlat = "\u{E264}"   // Double flat

    // Flags
    static let flag8thUp = "\u{E240}"              // Eighth flag up
    static let flag8thDown = "\u{E241}"            // Eighth flag down
    static let flag16thUp = "\u{E242}"             // 16th flag up
    static let flag16thDown = "\u{E243}"           // 16th flag down
    static let flag32ndUp = "\u{E244}"             // 32nd flag up
    static let flag32ndDown = "\u{E245}"           // 32nd flag down

    // Dynamics
    static let dynamicPiano = "\u{E520}"           // p
    static let dynamicMezzo = "\u{E521}"           // m
    static let dynamicForte = "\u{E522}"           // f
    static let dynamicRinforzando = "\u{E523}"     // r
    static let dynamicSforzando = "\u{E524}"       // s
    static let dynamicZ = "\u{E525}"               // z

    // Articulations
    static let articAccentAbove = "\u{E4A0}"       // Accent >
    static let articStaccatoAbove = "\u{E4A2}"     // Staccato .
    static let articTenutoAbove = "\u{E4A4}"       // Tenuto -
    static let articMarcatoAbove = "\u{E4AC}"      // Marcato ^
    static let articFermataAbove = "\u{E4C0}"      // Fermata

    // Time signatures
    static let timeSig0 = "\u{E080}"               // Time sig digit 0
    static let timeSig1 = "\u{E081}"               // Time sig digit 1
    static let timeSig2 = "\u{E082}"               // ...
    static let timeSig3 = "\u{E083}"
    static let timeSig4 = "\u{E084}"
    static let timeSig5 = "\u{E085}"
    static let timeSig6 = "\u{E086}"
    static let timeSig7 = "\u{E087}"
    static let timeSig8 = "\u{E088}"
    static let timeSig9 = "\u{E089}"

    // Barlines
    static let barlineSingle = "\u{E030}"
    static let barlineDouble = "\u{E031}"
    static let barlineFinal = "\u{E032}"
    static let repeatLeft = "\u{E040}"
    static let repeatRight = "\u{E041}"
    static let repeatDots = "\u{E043}"

    // Misc
    static let augmentationDot = "\u{E1E7}"        // Dotted note dot
    static let segno = "\u{E047}"
    static let coda = "\u{E048}"

    /// Get rest symbol for duration
    static func rest(for duration: DurationValue) -> String {
        switch duration {
        case .whole: return restWhole
        case .half: return restHalf
        case .quarter: return restQuarter
        case .eighth: return restEighth
        case .sixteenth: return rest16th
        case .thirtySecond: return rest32nd
        }
    }

    /// Get flag symbol for duration and stem direction
    static func flag(for duration: DurationValue, stemUp: Bool) -> String? {
        switch duration {
        case .eighth: return stemUp ? flag8thUp : flag8thDown
        case .sixteenth: return stemUp ? flag16thUp : flag16thDown
        case .thirtySecond: return stemUp ? flag32ndUp : flag32ndDown
        default: return nil
        }
    }

    /// Get time signature digit
    static func timeSigDigit(_ digit: Int) -> String {
        let digits = [timeSig0, timeSig1, timeSig2, timeSig3, timeSig4,
                      timeSig5, timeSig6, timeSig7, timeSig8, timeSig9]
        guard digit >= 0, digit <= 9 else { return "\(digit)" }
        return digits[digit]
    }

    /// Get clef symbol
    static func clef(_ clef: Clef) -> String {
        switch clef {
        case .treble: return gClef
        case .bass: return fClef
        case .alto, .tenor: return cClef
        }
    }

    /// Get accidental symbol
    static func accidental(_ acc: Accidental) -> String {
        switch acc {
        case .doubleFlat: return accidentalDoubleFlat
        case .flat: return accidentalFlat
        case .natural: return accidentalNatural
        case .sharp: return accidentalSharp
        case .doubleSharp: return accidentalDoubleSharp
        }
    }

    /// Fallback symbols (system font, no Bravura needed)
    enum Fallback {
        static func clef(_ clef: Clef) -> String {
            clef.symbol
        }

        static func accidental(_ acc: Accidental) -> String {
            acc.displaySymbol
        }

        static func rest(_ duration: DurationValue) -> String {
            switch duration {
            case .whole: return "—"
            case .half: return "▬"
            case .quarter: return "𝄾"
            case .eighth: return "𝄾"
            case .sixteenth: return "𝄿"
            case .thirtySecond: return "𝅀"
            }
        }
    }
}
