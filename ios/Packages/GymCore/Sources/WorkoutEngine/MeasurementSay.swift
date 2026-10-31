import Foundation

/// "Weight is now 66", "log waist 82 cm and body fat 15%" (#1000): body measurements told to Coach, read on the iPhone
/// and logged at once (free, offline, no AI). Nil when the text isn't a measurement to log, so Coach answers it instead.
public struct MeasurementSay: Equatable, Sendable {
    public var weightKg: Double?
    public var bodyFatPct: Double?
    /// Keyed like `BodyMeasurement.girthsCm` ("waist", "upperArmL").
    public var girthsCm: [String: Double] = [:]

    public init(weightKg: Double? = nil, bodyFatPct: Double? = nil, girthsCm: [String: Double] = [:]) {
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.girthsCm = girthsCm
    }

    public var isEmpty: Bool { weightKg == nil && bodyFatPct == nil && girthsCm.isEmpty }

    private enum Metric: Equatable { case weight, fat, girth(GirthSite) }

    private static let questionWords: Set<String> = [
        "how", "what", "why", "when", "should", "can", "could", "would", "is", "am", "are", "do", "does", "which",
        "comment", "pourquoi", "quel", "quelle", "est",
    ]
    private static let siteWords: [String: GirthSite] = [
        "neck": .neck, "cou": .neck, "shoulder": .shoulders, "shoulders": .shoulders, "epaules": .shoulders,
        "chest": .chest, "poitrine": .chest, "waist": .waist, "taille": .waist, "belly": .waist, "tour": .waist,
        "hip": .hips, "hips": .hips, "hanches": .hips, "glutes": .hips, "arm": .upperArm, "arms": .upperArm, "biceps": .upperArm,
        "bicep": .upperArm, "bras": .upperArm, "forearm": .forearm, "forearms": .forearm,
        "thigh": .thigh, "thighs": .thigh, "cuisse": .thigh, "cuisses": .thigh, "calf": .calf, "calves": .calf, "mollet": .calf, "mollets": .calf,
    ]
    private static let weightWords: Set<String> = ["weight", "weigh", "weighs", "weighed", "bodyweight", "poids", "pese", "peser"]
    /// "I lifted 100 kg": about the bar, not the body.
    private static let liftWords: Set<String> = [
        "lift", "lifted", "lifting", "bench", "squat", "squats", "press", "deadlift", "deadlifts", "row", "curl", "curls", "rep", "reps",
        "set", "sets", "bar", "barbell", "dumbbell", "dumbbells", "kettlebell", "machine", "plate", "plates", "pr", "max", "goal", "target",
        "lose", "gain", "want", "barre", "halteres", "serie", "series", "objectif",
    ]
    /// A number with a unit but no word for it ("log 66 kg") counts only with one of these.
    private static let logWords: Set<String> = [
        "log", "enter", "record", "save", "add", "note", "track", "measurement", "measurements", "today", "now", "morning",
        "enregistre", "ajoute", "mesure", "mesures", "aujourd", "maintenant",
    ]

    /// What the member said, or nil when it holds no measurement or asks a question about one.
    public static func parse(_ text: String) -> MeasurementSay? {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        if folded.contains("?") { return nil }
        let tokens = tokenize(folded)
        guard let first = tokens.first, !questionWords.contains(first),
              !tokens.contains(where: { liftWords.contains($0) }) else { return nil }
        let logging = tokens.contains { logWords.contains($0) }
        var out = MeasurementSay()
        var metric: Metric?
        var side: LimbSide?
        var since = 0
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let next = i + 1 < tokens.count ? tokens[i + 1] : ""
            if t == "left" || t == "gauche" { side = .left }
            else if t == "right" || t == "droit" || t == "droite" { side = .right }
            else if t == "fat" || t == "bf" || t == "graisse" || (t == "body" && next == "fat") {
                metric = .fat; since = 0
            } else if t == "upper", next == "arm" {
                metric = .girth(.upperArm); since = 0; i += 1
            } else if t == "avant", next == "bras" {
                metric = .girth(.forearm); since = 0; i += 1
            } else if let site = siteWords[t] {
                metric = .girth(site); since = 0
            } else if weightWords.contains(t), metric == nil || metric == .weight {
                metric = .weight; since = 0
            } else if let n = Double(t.replacingOccurrences(of: ",", with: ".")) {
                let unit = next
                // "Log 66 kg" with no word for it is the body weight; "15% body fat" names it after the number.
                let after = i + 2 < tokens.count ? tokens[i + 2] : ""
                let m: Metric? = metric
                    ?? (unit == "%" && ["body", "fat", "bf", "graisse"].contains(after) ? .fat : nil)
                    ?? (logging && ["kg", "kilo", "kilos", "lb", "lbs", "pounds"].contains(unit) ? .weight : nil)
                if let m, out.set(m, n, unit: unit, side: side) { metric = nil; side = nil }
            }
            since += 1
            if since > 6 { metric = nil }
            i += 1
        }
        return out.isEmpty ? nil : out
    }

    private mutating func set(_ m: Metric, _ n: Double, unit: String, side: LimbSide?) -> Bool {
        switch m {
        case .weight:
            let kg = ["lb", "lbs", "pound", "pounds", "livres"].contains(unit) ? n * 0.45359237 : n
            guard BodyMeasurement.weightRange.contains(kg) else { return false }
            weightKg = (kg * 10).rounded() / 10
        case .fat:
            guard BodyMeasurement.bodyFatRange.contains(n) else { return false }
            bodyFatPct = (n * 10).rounded() / 10
        case let .girth(site):
            let cm = ["in", "inch", "inches", "pouces"].contains(unit) ? n * 2.54 : n
            guard BodyMeasurement.girthRange.contains(cm) else { return false }
            girthsCm[BodyMeasurement.key(site, site.bilateral ? side : nil)] = (cm * 10).rounded() / 10
        }
        return true
    }

    private static let token = try! NSRegularExpression(pattern: "[0-9]+(?:[.,][0-9]+)?|[a-z]+|%")

    /// Lowercased, accent-free words, numbers ("66,5" stays one) and %.
    static func tokenize(_ s: String) -> [String] {
        let r = NSRange(s.startIndex..., in: s)
        return token.matches(in: s, range: r).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    /// `entry` with these values written in (today's entry, or a new one).
    public func applied(to entry: BodyMeasurement) -> BodyMeasurement {
        var e = entry
        if let weightKg { e.weightKg = weightKg }
        if let bodyFatPct { e.bodyFatPct = bodyFatPct }
        for (k, v) in girthsCm {
            var g = e.girthsCm ?? [:]
            g[k] = v
            e.girthsCm = g
        }
        return e
    }

    /// "weight 66 kg, waist 82 cm" for Coach's reply.
    public var summary: String {
        var parts: [String] = []
        if let weightKg { parts.append("weight \(Self.number(weightKg)) kg") }
        if let bodyFatPct { parts.append("body fat \(Self.number(bodyFatPct))%") }
        for site in GirthSite.allCases {
            for side in [nil, LimbSide.left, .right] {
                guard let v = girthsCm[BodyMeasurement.key(site, side)] else { continue }
                let name = side == nil ? site.label.lowercased() : "\(side == .left ? "left" : "right") \(site.label.lowercased())"
                parts.append("\(name) \(Self.number(v)) cm")
            }
        }
        return parts.joined(separator: ", ")
    }

    private static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
