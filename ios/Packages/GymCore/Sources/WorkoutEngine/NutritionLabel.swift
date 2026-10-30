import Foundation

// Read a nutrition label (#872, epic #865): the camera reads the label's text on the iPhone (Vision, free, offline) and
// this turns its lines into values per 100 g (ml). Labels in English, German, French and Italian. When a label has two
// columns (per 100 g | per portion) the first number on a row wins, which is the per 100 g one on EU and Swiss labels.

public struct NutritionLabel: Equatable, Sendable {
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var fibre: Double?
    public var salt: Double?
    /// "per 100 ml" seen: a drink.
    public var perMl = false

    public init(kcal: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, fibre: Double? = nil,
                salt: Double? = nil, perMl: Bool = false) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fibre = fibre
        self.salt = salt
        self.perMl = perMl
    }

    public enum Field: String, CaseIterable, Sendable { case kcal, protein, carbs, fat, fibre, salt }

    public subscript(_ f: Field) -> Double? {
        get {
            switch f {
            case .kcal: kcal
            case .protein: protein
            case .carbs: carbs
            case .fat: fat
            case .fibre: fibre
            case .salt: salt
            }
        }
        set {
            switch f {
            case .kcal: kcal = newValue
            case .protein: protein = newValue
            case .carbs: carbs = newValue
            case .fat: fat = newValue
            case .fibre: fibre = newValue
            case .salt: salt = newValue
            }
        }
    }

    /// Energy plus the three macros read: enough to use.
    public var usable: Bool { kcal != nil && protein != nil && carbs != nil && fat != nil }

    public var isEmpty: Bool { Field.allCases.allSatisfy { self[$0] == nil } && !perMl }

    /// A newer frame's values win; a value seen once stays while the camera moves.
    public func merged(_ newer: NutritionLabel) -> NutritionLabel {
        var out = self
        for f in Field.allCases { if let v = newer[f] { out[f] = v } }
        out.perMl = perMl || newer.perMl
        return out
    }

    // Keyword stems, folded (lowercase, no accents). A row that names a part first ("saturates", "of which sugars",
    // "gesättigte Fettsäuren") is skipped: it also says "fat" or sits right under carbs.
    private static let parts = ["saturate", "gesattigt", "satures", "saturi", "sugar", "zucker", "sucre", "zuccher",
                                "mono-unsat", "monounsat", "polyunsat", "einfach", "mehrfach", "polyol", "starch", "starke", "amidon", "amido"]
    private static let words: [(Field, [String])] = [
        (.kcal, ["energy", "energie", "energia", "brennwert", "kcal", "calories"]),
        (.protein, ["protein", "eiweiss", "eiweiß", "proteine", "proteines"]),
        (.carbs, ["carbohydrate", "kohlenhydrat", "glucide", "carboidrat", "carbs"]),
        (.fibre, ["fibre", "fiber", "ballaststoff", "fibra"]),
        (.salt, ["salt", "salz", "sel", "sale"]),
        (.fat, ["fat", "fett", "matieres grasses", "lipide", "grassi"]),
    ]

    /// Reads the lines of one camera frame (or one photo).
    public static func read(_ lines: [String]) -> NutritionLabel {
        var out = NutritionLabel()
        var kcalExact = false
        let folded = lines.map(FoodBook.fold)
        for (i, line) in folded.enumerated() {
            if line.contains("100 ml") || line.contains("100ml") { out.perMl = true }
            guard case let (field, at)? = keyword(line) else { continue }
            if let part = parts.compactMap({ line.range(of: $0)?.lowerBound }).min(), part < at { continue }
            let next = i + 1 < folded.count && keyword(folded[i + 1]) == nil ? " " + folded[i + 1] : ""
            if field == .kcal {
                // "Energy 1550 kJ" then "372 kcal": a kcal figure beats one worked out from kJ.
                guard !kcalExact, case let (v, exact)? = energy(line) ?? energy(line + next), v <= 900 else { continue }
                out.kcal = v
                kcalExact = exact
                continue
            }
            // "Protein" alone, its "13 g" on the next line (a table read as two blocks).
            guard out[field] == nil, let v = number(in: line) ?? number(in: next), v <= 100 else { continue }
            out[field] = v
        }
        return out
    }

    /// The row's nutrient and where its name starts.
    private static func keyword(_ line: String) -> (Field, String.Index)? {
        var best: (Field, String.Index)?
        for (field, stems) in words {
            for w in stems {
                guard let r = find(line, w) else { continue }
                if best.map({ r < $0.1 }) ?? true { best = (field, r) }
            }
        }
        return best
    }

    /// A food for the member's own list, from these values (kcal from the macros when the label had none).
    public func food(name: String, serving: Double, own: [Food] = []) -> Food {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = clean.isEmpty ? "Scanned food" : String(clean.prefix(40))
        var id = "label-\(FoodBook.slug(title))"
        var n = 2
        while FoodBook.food(id, own: own) != nil {
            id = "label-\(FoodBook.slug(title))-\(n)"
            n += 1
        }
        // Their own food from their own pack: no diet guess, so it shows for every diet.
        var f = Food(id: id, name: title, emoji: perMl ? "🥤" : "🏷️", group: perMl ? .drink : .snack,
                     per100: Macros(protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, kcal: kcal),
                     portion: Food.Serving(g: max(5, min(1000, serving)), label: perMl ? "1 glass" : "1 serving"), base: .vegan)
        f.fibre = fibre
        f.salt = salt
        if perMl {
            f.aisle = "drinks"
        } else {
            f.group = switch f.role {
            case .protein: .protein
            case .carbs: .grain
            case .fat: .fat
            case .veg: .veg
            case .extra: .snack
            }
        }
        return f
    }

    private static func find(_ line: String, _ word: String) -> String.Index? {
        // Short stems ("sel", "fat", "sale") as whole words only: "fat" not in "fatigue", "sel" not in "selleri".
        guard word.count <= 4 else { return line.range(of: word)?.lowerBound }
        return line.range(of: "(^|[^a-z])\(word)([^a-z]|$)", options: .regularExpression)?.lowerBound
    }

    private static var numberPattern: NSRegularExpression { try! NSRegularExpression(pattern: "(\\d+(?:[.,]\\d+)?)\\s*(kcal|kj|mg|g)?") }

    /// First amount on the line: "7,1 g" → 7.1, "<0.5 g" → 0.5, "350 mg" → 0.35.
    static func number(in line: String) -> Double? {
        let ns = line as NSString
        for m in numberPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let unit = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            // "100 g" in "per 100 g" is the column header, not a value.
            let before = ns.substring(to: m.range.location)
            if before.hasSuffix("per ") || before.hasSuffix("pro ") || before.hasSuffix("pour ") || before.hasSuffix("per") { continue }
            guard unit != "kcal", unit != "kj", let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "."))
            else { continue }
            return unit == "mg" ? v / 1000 : v
        }
        return nil
    }

    /// "1550 kJ / 372 kcal" → (372, exact); only kJ → kcal worked out from kJ.
    static func energy(_ line: String) -> (Double, Bool)? {
        let ns = line as NSString
        var kj: Double?
        for m in numberPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) where m.range(at: 2).location != NSNotFound {
            guard let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { continue }
            switch ns.substring(with: m.range(at: 2)) {
            case "kcal": return (v, true)
            case "kj": if kj == nil { kj = v }
            default: break
            }
        }
        return kj.map { (($0 / 4.184).rounded(), false) }
    }
}
