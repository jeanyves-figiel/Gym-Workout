import Foundation
import HealthKit
import WorkoutEngine

/// Height / weight / age entered in-app when Apple Health doesn't have them,
/// plus optional, inclusive identity fields. Every field is optional.
struct BodyMetrics: Codable, Equatable, Sendable {
    /// Sex used only to refine physiological estimates (calories, heart-rate zones). Optional.
    enum Sex: String, Codable, CaseIterable, Identifiable {
        case female, male, intersex, other, preferNotToSay
        var id: String { rawValue }

        var label: String {
            switch self {
            case .female: "Female"
            case .male: "Male"
            case .intersex: "Intersex"
            case .other: "Other"
            case .preferNotToSay: "Prefer not to say"
            }
        }
    }

    /// How you identify. Never used in calculations. Optional.
    enum Gender: String, Codable, CaseIterable, Identifiable {
        case woman, man, nonBinary, genderfluid, agender, twoSpirit, questioning, selfDescribe, preferNotToSay
        var id: String { rawValue }

        var label: String {
            switch self {
            case .woman: "Woman"
            case .man: "Man"
            case .nonBinary: "Non-binary"
            case .genderfluid: "Genderfluid"
            case .agender: "Agender"
            case .twoSpirit: "Two-Spirit"
            case .questioning: "Questioning"
            case .selfDescribe: "Prefer to self-describe"
            case .preferNotToSay: "Prefer not to say"
            }
        }
    }

    var heightCm: Double?
    var weightKg: Double?
    var birthYear: Int?
    var sex: Sex?
    var gender: Gender?
    /// Free text when `gender == .selfDescribe`.
    var genderDescription: String?

    var isEmpty: Bool {
        heightCm == nil && weightKg == nil && birthYear == nil && sex == nil && gender == nil && genderDescription == nil
    }
}

/// What we read from Apple Health. Stays on device (never sent to the server).
struct HealthSnapshot: Equatable {
    var weightKg: Double?
    var weightDate: Date?
    var heightCm: Double?
    var birthYear: Int?
    var sex: BodyMetrics.Sex?
    var restingHR: Double?
    var restingHRBaseline: Double?
    var hrv: Double?
    var hrvBaseline: Double?
    var vo2Max: Double?
    var sleepHours: Double?
    var climbingThisWeek = 0
    var climbingPerWeek4w: Double?
    /// Climbing workouts of the last 4 weeks from every app, newest first (#44).
    var recentClimbs: [ClimbEntry] = []
    var weightTrend: [TrendPoint] = []
    var vo2Trend: [TrendPoint] = []

    struct TrendPoint: Equatable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var hasRecoveryData: Bool { hrv != nil || restingHR != nil || sleepHours != nil }
}

enum Readiness: String {
    case ready, normal, easy

    var title: String {
        switch self {
        case .ready: "Ready to push"
        case .normal: "Train as planned"
        case .easy: "Take it easier"
        }
    }

    var advice: String {
        switch self {
        case .ready: "Recovery markers look good — go for quality reps."
        case .normal: "One marker is off. Follow the plan, keep RPE honest."
        case .easy: "Several markers are low. Drop 1 RPE, skip the last set, prioritise mobility."
        }
    }

    /// Flag thresholds (also quoted in the info sheet).
    static let hrvFloor = 0.85
    static let restHRRise = 5.0
    static let minSleep = 6.0

    /// HRV vs 30-day baseline, resting HR vs baseline, last night's sleep.
    static func assess(_ s: HealthSnapshot) -> (Readiness, [String])? {
        guard s.hasRecoveryData else { return nil }
        var low: [String] = []
        if let h = s.hrv, let b = s.hrvBaseline, b > 0, h < b * hrvFloor { low.append("HRV below your baseline") }
        if let r = s.restingHR, let b = s.restingHRBaseline, r > b + restHRRise { low.append("Resting HR elevated") }
        if let sl = s.sleepHours, sl < minSleep { low.append("Short sleep") }
        return (low.count >= 2 ? .easy : low.count == 1 ? .normal : .ready, low)
    }
}

