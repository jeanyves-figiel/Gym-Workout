import Foundation

/// Scan live sees plain food (#1012): Apple's on-device image classifier names what's in view ("croissant", "banana",
/// "french_fries"); this turns its labels into foods on the list and only keeps a food once it has been seen steadily,
/// so a passing guess doesn't land on What I have.
public enum SeenFood {
    /// Classifier labels whose words don't match a food's name or alias.
    static let labels: [String: String] = [
        "french fries": "fries", "fries": "fries", "potato chips": "crisps", "chips": "crisps",
        "bell pepper": "bell-pepper", "pepper veggie": "bell-pepper", "pepper": "bell-pepper",
        "zucchini": "courgette", "eggplant": "aubergine", "mushroom": "mushrooms", "watermelon": "melon", "cantaloupe": "melon",
        "honeydew": "melon", "strawberry": "strawberries", "blueberry": "blueberries", "raspberry": "raspberries",
        "cherry": "cherries", "grape": "grapes", "berry": "berries", "date fruit": "dates",
        "bread": "bread-white", "toast": "bread-white", "loaf": "bread-white", "sliced bread": "bread-white",
        "brioche": "croissant", "pain au chocolat": "croissant", "pastry": "croissant",
        "cookie": "biscuits", "biscuit": "biscuits", "chocolate": "milk-chocolate", "chocolate bar": "milk-chocolate",
        "pizza": "frozen-pizza", "sausage": "pork-sausage", "hot dog": "pork-sausage", "steak": "beef-steak",
        "fried egg": "egg", "boiled egg": "egg", "eggs": "egg", "scrambled eggs": "egg",
        "yogurt": "yogurt", "yoghurt": "yogurt", "ice cream": "ice-cream", "soda": "soft-drink", "orange juice": "orange-juice",
        "wine": "red-wine", "red wine": "red-wine", "white wine": "white-wine", "nut": "mixed-nuts", "nuts": "mixed-nuts",
        "leafy green": "lettuce", "salad": "lettuce", "corn": "sweetcorn", "pretzel": "pretzels", "rice cake": "rice-cakes",
    ]

    /// Too broad to name a food on their own ("fruit", "food"), or things around food ("bag", "plate").
    static let broad: Set<String> = [
        "food", "fruit", "vegetable", "produce", "baked goods", "dessert", "meal", "dish", "snack", "drink", "beverage",
        "citrus fruit", "bag", "paper bag", "plate", "bowl", "container", "package", "bottle", "cup", "jar",
    ]

    /// A food for one classifier label (lowercased, `_` read as a space), nil when it isn't food or is too broad.
    public static func food(label: String, own: [Food] = []) -> Food? {
        let name = FoodBook.fold(label).replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !broad.contains(name) else { return nil }
        if let id = labels[name], let f = FoodBook.food(id, own: own) { return f }
        // The label is the food's name or one of its aliases ("croissant", "banana", "bagel", "gipfeli").
        return FoodBook.find(in: name, own: own).first
    }

    /// One classifier answer: the label and how sure it was (0–1).
    public struct Guess: Equatable, Sendable {
        public var label: String
        public var confidence: Double
        public init(_ label: String, _ confidence: Double) { self.label = label; self.confidence = confidence }
    }

    /// Keeps a food once it was seen clearly once (`sure`) or fairly in two of the last three looks (`fair`).
    public struct Tracker: Sendable {
        public static let sure = 0.6
        public static let fair = 0.3
        private var recent: [Set<String>] = []
        private var kept: Set<String> = []

        public init() {}

        /// Feeds one look's guesses; returns the foods seen steadily for the first time, best first.
        public mutating func look(_ guesses: [Guess], own: [Food] = []) -> [Food] {
            var now: [String: (Food, Double)] = [:]
            for g in guesses where g.confidence >= Self.fair {
                guard let f = SeenFood.food(label: g.label, own: own) else { continue }
                if g.confidence > (now[f.id]?.1 ?? 0) { now[f.id] = (f, g.confidence) }
            }
            recent.append(Set(now.keys))
            if recent.count > 3 { recent.removeFirst() }
            var out: [(Food, Double)] = []
            for (id, (f, c)) in now where !kept.contains(id) {
                let times = recent.filter { $0.contains(id) }.count
                if c >= Self.sure || times >= 2 {
                    kept.insert(id)
                    out.append((f, c))
                }
            }
            return out.sorted { $0.1 > $1.1 }.map(\.0)
        }

        /// Takes a food back out (unticked or removed), so it can be found again.
        public mutating func forget(_ id: String) { kept.remove(id) }
    }
}
