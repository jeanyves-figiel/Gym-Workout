public struct Gym: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let location: String
    public let equipment: [Equipment]
    public let amenities: [String]
    /// Assumptions to verify on site.
    public let note: String

    public static let puls5 = Gym(
        id: "fitnesspark-puls5",
        name: "Fitnesspark Puls 5",
        location: "Giessereistrasse 18, 8005 Zürich",
        equipment: Equipment.allCases,
        amenities: ["Sauna ×2", "Steam bath", "Whirlpool", "Group classes"],
        note: "Large full-service club: free weights, machine circuits, functional zone, full cardio floor. Inventory assumed — untick anything missing."
    )
}
