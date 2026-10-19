import Foundation
import CoreLocation
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
    /// Body figure drawn on muscle maps (#110). Display only; nil = suggested from `sex`.
    var figure: BodyMapLayout.Figure?
    /// How we talk to you (#415). Picked pronouns; nil = prefilled from `gender` (see `effectivePronouns`).
    var pronouns: Pronouns?
    /// Own words when `pronouns == .custom`.
    var pronounsCustom: String?
    /// What the coach calls you; nil = your name when there is one.
    var coachCall: CoachCall?
    /// Pronouns next to your nickname in Community.
    var showPronouns: Bool?

    var isEmpty: Bool {
        heightCm == nil && weightKg == nil && birthYear == nil && sex == nil && gender == nil && genderDescription == nil
            && figure == nil && pronouns == nil && pronounsCustom == nil && coachCall == nil && showPronouns == nil
    }

    var effectivePronouns: Pronouns? { pronouns ?? Pronouns.suggested(gender: gender?.rawValue) }
    /// "she/her", custom words, or nil (neutral).
    var pronounsText: String? { Pronouns.text(effectivePronouns, custom: pronounsCustom) }

    /// Figure prefilled when none was picked: F for female sex, M otherwise.
    static func suggestedFigure(sex: Sex?) -> BodyMapLayout.Figure { sex == .female ? .female : .male }
}

/// What we read from Apple Health. Stays on device (never sent to the server); last copy cached on device
/// so the first frame after launch shows it (#202).
struct HealthSnapshot: Equatable, Codable {
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
    /// Other sport workouts of the last 4 weeks from every app (Watch, Strava, Garmin…), newest first (#416).
    var recentSports: [SportEntry] = []
    var weightTrend: [TrendPoint] = []
    var vo2Trend: [TrendPoint] = []
    /// Body composition and waist (#185), latest values and the last year.
    var bodyFatPct: Double?
    var leanKg: Double?
    var waistCm: Double?
    var bodyFatTrend: [TrendPoint] = []
    var leanTrend: [TrendPoint] = []
    var waistTrend: [TrendPoint] = []

    struct TrendPoint: Equatable, Identifiable, Codable {
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
    /// Health values known (cached or read). Until then "Connect Apple Health" prompts stay hidden for connected users.
    private(set) var loaded = false
    var error: String?
    /// Connected before body measurements (#185) were asked for: Health needs one more permission sheet.
    private(set) var needsMeasurementAccess = false
    /// Connected before Daily Move (#454): steps and floors need one more permission sheet.
    private(set) var needsMoveAccess = false

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Last snapshot on device (Application Support, protected until first unlock): launch shows it at once,
    /// `refresh()` replaces it in the background (#202).
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("health-snapshot.json")
    }

    init() {
        guard connected else { return }
        if let data = try? Data(contentsOf: Self.cacheURL), let cached = try? JSONDecoder().decode(HealthSnapshot.self, from: data) {
            snapshot = cached
            loaded = true
        }
        // Background delivery needs its observer set up on every launch, including the background ones it causes.
        startMoveObserver()
    }

    /// Sign-out / account deletion: drop the cached readings file (the next refresh writes a fresh one).
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// Nothing to wait for: not connected, or Health unavailable on this device.
    var settled: Bool { loaded || !connected || !available }