@MainActor @Observable
final class HealthManager {
    private let store = HKHealthStore()
    private static let connectedKey = "healthConnected"
    private static let writeKey = "healthWriteWorkouts"

    private(set) var connected = UserDefaults.standard.bool(forKey: HealthManager.connectedKey)
    private(set) var writeWorkouts = UserDefaults.standard.object(forKey: HealthManager.writeKey) as? Bool ?? true
    var snapshot = HealthSnapshot()
    var error: String?

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private let bpm = HKUnit.count().unitDivided(by: .minute())

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [
            HKQuantityType(.bodyMass), HKQuantityType(.height), HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.vo2Max), HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
        ]
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { s.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { s.insert(sex) }
        return s
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass), HKQuantityType(.height)]
    }

    func setWriteWorkouts(_ on: Bool) {
        writeWorkouts = on
        UserDefaults.standard.set(on, forKey: HealthManager.writeKey)
    }

    func connect() async {
        guard available else {
            error = "Apple Health isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            connected = true
            UserDefaults.standard.set(true, forKey: HealthManager.connectedKey)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Read

    func refresh() async {
        guard connected, available else { return }
        var s = HealthSnapshot()
        let now = Date()
        let d30 = now.addingTimeInterval(-30 * 86_400)

        if let w = await latest(.bodyMass) {
            s.weightKg = w.quantity.doubleValue(for: .gramUnit(with: .kilo))
            s.weightDate = w.endDate
        }
        if let h = await latest(.height) { s.heightCm = h.quantity.doubleValue(for: .meterUnit(with: .centi)) }
        s.birthYear = (try? store.dateOfBirthComponents())?.year
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: s.sex = .female
        case .male: s.sex = .male
        case .other: s.sex = .other
        default: s.sex = nil
        }
        s.restingHR = await latest(.restingHeartRate)?.quantity.doubleValue(for: bpm)
        s.restingHRBaseline = await average(.restingHeartRate, unit: bpm, from: d30, to: now)
        s.hrv = await latest(.heartRateVariabilitySDNN)?.quantity.doubleValue(for: .secondUnit(with: .milli))
        s.hrvBaseline = await average(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: d30, to: now)
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        s.vo2Max = await latest(.vo2Max)?.quantity.doubleValue(for: vo2Unit)
        s.sleepHours = await sleepLastNight()
        s.weightTrend = await trend(.bodyMass, unit: .gramUnit(with: .kilo), days: 120)
        s.vo2Trend = await trend(.vo2Max, unit: vo2Unit, days: 365)

        let cal = Progression.calendar()
        let weekStart = Progression.weekStart(now, cal)
        s.climbingThisWeek = await climbingCount(from: weekStart, to: now)
        let fourWeeks = cal.date(byAdding: .weekOfYear, value: -4, to: weekStart)!
        let past = await climbingCount(from: fourWeeks, to: weekStart)
        s.climbingPerWeek4w = past > 0 ? Double(past) / 4 : nil
        s.recentClimbs = await climbs(from: fourWeeks, to: now)
        snapshot = s
    }

    private func latest(_ id: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        let d = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        return try? await d.result(for: store).first
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        let pred = HKSamplePredicate.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: to))
        let d = HKStatisticsQueryDescriptor(predicate: pred, options: .discreteAverage)
        return try? await d.result(for: store)?.averageQuantity()?.doubleValue(for: unit)
    }

    private func trend(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Double) async -> [HealthSnapshot.TrendPoint] {
        let from = Date().addingTimeInterval(-days * 86_400)
        let d = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: nil))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)])
        let samples = (try? await d.result(for: store)) ?? []
        return samples.map { .init(date: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func sleepLastNight() async -> Double? {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: Date())!)!
        let d = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))],
            sortDescriptors: [])
        guard let samples = try? await d.result(for: store), !samples.isEmpty else { return nil }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let secs = samples.filter { asleep.contains($0.value) }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return secs > 0 ? secs / 3600 : nil
    }

    private func climbingCount(from: Date, to: Date) async -> Int {
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .climbing),
            HKQuery.predicateForSamples(withStart: from, end: to),
        ])
        let d = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [])
        return (try? await d.result(for: store).count) ?? 0
    }

    private static let climbIdKey = "MonkeyWorkoutClimbId"

    private func climbs(from: Date, to: Date) async -> [ClimbEntry] {
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .climbing),
            HKQuery.predicateForSamples(withStart: from, end: to),
        ])
        let d = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor<HKWorkout>(\.startDate, order: .reverse)], limit: 50)
        let workouts = (try? await d.result(for: store)) ?? []
        return workouts.map { w in
            let meta = w.metadata ?? [:]
            let id = (meta[Self.climbIdKey] as? String).flatMap(UUID.init(uuidString:)) ?? w.uuid
            return ClimbEntry(
                id: id, start: w.startDate, end: w.endDate, source: w.sourceRevision.source.name,
                kind: (meta["MonkeyWorkoutClimbType"] as? String).flatMap(ClimbKind.init(rawValue:)),
                effort: (meta["MonkeyWorkoutEffort"] as? NSNumber)?.intValue,
                topGrade: meta["MonkeyWorkoutTopGrade"] as? String)
        }
    }

    // MARK: Write

    /// Saves a logged climb as an Apple Health Climbing workout. Returns true when written.
    @discardableResult
    func saveClimb(_ log: ClimbLog, kcal: Double?) async -> Bool {
        guard connected, available, writeWorkouts else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = .climbing
        config.locationType = log.kind == .outdoor ? .outdoor : .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: log.start)
            if let kcal {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: log.start, end: log.end)
                try await builder.addSamples([sample])
            }
            var meta: [String: Any] = [
                HKMetadataKeyIndoorWorkout: log.kind != .outdoor,
                Self.climbIdKey: log.id.uuidString,
                "MonkeyWorkoutClimbType": log.kind.rawValue,
                "MonkeyWorkoutEffort": log.effort,
            ]
            if let g = log.topGrade, !g.isEmpty { meta["MonkeyWorkoutTopGrade"] = g }
            try await builder.addMetadata(meta)
            try await builder.endCollection(at: log.end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Removes the Health workout written for a logged climb, if any.
    func deleteClimb(_ id: UUID) async {
        guard connected, available else { return }
        let pred = HKQuery.predicateForObjects(withMetadataKey: Self.climbIdKey, allowedValues: [id.uuidString])
        _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: pred)
    }

    /// Saves the session as an Apple Health workout; returns heart-rate stats measured during it (e.g. by a Watch).
    func save(_ record: WorkoutRecord) async -> (avg: Double?, max: Double?) {
        guard connected, available, writeWorkouts else { return (nil, nil) }
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: record.startedAt)
            if let kcal = record.kcal {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: record.startedAt, end: record.endedAt)
                try await builder.addSamples([sample])
            }
            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: true,
                "MonkeyWorkoutTitle": record.title,
                "MonkeyWorkoutSets": record.totalSets,
            ])
            try await builder.endCollection(at: record.endedAt)
            _ = try await builder.finishWorkout()
        } catch {
            self.error = error.localizedDescription
        }
        return await heartRate(from: record.startedAt, to: record.endedAt)
    }

    func heartRate(from: Date, to: Date) async -> (avg: Double?, max: Double?) {
        guard connected, available else { return (nil, nil) }
        let pred = HKSamplePredicate.quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: from, end: to))
        let d = HKStatisticsQueryDescriptor(predicate: pred, options: [.discreteAverage, .discreteMax])
        let stats = try? await d.result(for: store)
        return (stats?.averageQuantity()?.doubleValue(for: bpm), stats?.maximumQuantity()?.doubleValue(for: bpm))
    }

    /// Writes body metrics entered in-app back to Apple Health.
    func saveBody(_ body: BodyMetrics) async {
        guard connected, available else { return }
        var samples: [HKQuantitySample] = []
        let now = Date()
        if let kg = body.weightKg {
            samples.append(HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: now, end: now))
        }
        if let cm = body.heightCm {
            samples.append(HKQuantitySample(type: HKQuantityType(.height), quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: cm), start: now, end: now))
        }
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
