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
        for (word, n) in numberWords { t = t.replacingOccurrences(of: " \(word) ", with: " \(n) ") }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let words = t.split(separator: " ").map(String.init)
        let has = { (w: String) in words.contains(w) }
        let phrase = { (p: String) in (" " + t + " ").contains(" \(p) ") }
        let number = words.compactMap { Double($0) }.first
        let short = words.count <= 6

        // Questions go to the coach even when they hold a command word ("should I skip rest?").
        if words.first.map(questionStarts.contains) == true || said.contains("?") { return .ask(said.trimmingCharacters(in: .whitespaces)) }

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

    private static let questionStarts: Set<String> = ["what", "why", "how", "should", "is", "can", "could", "which", "when", "where", "do", "does", "am", "will", "would"]

    private static let numberWords: [(String, String)] = [
        ("twenty", "20"), ("nineteen", "19"), ("eighteen", "18"), ("seventeen", "17"), ("sixteen", "16"), ("fifteen", "15"),
        ("fourteen", "14"), ("thirteen", "13"), ("twelve", "12"), ("eleven", "11"), ("ten", "10"), ("nine", "9"), ("eight", "8"),
        ("seven", "7"), ("six", "6"), ("five", "5"), ("four", "4"), ("three", "3"), ("two", "2"), ("one", "1"), ("zero", "0"),
    ]
}
