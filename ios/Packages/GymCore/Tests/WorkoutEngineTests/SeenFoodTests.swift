import Foundation
import Testing
@testable import WorkoutEngine

// #1012: Scan live names plain food from Apple's image classifier labels.
@Suite struct SeenFoodTests {
    @Test func labelsMapToFoods() {
        #expect(SeenFood.food(label: "croissant")?.id == "croissant")
        #expect(SeenFood.food(label: "Banana")?.id == "banana")
        #expect(SeenFood.food(label: "french_fries")?.id == "fries")
        #expect(SeenFood.food(label: "strawberry")?.id == "strawberries")
        #expect(SeenFood.food(label: "bagel")?.id == "bagel")
    }

    @Test func broadAndNonFoodLabelsAreSkipped() {
        #expect(SeenFood.food(label: "food") == nil)
        #expect(SeenFood.food(label: "baked_goods") == nil)
        #expect(SeenFood.food(label: "paper_bag") == nil)
        #expect(SeenFood.food(label: "suitcase") == nil)
        #expect(SeenFood.food(label: "rug") == nil)
    }

    @Test func clearGuessIsKeptAtOnce() {
        var t = SeenFood.Tracker()
        let out = t.look([.init("croissant", 0.82), .init("rug", 0.9)])
        #expect(out.map(\.id) == ["croissant"])
        #expect(t.look([.init("croissant", 0.9)]).isEmpty)
    }

    @Test func fairGuessNeedsTwoOfThreeLooks() {
        var t = SeenFood.Tracker()
        #expect(t.look([.init("apple", 0.4)]).isEmpty)
        #expect(t.look([.init("bagel", 0.35)]).isEmpty)
        #expect(t.look([.init("apple", 0.45)]).map(\.id) == ["apple"])
        #expect(t.look([.init("orange", 0.2)]).isEmpty)
    }

    @Test func forgottenFoodCanComeBack() {
        var t = SeenFood.Tracker()
        #expect(t.look([.init("banana", 0.7)]).count == 1)
        t.forget("banana")
        #expect(t.look([.init("banana", 0.7)]).map(\.id) == ["banana"])
    }
}
