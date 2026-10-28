import Foundation
import Testing
@testable import WorkoutEngine

// #872: a nutrition label read by the camera fills a new food per 100 g.
@Suite struct NutritionLabelTests {
    @Test func readsAnEnglishLabelPer100() {
        let l = NutritionLabel.read([
            "Nutrition per 100 g | per 45 g", "Energy 1556 kJ / 372 kcal 167 kcal", "Fat 7.1 g 3.2 g",
            "of which saturates 1.2 g", "Carbohydrate 58 g 26 g", "of which sugars 12 g", "Fibre 8 g", "Protein 13 g 5.9 g", "Salt 0.3 g",
        ])
        #expect(l == NutritionLabel(kcal: 372, protein: 13, carbs: 58, fat: 7.1, fibre: 8, salt: 0.3))
        #expect(l.usable)
    }

    @Test func readsGermanAndFrenchWithCommasAndSplitRows() {
        let de = NutritionLabel.read(["Brennwert 1550 kJ", "Fett", "7,1 g", "davon gesättigte Fettsäuren 1,2 g", "Kohlenhydrate 58 g",
                                      "davon Zucker 12 g", "Eiweiß 13 g", "Salz <0,5 g"])
        #expect(de.kcal == 370)
        #expect(de.fat == 7.1)
        #expect(de.carbs == 58)
        #expect(de.protein == 13)
        #expect(de.salt == 0.5)
        let fr = NutritionLabel.read(["Valeurs pour 100 ml", "Énergie 180 kJ", "42 kcal", "Matières grasses 0 g",
                                      "dont acides gras saturés 0 g", "Glucides 10,6 g", "dont sucres 10,6 g", "Protéines 0 g", "Sel 0,01 g"])
        #expect(fr.kcal == 42)
        #expect(fr.carbs == 10.6)
        #expect(fr.perMl)
        #expect(fr.usable)
    }

    @Test func framesMergeAndMakeAFood() throws {
        let a = NutritionLabel.read(["Protein 13 g", "Fat 7.1 g"])
        #expect(!a.usable)
        let both = a.merged(NutritionLabel.read(["Energy 372 kcal", "Carbohydrate 58 g"]))
        #expect(both.usable)
        let f = both.food(name: " Oat granola ", serving: 45)
        #expect(f.id == "label-oat-granola")
        #expect(f.name == "Oat granola")
        #expect(f.per100.kcal == 372)
        #expect(f.portion.g == 45)
        #expect(f.group == .grain)
        #expect(f.fits(FuelPrefs()))
        let again = both.food(name: "Oat granola", serving: 45, own: [f])
        #expect(again.id == "label-oat-granola-2")
        let data = try JSONEncoder().encode(f)
        #expect(try JSONDecoder().decode(Food.self, from: data) == f)
    }

    @Test func ignoresWordsThatOnlyLookLikeNutrients() {
        let l = NutritionLabel.read(["Fatigue-free", "Selleriesalat 2024", "Best before 12.2027"])
        #expect(l.isEmpty)
    }
}
