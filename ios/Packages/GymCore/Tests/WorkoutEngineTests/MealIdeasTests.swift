import Foundation
import Testing
@testable import WorkoutEngine

struct MealIdeasTests {
    @Test func totalsAndServingsComeFromTheFoodList() throws {
        let egg = try #require(FoodBook.food("egg"))
        let idea = MealIdea(name: "Eggs", minutes: 10, items: [.init(foodId: "egg", grams: 150), .init(foodId: "no-such-food", grams: 80)])
        #expect(idea.foods().count == 1)
        #expect(abs(idea.totals().protein - egg.per100.protein * 1.5) < 0.01)
        let s = try #require(idea.servings().first)
        #expect(abs(s.grams(egg) - 150) < 1)
    }

    @Test func extraMealsAskForTheNearestMeal() {
        #expect(MealIdea.meal(.lunch) == "lunch")
        #expect(MealIdea.meal(.recovery) == "dinner")
        #expect(MealIdea.meal(.pre) == "snack")
        #expect(MealIdea.meal(.bedtime) == "snack")
    }
}
