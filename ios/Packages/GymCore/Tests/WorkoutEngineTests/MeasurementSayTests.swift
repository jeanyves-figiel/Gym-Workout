import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct MeasurementSayTests {
    @Test func weightSaidToCoach() {
        #expect(MeasurementSay.parse("Enter my measurement, weight is now 66")?.weightKg == 66)
        #expect(MeasurementSay.parse("I weigh 72.5 kg")?.weightKg == 72.5)
        #expect(MeasurementSay.parse("poids 66,5")?.weightKg == 66.5)
        #expect(MeasurementSay.parse("Log 66 kg") == MeasurementSay(weightKg: 66))
        #expect(MeasurementSay.parse("weight 150 lbs today")?.weightKg == 68)
    }

    @Test func girthsSidesAndBodyFat() {
        let s = MeasurementSay.parse("log waist 82 cm, left arm 35.5 and body fat 15%")
        #expect(s == MeasurementSay(bodyFatPct: 15, girthsCm: ["waist": 82, "upperArmL": 35.5]))
        #expect(MeasurementSay.parse("15% body fat today")?.bodyFatPct == 15)
        #expect(MeasurementSay.parse("waist 32 inches")?.girthsCm["waist"] == 81.3)
        #expect(s?.summary == "body fat 15%, waist 82 cm, left upper arm 35.5 cm")
    }

    @Test func questionsAndLiftsAreLeftToCoach() {
        #expect(MeasurementSay.parse("Is my weight trending well?") == nil)
        #expect(MeasurementSay.parse("how much should my weight be at 66") == nil)
        #expect(MeasurementSay.parse("I lifted 100 kg on bench today") == nil)
        #expect(MeasurementSay.parse("my bench weight is 80") == nil)
        #expect(MeasurementSay.parse("45 min full body") == nil)
        #expect(MeasurementSay.parse("weight is now 900") == nil)
        #expect(MeasurementSay.parse("100 kg") == nil)
    }

    @Test func writesOntoTodaysEntry() {
        var today = BodyMeasurement(date: Date(), weightKg: 70)
        today.setGirth(.waist, 84)
        let e = MeasurementSay(weightKg: 66).applied(to: today)
        #expect(e.id == today.id && e.weightKg == 66 && e.girth(.waist) == 84)
    }
}
