import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok: \(msg)") } else { print("  FAIL: \(msg)"); failures += 1 }
}
func spell(_ p: Pitch) -> String { "\(p.name.englishName)\(p.accidental == .natural ? "" : p.accidental.displaySymbol)\(p.octave)" }

print("== M1: direction-aware chromatic spelling ==")
check(spell(Pitch.fromMIDI(61, preferFlats: false)) == "C♯4", "61 sharp -> C#4 (got \(spell(Pitch.fromMIDI(61, preferFlats: false))))")
check(spell(Pitch.fromMIDI(61, preferFlats: true))  == "D♭4", "61 flat -> Db4 (got \(spell(Pitch.fromMIDI(61, preferFlats: true))))")
check(spell(Pitch.fromMIDI(58, preferFlats: true))  == "B♭3", "58 flat -> Bb3 (got \(spell(Pitch.fromMIDI(58, preferFlats: true))))")
check(spell(Pitch.fromMIDI(58, preferFlats: false)) == "A♯3", "58 sharp -> A#3 (got \(spell(Pitch.fromMIDI(58, preferFlats: false))))")
check(spell(Pitch.fromMIDI(60, preferFlats: true))  == "C4",  "60 flat -> C4 natural (got \(spell(Pitch.fromMIDI(60, preferFlats: true))))")
// midi must be preserved either way
for m in 55...75 {
    check(Pitch.fromMIDI(m, preferFlats: true).midiNote == m, "flat spelling preserves midi \(m)")
    check(Pitch.fromMIDI(m, preferFlats: false).midiNote == m, "sharp spelling preserves midi \(m)")
}

print("== M3: enharmonic respell (same sound, next spelling) ==")
let cs4 = Pitch(name: .C, octave: 4, accidental: .sharp)   // midi 61
let r1 = cs4.respelledEnharmonic()
check(r1.midiNote == cs4.midiNote, "respell keeps sound (\(spell(cs4)) -> \(spell(r1)))")
check(spell(r1) == "D♭4", "C#4 respells to Db4 (got \(spell(r1)))")
let r2 = r1.respelledEnharmonic()
check(r2.midiNote == cs4.midiNote, "respell keeps sound on 2nd cycle")
check(spell(r2) == "C♯4", "Db4 respells back to C#4 (got \(spell(r2)))")

let e4 = Pitch(name: .E, octave: 4, accidental: .natural) // midi 64
let re = e4.respelledEnharmonic()
check(re.midiNote == e4.midiNote, "E4 respell keeps sound (-> \(spell(re)))")
check(spell(re) != "E4", "E4 respell changes spelling (got \(spell(re)))")

// every chromatic pitch must respell to the same sound and eventually cycle back
for m in 55...75 {
    let p = Pitch.fromMIDI(m)
    let rr = p.respelledEnharmonic()
    check(rr.midiNote == m, "respell preserves midi \(m) (\(spell(p)) -> \(spell(rr)))")
}

print(failures == 0 ? "\nALL GREEN" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