    private func cache(_ s: HealthSnapshot) {
        snapshot = s
        loaded = true
        guard let data = try? JSONEncoder().encode(s) else { return }
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private let bpm = HKUnit.count().unitDivided(by: .minute())

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [
            HKQuantityType(.bodyMass), HKQuantityType(.height), HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.vo2Max), HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
            HKQuantityType(.bodyFatPercentage), HKQuantityType(.leanBodyMass), HKQuantityType(.waistCircumference),
            // Sport session page (#416): the route of workouts recorded by the Watch or other apps.
            HKSeriesType.workoutRoute(),
            // Daily Move (#454): walking and stairs count toward the level.
            HKQuantityType(.stepCount), HKQuantityType(.flightsClimbed),
        ]
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { s.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { s.insert(sex) }
        return s
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass), HKQuantityType(.height),
         HKQuantityType(.bodyFatPercentage), HKQuantityType(.leanBodyMass), HKQuantityType(.waistCircumference),
         HKQuantityType(.dietaryWater)]
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
            startMoveObserver()
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Read

    /// Reads every value at once (queries run concurrently), then replaces the cached snapshot.
    func refresh() async {
        guard connected, available else { return }
        var s = HealthSnapshot()
        let now = Date()
        let d30 = now.addingTimeInterval(-30 * 86_400)
        let kg = HKUnit.gramUnit(with: .kilo), cm = HKUnit.meterUnit(with: .centi), ms = HKUnit.secondUnit(with: .milli)
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        let cal = Progression.calendar()
        let weekStart = Progression.weekStart(now, cal)
        let fourWeeks = cal.date(byAdding: .weekOfYear, value: -4, to: weekStart)!

        async let weight = latestValue(.bodyMass, unit: kg)
        async let height = latestValue(.height, unit: cm)
        async let restingHR = latestValue(.restingHeartRate, unit: bpm)
        async let restingHRBaseline = average(.restingHeartRate, unit: bpm, from: d30, to: now)
        async let hrv = latestValue(.heartRateVariabilitySDNN, unit: ms)
        async let hrvBaseline = average(.heartRateVariabilitySDNN, unit: ms, from: d30, to: now)
        async let vo2Max = latestValue(.vo2Max, unit: vo2Unit)
        async let sleep = sleepLastNight()
        async let weightTrend = trend(.bodyMass, unit: kg, days: 365)
        async let bodyFat = latestValue(.bodyFatPercentage, unit: .percent())
        async let lean = latestValue(.leanBodyMass, unit: kg)
        async let waist = latestValue(.waistCircumference, unit: cm)
        async let bodyFatTrend = trend(.bodyFatPercentage, unit: .percent(), days: 365)
        async let leanTrend = trend(.leanBodyMass, unit: kg, days: 365)
        async let waistTrend = trend(.waistCircumference, unit: cm, days: 365)
        async let vo2Trend = trend(.vo2Max, unit: vo2Unit, days: 365)
        async let climbingThisWeek = climbingCount(from: weekStart, to: now)
        async let climbingPast = climbingCount(from: fourWeeks, to: weekStart)
        async let recentClimbs = climbs(from: fourWeeks, to: now)
        async let recentSports = sports(from: fourWeeks, to: now)
        async let measurementStatus = requestStatus()
        async let moveStatus = moveRequestStatus()

        s.birthYear = (try? store.dateOfBirthComponents())?.year
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: s.sex = .female
        case .male: s.sex = .male
        case .other: s.sex = .other
        default: s.sex = nil
        }
        if let w = await weight {
            s.weightKg = w.value
            s.weightDate = w.date
        }
        s.heightCm = await height?.value
        s.restingHR = await restingHR?.value
        s.restingHRBaseline = await restingHRBaseline
        s.hrv = await hrv?.value
        s.hrvBaseline = await hrvBaseline
        s.vo2Max = await vo2Max?.value
        s.sleepHours = await sleep
        s.weightTrend = await weightTrend
        s.bodyFatPct = await bodyFat.map { $0.value * 100 }
        s.leanKg = await lean?.value
        s.waistCm = await waist?.value
        s.bodyFatTrend = await bodyFatTrend.map { .init(date: $0.date, value: $0.value * 100) }
        s.leanTrend = await leanTrend
        s.waistTrend = await waistTrend
        s.vo2Trend = await vo2Trend
        s.climbingThisWeek = await climbingThisWeek
        let past = await climbingPast
        s.climbingPerWeek4w = past > 0 ? Double(past) / 4 : nil
        s.recentClimbs = await recentClimbs
        s.recentSports = await recentSports
        needsMoveAccess = await moveStatus == .shouldRequest
        // Steps and floors only ask for themselves, so the body-measurement prompt doesn't show for them.
        needsMeasurementAccess = await measurementStatus == .shouldRequest && !needsMoveAccess
        cache(s)
        await refreshMove()
    }

    private func requestStatus() async -> HKAuthorizationRequestStatus? {
        try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
    }

    // MARK: Daily Move (#454)

    private static let moveTypes: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.flightsClimbed)]
    private var moveObserving = false

    private func moveRequestStatus() async -> HKAuthorizationRequestStatus? {
        try? await store.statusForAuthorizationRequest(toShare: [], read: Self.moveTypes)
    }

    /// Steps and floors per day (four weeks: two for the usual of each of the last two weeks) and the hour the
    /// member usually walks (last two weeks), into `MoveStore`.
    func refreshMove() async {
        guard connected, available else { return }
        let cal = Progression.calendar()
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let from = cal.date(byAdding: .day, value: -27, to: today),
              let twoWeeks = cal.date(byAdding: .day, value: -14, to: today) else { return }
        async let steps = sums(.stepCount, from: from, to: now, every: DateComponents(day: 1), anchor: today)
        async let floors = sums(.flightsClimbed, from: from, to: now, every: DateComponents(day: 1), anchor: today)
        async let hourly = sums(.stepCount, from: twoWeeks, to: today, every: DateComponents(hour: 1), anchor: today)
        let s = await steps, f = await floors
        guard !s.isEmpty || !f.isEmpty else { return }
        let days = Set(s.keys).union(f.keys).map { DayMove(day: $0, steps: s[$0] ?? 0, floors: f[$0] ?? 0) }
        var perHour: [Int: Int] = [:]
        for (date, n) in await hourly { perHour[cal.component(.hour, from: date), default: 0] += n }
        // Keep older days already read: active weeks and XP since `since` stay put after they leave the window.
        var merged = Dictionary(MoveStore.shared.saved.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for d in days { merged[d.day] = d }
        MoveStore.shared.update(days: Array(merged.values), hour: perHour.isEmpty ? nil : DailyMove.usualHour(perHour))
    }

    /// Cumulative sums per interval, keyed by interval start.
    private func sums(_ id: HKQuantityTypeIdentifier, from: Date, to: Date, every: DateComponents, anchor: Date) async -> [Date: Int] {
        let pred = HKSamplePredicate.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: to))
        let d = HKStatisticsCollectionQueryDescriptor(predicate: pred, options: .cumulativeSum, anchorDate: anchor, intervalComponents: every)
        guard let collection = try? await d.result(for: store) else { return [:] }
        var out: [Date: Int] = [:]
        collection.enumerateStatistics(from: from, to: to) { stats, _ in
            if let q = stats.sumQuantity() { out[stats.startDate] = Int(q.doubleValue(for: .count()).rounded()) }
        }
        return out
    }

    /// New steps wake the app about once an hour, even in the background: refresh and maybe nudge.
    private func startMoveObserver() {
        guard connected, available, !moveObserving else { return }
        moveObserving = true
        let type = HKQuantityType(.stepCount)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { return completion() }
            Task { @MainActor in
                await self?.moveChanged()
                completion()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }

    private func moveChanged() async {
        await refreshMove()
        await checkMoveNudge()
    }

    /// One nudge on a slow day (#454): from the member's walking hour, only when well behind their usual, never
    /// after a workout or sport (any app's, in Health), a "Rest day" tap, or in quiet hours.
    func checkMoveNudge(now: Date = Date()) async {
        let move = MoveStore.shared
        let notify = NotificationManager.shared
        guard connected, available, move.hasData, notify.prefs.moveNudges else { return }
        let cal = Progression.calendar()
        let key = move.key(now)
        let minute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let today = move.today
        let usual = move.usual
        var trained = move.saved.busy == key
        if !trained { trained = await workoutCount(from: cal.startOfDay(for: now), to: now) > 0 }
        guard DailyMove.nudge(steps: today.steps, usual: usual, hour: move.hour, nowMinute: minute, trainedToday: trained,
                              restDay: move.saved.restDay == key, nudgedToday: move.saved.nudged == key, prefs: notify.prefs) == nil
        else { return }
        move.markNudged(now)
        await notify.postMoveNudge(steps: today.steps, usual: usual)
    }

    private func workoutCount(from: Date, to: Date) async -> Int {
        let d = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForSamples(withStart: from, end: to))], sortDescriptors: [], limit: 1)
        return (try? await d.result(for: store).count) ?? 0
    }

    private func latestValue(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, date: Date)? {
        guard let sample = await latest(id) else { return nil }
        return (sample.quantity.doubleValue(for: unit), sample.endDate)
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

    private static let sportIdKey = "MonkeyWorkoutSportId"

    /// Workouts of other sports (#416): every app's, except climbing (read above) and gym-type workouts.
    private func sports(from: Date, to: Date) async -> [SportEntry] {
        let pred = HKQuery.predicateForSamples(withStart: from, end: to)
        let d = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor<HKWorkout>(\.startDate, order: .reverse)], limit: 120)
        let workouts = (try? await d.result(for: store)) ?? []
        let meters = HKUnit.meter()
        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming,
                                                         .distanceDownhillSnowSports]
        return workouts.compactMap { (w: HKWorkout) -> SportEntry? in
            let meta = w.metadata ?? [:]
            guard let sport = (meta["MonkeyWorkoutSport"] as? String).flatMap(Sport.init(rawValue:)) ?? Self.sport(for: w.workoutActivityType),
                  sport != .climbing else { return nil }
            let id = (meta[Self.sportIdKey] as? String).flatMap(UUID.init(uuidString:)) ?? w.uuid
            let stats = w.allStatistics
            let meters_ = distanceTypes.compactMap { stats[HKQuantityType($0)]?.sumQuantity()?.doubleValue(for: meters) }.reduce(0, +)
            let hr = stats[HKQuantityType(.heartRate)]
            return SportEntry(
                id: id, sport: sport, start: w.startDate, end: w.endDate, source: w.sourceRevision.source.name,
                effort: (meta["MonkeyWorkoutEffort"] as? NSNumber)?.intValue,
                distanceKm: meters_ > 0 ? meters_ / 1000 : nil,
                elevationM: (meta[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: meters),
                avgHR: hr?.averageQuantity()?.doubleValue(for: bpm),
                maxHR: hr?.maximumQuantity()?.doubleValue(for: bpm),
                kcal: stats[HKQuantityType(.activeEnergyBurned)]?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                local: meta[Self.sportIdKey] != nil,
                tracked: meta["MonkeyWorkoutSport"] != nil && meta[Self.sportIdKey] == nil)
        }
    }

    /// Route, elevation, speed and laps of a Health sport workout (#416 session page), nil without a route.
    func track(for id: UUID) async -> SportTrack? {
        guard connected, available else { return nil }
        let d = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: id))], sortDescriptors: [], limit: 1)
        guard let workout = try? await d.result(for: store).first else { return nil }
        let laps = (workout.workoutEvents ?? []).filter { $0.type == .lap || $0.type == .segment }
            .map { SportTrack.Lap(start: $0.dateInterval.start, end: $0.dateInterval.end) }
        let routes = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [])
        var locations: [CLLocation] = []
        for case let route as HKWorkoutRoute in (try? await routes.result(for: store)) ?? [] {
            locations += await routeLocations(route)
        }
        locations.sort { $0.timestamp < $1.timestamp }
        guard locations.count >= 2 || !laps.isEmpty else { return nil }
        // Heart rate per point (#445 map colour): nearest sample within a minute.
        let hrQuery = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate),
                                         predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let beats = ((try? await hrQuery.result(for: store)) ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: bpm)) }
        var b = 0
        var points: [SportTrack.Point] = []
        for (i, l) in locations.enumerated() {
            while b + 1 < beats.count && abs(beats[b + 1].0.timeIntervalSince(l.timestamp)) <= abs(beats[b].0.timeIntervalSince(l.timestamp)) { b += 1 }
            let hr = beats.indices.contains(b) && abs(beats[b].0.timeIntervalSince(l.timestamp)) <= 60 ? beats[b].1 : nil
            var speed = l.speed
            if speed < 0, i > 0 {
                let prev = locations[i - 1]
                let dt = l.timestamp.timeIntervalSince(prev.timestamp)
                speed = dt > 0 ? l.distance(from: prev) / dt : 0
            }
            points.append(.init(lat: l.coordinate.latitude, lon: l.coordinate.longitude, alt: l.altitude, speed: max(0, speed), time: l.timestamp, hr: hr))
        }
        return SportTrack(points: points, laps: laps)
    }

    private func routeLocations(_ route: HKWorkoutRoute) async -> [CLLocation] {
        await withCheckedContinuation { (cont: CheckedContinuation<[CLLocation], Never>) in
            var all: [CLLocation] = []
            var resumed = false
            let q = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                all += locations ?? []
                if (done || error != nil) && !resumed {
                    resumed = true
                    cont.resume(returning: all)
                }
            }
            store.execute(q)
        }
    }

    /// Sport of a Health workout type; nil for gym-type and everyday activities (strength, walking, mobility…).
    static func sport(for type: HKWorkoutActivityType) -> Sport? {
        switch type {
        case .snowboarding: .snowboard
        case .downhillSkiing, .snowSports: .ski
        case .crossCountrySkiing: .crossCountrySki
        case .cycling: .roadBike
        case .running: .run
        case .hiking: .hike
        case .climbing: .climbing
        case .crossTraining: .crossfit
        case .swimming: .swim
        case .rowing: .rowing
        case .soccer, .australianFootball, .americanFootball, .rugby: .football
        case .basketball: .basketball
        case .volleyball: .volleyball
        case .tennis, .tableTennis, .badminton: .tennis
        case .pickleball, .racquetball: .padel
        case .squash: .squash
        case .martialArts, .wrestling: .martialArts
        case .boxing, .kickboxing: .boxing
        case .surfingSports, .paddleSports, .sailing: .surf
        case .underwaterDiving: .scubaDiving
        case .skatingSports: .skate
        case .golf: .golf
        case .yoga, .pilates: .yoga
        default: nil
        }
    }

    /// Health workout type for a sport, when written from here.
    static func activityType(for sport: Sport) -> HKWorkoutActivityType {
        switch sport {
        case .climbing: .climbing
        case .snowboard: .snowboarding
        case .ski: .downhillSkiing
        case .crossCountrySki: .crossCountrySkiing
        case .mountainBike, .roadBike: .cycling
        case .run, .trailRun: .running
        case .hike, .mountaineering: .hiking
        case .hyrox, .crossfit: .crossTraining
        case .swim: .swimming
        case .rowing: .rowing
        case .football: .soccer
        case .basketball: .basketball
        case .volleyball: .volleyball
        case .tennis: .tennis
        case .padel: .pickleball
        case .squash: .squash
        case .martialArts: .martialArts
        case .boxing: .boxing
        case .surf: .surfingSports
        case .scubaDiving: .underwaterDiving
        case .skate: .skatingSports
        case .golf: .golf
        case .yoga: .yoga
        case .other: .other
        }
    }

    // MARK: Write

    /// Saves a logged sport session as an Apple Health workout (#416). Returns true when written.
    @discardableResult
    func saveSport(_ log: SportLog, kcal: Double?) async -> Bool {
        guard connected, available, writeWorkouts, log.fromHealth != true else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: log.sport)
        config.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: log.start)
            var samples: [HKSample] = []
            if let kcal {
                samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: log.start, end: log.end))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }
            try await builder.addMetadata([
                Self.sportIdKey: log.id.uuidString,
                "MonkeyWorkoutSport": log.sport.rawValue,
                "MonkeyWorkoutEffort": log.effort,
            ])
            try await builder.endCollection(at: log.end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Removes the Health workout written for a logged sport session, if any.
    func deleteSport(_ id: UUID) async {
        guard connected, available else { return }
        let pred = HKQuery.predicateForObjects(withMetadataKey: Self.sportIdKey, allowedValues: [id.uuidString])
        _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: pred)
    }


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

    /// Wakes the Watch app with a strength workout so it can offer to track the iPhone workout (#347).
    /// `activity`: any other type starts what the iPhone asked: Hyrox (#426) or a sport (#439).
    /// `done` (main actor): whether the Watch app was woken; it fails when the Watch is off the wrist or locked (#462).
    func startWatchApp(activity: HKWorkoutActivityType = .functionalStrengthTraining, done: ((Bool) -> Void)? = nil) {
        guard available else {
            done?(false)
            return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor
        store.startWatchApp(with: config) { ok, _ in
            Task { @MainActor in done?(ok) }
        }
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

    /// Writes a logged measurement (#185) to Apple Health: weight, body fat, lean mass (from both) and waist,
    /// dated like the entry. Other girths have no Health type and stay in the app.
    func saveMeasurement(_ m: BodyMeasurement) async {
        guard connected, available else { return }
        let d = m.date
        var samples: [HKQuantitySample] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
            guard let value else { return }
            samples.append(HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value), start: d, end: d))
        }
        add(.bodyMass, .gramUnit(with: .kilo), m.weightKg)
        add(.bodyFatPercentage, .percent(), m.bodyFatPct.map { $0 / 100 })
        add(.leanBodyMass, .gramUnit(with: .kilo), m.leanKg)
        add(.waistCircumference, .meterUnit(with: .centi), m.girth(.waist))
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Glasses tapped in Fuel (#496), as dietary water. Silent when water sharing wasn't allowed (asked again on the
    /// next connect from Settings).
    func saveWater(ml: Double, at date: Date = Date()) async {
        guard connected, available, ml > 0 else { return }
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                                      start: date, end: date)
        try? await store.save(sample)
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
