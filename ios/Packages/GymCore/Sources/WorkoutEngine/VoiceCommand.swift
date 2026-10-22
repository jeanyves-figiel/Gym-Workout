import Foundation

/// Hands-free player (#412, design C): what the member said to the "Hey Coach" mic. Short commands run on the device
/// (offline, instant); anything else goes to Ask Coach as a question about the current exercise.
public enum VoiceCommand: Equatable, Sendable {
    /// Set done; `rir` when the member also said how hard (easy = 4, fail = 0, "two left" = 2).
    case done(rir: Int?)
    case kg(Double)
    /// "drop 5", "add 2.5 kilos".
    case kgBy(Double)
    /// "lighter" / "heavier": one stepper step.
    case kgStep(Int)
    case reps(Int)
    /// Reps and weight in one go (#617): "eight at eighty", "80 kilos for 8". Fills the set and logs it.
    case set(reps: Int, kg: Double)
    case skipRest
    case addRest
    case next
    case previous
    case ask(String)

    /// Parses one utterance. Speech recognition usually writes numbers as digits; small number words work too.
    public static func parse(_ said: String) -> VoiceCommand? {
        var t = " " + said.lowercased()
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: ",", with: " ")
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: ".")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " "
        for w in ["hey coach", "ok coach", "okay coach", "coach", "please"] { t = t.replacingOccurrences(of: " \(w) ", with: " ") }
        // Number words, tens and decimals too ("eighty two point five" → 82.5, #617).
        let words = foldNumbers(t.split(separator: " ").map(String.init))
        t = words.joined(separator: " ")
        guard !t.isEmpty else { return nil }
        let has = { (w: String) in words.contains(w) }
        let phrase = { (p: String) in (" " + t + " ").contains(" \(p) ") }
        let number = words.compactMap { Double($0) }.first
        let short = words.count <= 6

        // Questions go to the coach even when they hold a command word ("should I skip rest?").
        if words.first.map(questionStarts.contains) == true || said.contains("?") { return .ask(said.trimmingCharacters(in: .whitespaces)) }

        if words.count <= 8, let s = repsAndKg(words) { return .set(reps: s.reps, kg: s.kg) }

        if short, phrase("skip rest") || phrase("end rest") || phrase("stop rest") || ["go", "ready", "start", "lets go"].contains(t) {
            return .skipRest
        }
        if short, phrase("more rest") || phrase("add rest") || phrase("extra rest") || phrase("more time") { return .addRest }
        if short, phrase("next exercise") || phrase("skip exercise") || phrase("skip this") || t == "next" { return .next }
        if short, phrase("previous exercise") || phrase("go back") || t == "previous" || t == "back" { return .previous }

        if short, let n = number {
            let down = has("drop") || has("minus") || has("less") || has("lower") || has("remove") || has("take")
            let up = has("add") || has("plus") || has("more") || has("increase") || has("up")
            let kgWord = has("kg") || has("kilo") || has("kilos") || has("kilogram") || has("kilograms") || has("weight")
            if down != up, kgWord || !has("reps") { return .kgBy(down ? -n : n) }
            if has("reps") || has("rep") || has("did") { return .reps(Int(n)) }
            if kgWord { return .kg(n) }
        }
        if short, has("lighter") { return .kgStep(-1) }
        if short, has("heavier") { return .kgStep(1) }

        if short {
            let doneWords = phrase("set done") || phrase("log it") || phrase("log set") || has("done") || has("logged") || has("finished") || t == "log"
            if doneWords || phrase("one left") || phrase("two left") || phrase("three left") || has("failed") {
                return .done(rir: effort(words: words, phrase: phrase))
            }
        }
        return .ask(said.trimmingCharacters(in: .whitespaces))
    }

    private static func effort(words: [String], phrase: (String) -> Bool) -> Int? {
        if words.contains("failed") || words.contains("fail") || phrase("to failure") { return 0 }
        if phrase("1 left") { return 1 }
        if phrase("2 left") { return 2 }
        if phrase("3 left") { return 3 }
        if words.contains("easy") { return 4 }
        if words.contains("hard") || words.contains("tough") { return 1 }
        return nil
    }

    private static let kgWords: Set<String> = ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]
    private static let repWords: Set<String> = ["rep", "reps", "times"]

    /// "8 at 80" / "8 reps at 80 kg": reps then weight; "80 kg for 8": weight then reps.
    private static func repsAndKg(_ w: [String]) -> (reps: Int, kg: Double)? {
        for (i, word) in w.enumerated() where (word == "at" || word == "for") && i > 0 && i + 1 < w.count {
            var b = i - 1
            if b > 0, kgWords.contains(w[b]) || repWords.contains(w[b]) { b -= 1 }
            guard let before = Double(w[b]), let after = Double(w[i + 1]) else { continue }
            let (reps, kg) = word == "at" ? (before, after) : (after, before)
            guard reps >= 1, reps <= 100, reps == reps.rounded(), kg > 0, kg <= 500 else { continue }
            return (Int(reps), kg)
        }
        return nil
    }

    /// Turns runs of number words into one number: "one hundred and twenty" → 120, "sixty two point five" → 62.5,
    /// "a hundred" → 100, "seventy and a half" → 70.5. Digits and other words pass through.
    static func foldNumbers(_ w: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < w.count {
            if let (v, used) = number(w, from: i) {
                out.append(v == v.rounded() ? String(Int(v)) : String(v))
                i += used
            } else {
                out.append(w[i])
                i += 1
            }
        }
        return out
    }

    private static func number(_ w: [String], from s: Int) -> (Double, Int)? {
        var i = s
        var v: Double
        if i + 1 < w.count, w[i + 1] == "hundred", w[i] == "a" || units[w[i]] != nil {
            v = (units[w[i]] ?? 1) * 100
            i += 2
            if i + 1 < w.count, w[i] == "and", below100(w, i + 1) != nil { i += 1 }
            if let (r, n) = below100(w, i) { v += r; i += n }
        } else if let (r, n) = below100(w, i) {
            v = r
            i += n
        } else {
            return nil
        }
        if i + 1 < w.count, w[i] == "point", let d = units[w[i + 1]] ?? Double(w[i + 1]), d < 10, d == d.rounded() {
            v += d / 10
            i += 2
        } else if i + 2 < w.count, w[i] == "and", w[i + 1] == "a", w[i + 2] == "half" {
            v += 0.5
            i += 3
        }
        return (v, i - s)
    }

    private static func below100(_ w: [String], _ i: Int) -> (Double, Int)? {
        guard i < w.count else { return nil }
        if let u = units[w[i]] { return (u, 1) }
        guard let t = tens[w[i]] else { return nil }
        if i + 1 < w.count, let u = units[w[i + 1]], u >= 1, u <= 9 { return (t + u, 2) }
        return (t, 1)
    }

    private static let questionStarts: Set<String> = ["what", "why", "how", "should", "is", "can", "could", "which", "when", "where", "do", "does", "am", "will", "would"]

    private static let units: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
}
