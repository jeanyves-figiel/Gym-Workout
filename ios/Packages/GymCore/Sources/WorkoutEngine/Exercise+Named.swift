import Foundation

extension Exercise {
    /// The exercise Coach names in an answer (#412): exact name first (any case), else the closest name that contains
    /// all its words ("DB bench press" finds "Dumbbell bench press").
    public static func named(_ name: String, custom: CustomExercises = .shared) -> Exercise? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        let all = catalog + custom.active
        if let e = all.first(where: { normalized($0.name) == key }) { return e }
        let words = key.split(separator: " ").map { aliases[String($0)] ?? String($0) }
        return all
            .filter { e in
                let n = normalized(e.name)
                return words.allSatisfy { n.contains($0) }
            }
            .min { $0.name.count < $1.name.count }
    }

    private static let aliases = ["db": "dumbbell", "bb": "barbell", "kb": "kettlebell"]

    private static func normalized(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
