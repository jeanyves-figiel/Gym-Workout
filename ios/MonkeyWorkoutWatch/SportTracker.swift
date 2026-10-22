import AVFoundation
import CoreLocation
import Foundation
import HealthKit
import LiftSensor
import Observation
import WatchKit

/// Sports the Watch tracks (#418, design B + C); Hyrox has its own race mode (`HyroxTracker`, #426). Raw values match the iPhone's `Sport`, so the session page and the
/// plan read the exact sport from the workout's metadata. Diving is left to dive apps (user, 2026-10-17).
enum TrackedSport: String, CaseIterable, Identifiable {
    case snowboard, ski, crossCountrySki, mountainBike, roadBike, run, trailRun, hike, mountaineering
    case crossfit, rowing, football, tennis, padel, golf, surf, skate, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .snowboard: "Snowboard"
        case .ski: "Ski"
        case .crossCountrySki: "XC ski"
        case .mountainBike: "MTB"
        case .roadBike: "Road bike"
        case .run: "Run"
        case .trailRun: "Trail run"
        case .hike: "Hike"
        case .mountaineering: "Mountaineering"
        case .crossfit: "CrossFit"
        case .rowing: "Rowing"
        case .football: "Football"
        case .tennis: "Tennis"
        case .padel: "Padel"
        case .golf: "Golf"
        case .surf: "Surf"
        case .skate: "Skate"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .snowboard: "figure.snowboarding"
        case .ski: "figure.skiing.downhill"
        case .crossCountrySki: "figure.skiing.crosscountry"
        case .mountainBike: "figure.outdoor.cycle"
        case .roadBike: "bicycle"
        case .run, .trailRun: "figure.run"
        case .hike: "figure.hiking"
        case .mountaineering: "mountain.2.fill"
        case .crossfit: "figure.highintensity.intervaltraining"
        case .rowing: "figure.rower"
        case .football: "figure.soccer"
        case .tennis: "figure.tennis"
        case .padel: "figure.racquetball"
        case .golf: "figure.golf"
        case .surf: "figure.surfing"
        case .skate: "figure.skating"
        case .other: "figure.mixed.cardio"
        }
    }

    var tint: (UInt32, UInt32) {
        switch self {
        case .snowboard, .ski, .crossCountrySki: (0x00A3C4, 0x7DF9FF)
        case .mountainBike, .hike, .trailRun, .mountaineering: (0x00B86B, 0x7DFFB0)
        case .crossfit: (0xFF3D8B, 0xFF9A5E)
        case .roadBike, .run, .rowing: (0x3D59FF, 0x00C7FF)
        default: (0x7D4DFF, 0xE040FB)
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .snowboard: .snowboarding
        case .ski: .downhillSkiing
        case .crossCountrySki: .crossCountrySkiing
        case .mountainBike, .roadBike: .cycling
        case .run, .trailRun: .running
        case .hike, .mountaineering: .hiking
        case .crossfit: .crossTraining
        case .rowing: .rowing
        case .football: .soccer
        case .tennis: .tennis
        case .padel: .pickleball
        case .golf: .golf
        case .surf: .surfingSports
        case .skate: .skatingSports
        case .other: .other
        }
    }

    /// Bike rides use Bluetooth power, cadence and heart-rate sensors (#623).
    var bike: Bool { self == .roadBike || self == .mountainBike }

    /// GPS is worth its battery: outdoor sports that move.
    var usesGPS: Bool { ![TrackedSport.crossfit, .rowing, .tennis, .padel, .football].contains(self) }
    /// Downhill: runs split at lifts, vertical counted down.
    var downhill: Bool { self == .snowboard || self == .ski }
    /// Laps or stations with a big LAP button.
    var laps: Bool { [TrackedSport.crossfit, .run, .rowing].contains(self) }
    /// Compass page with waypoints (#617).
    var compass: Bool { [TrackedSport.hike, .mountaineering, .trailRun].contains(self) }
    /// Swing counter (#611 B): shoulder to racket or club head, metres; nil = not a swing sport.
    var swingLever: Double? {
        switch self {
        case .tennis, .padel: 1.2
        case .golf: 1.6
        default: nil
        }
    }

    var locationActivity: CLActivityType {
        switch self {
        case .mountainBike, .roadBike: .otherNavigation
        case .snowboard, .ski: .otherNavigation
        default: .fitness
        }
    }

}

/// Battery mode picked before the start (design C).
enum TrackPower: String, CaseIterable, Identifiable {
    /// GPS every few metres: best map and speed.
    case full
    /// GPS fix about once a minute, coarse accuracy: long days on one charge.
    case saver

    var id: String { rawValue }
    var label: String { self == .full ? "Full" : "Saver" }
    var detail: String { self == .full ? "GPS every few m · ~6 h" : "GPS once a min · ~14 h" }
}

/// A sport session on the Watch (#418): system workout session in the background (HR, energy, motion from watchOS),
/// GPS route batched into Apple Health, live speed / distance / vertical / runs, laps as workout segments.
/// Battery: no timers except the 1-minute fix in Saver, GPS filtered per sport, nothing sent live to the iPhone.
@MainActor @Observable
final class SportTracker: NSObject {
    static let shared = SportTracker()

    private(set) var sport: TrackedSport?
    private(set) var power: TrackPower = .full
    private(set) var started: Date?
    private(set) var paused = false
    var heartRate: Double?
    private(set) var maxHeartRate: Double?
    private(set) var kcal: Double = 0
    /// km/h, smoothed over the last fixes.
    private(set) var speed: Double = 0
    private(set) var topSpeed: Double = 0
    private(set) var meters: Double = 0
    private(set) var up: Double = 0
    private(set) var down: Double = 0
    private(set) var altitude: Double?
    private(set) var highest: Double?
    private(set) var runs = 0
    /// Breadcrumb for the live map (#445 C), thinned to stay under `trailMax` points.
    private(set) var trail: [CLLocationCoordinate2D] = []
    /// Metres and compass bearing (degrees) back to where tracking started; direction of travel when moving.
    private(set) var homeMeters: Double?
    private(set) var homeBearing: Double?
    private(set) var course: Double?
    /// Compass (#617, hike / mountaineering / trail run): heading in degrees while the compass page is on screen,
    /// waypoints marked on the way and the one the arrow points to.
    private(set) var heading: Double?
    private(set) var waypoints: [Waypoint] = []
    private(set) var target: Int?

    struct Waypoint: Identifiable {
        let id: Int
        let name: String
        let coordinate: CLLocationCoordinate2D
    }
    /// Ski / snowboard live state: on a lift (climbing) or riding, time in each, the last finished run.
    private(set) var onLift = false
    private(set) var rideSeconds: TimeInterval = 0
    private(set) var liftSeconds: TimeInterval = 0
    private(set) var lastRun: (drop: Double, topKmh: Double)?
    /// Lap / station index (0-based) and when it started.
    private(set) var lap = 0
    private(set) var lapStart: Date?
    private(set) var lastLapMinutes: Double?
    /// Battery % at start and at finish (summary).
    private(set) var batteryStart: Float?
    private(set) var summary: Summary?
    /// Planned run (#618, design B): its steps as big blocks, pace target vs actual, voice cues.
    private(set) var run: WRun?
    private(set) var stepIndex = 0
    private(set) var stepStart: Date?
    private var stepMeters0: Double = 0
    private var runTimer: Timer?
    private let voice = AVSpeechSynthesizer()

    struct Summary {
        let sport: TrackedSport
        let minutes: Int
        let km: Double
        let vertical: Double
        let runs: Int
        let topKmh: Double
        let batteryUsed: Int?
        var trail: [CLLocationCoordinate2D] = []
        var rideSeconds: TimeInterval = 0
        var liftSeconds: TimeInterval = 0
        /// Swing sports (#611 B): forehand, backhand, smash counts and the fastest swing (km/h).
        var swings: [SwingCounter.Shot: Int] = [:]
        var topSwing: Double = 0
    }

    var running: Bool { sport != nil }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let location = CLLocationManager()
    private var pending: [CLLocation] = []
    private var last: CLLocation?
    private var altRef: Double?
    private var runTop: Double?
    private var runLow: Double?
    private var runTopSpeed: Double = 0
    private var home: CLLocation?
    private var saverTimer: Timer?
    private let trailMax = 400
    /// Swings counted from the batched sensors (#611 B).
    let impacts = ImpactTracker()

    func start(_ sport: TrackedSport, power: TrackPower, run: WRun? = nil, target: Int? = nil) async {
        guard HKHealthStore.isHealthDataAvailable(), !running, !WorkoutManager.shared.running, !HyroxTracker.shared.running,
              !WodTracker.shared.running, !SwimTracker.shared.running else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
        let config = HKWorkoutConfiguration()
        config.activityType = sport.activityType
        config.locationType = sport.usesGPS ? .outdoor : .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        reset()
        self.sport = sport
        self.power = power
        self.run = run
        await prepareZones(b, target: run?.steps.first?.zone ?? run?.zone ?? target)
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        batteryStart = WKInterfaceDevice.current().batteryLevel >= 0 ? WKInterfaceDevice.current().batteryLevel : nil
        let now = Date()
        started = now
        lapStart = now
        stepStart = run == nil ? nil : now
        s.startActivity(with: now)
        do {
            try await b.beginCollection(at: now)
            try? await b.addMetadata(["MonkeyWorkoutSport": sport.rawValue, "MonkeyWorkoutPower": power.rawValue])
        } catch {
            discard()
            return
        }
        if sport.usesGPS { startLocation() }
        if run != nil { startRun() }
        // Batched sensors only run inside the workout session.
        if let lever = sport.swingLever { impacts.startSwings(lever: lever) }
        if sport.bike { BikeSensors.shared.connect() }
    }

    private func reset() {
        summary = nil
        paused = false
        heartRate = nil
        maxHeartRate = nil
        kcal = 0
        speed = 0
        topSpeed = 0
        meters = 0
        up = 0
        down = 0
        altitude = nil
        highest = nil
        runs = 0
        lap = 0
        lastLapMinutes = nil
        pending = []
        last = nil
        altRef = nil
        runTop = nil
        runLow = nil
        runTopSpeed = 0
        trail = []
        home = nil
        homeMeters = nil
        homeBearing = nil
        course = nil
        heading = nil
        waypoints = []
        target = nil
        onLift = false
        rideSeconds = 0
        liftSeconds = 0
        lastRun = nil
        run = nil
        stepIndex = 0
        stepStart = nil
        stepMeters0 = 0
        runTimer?.invalidate()
        runTimer = nil
    }

    // MARK: Run player (#618)

    var step: WRunStep? { run.flatMap { stepIndex < $0.steps.count ? $0.steps[stepIndex] : nil } }
    var nextUp: WRunStep? { run.flatMap { stepIndex + 1 < $0.steps.count ? $0.steps[stepIndex + 1] : nil } }
    var stepMeters: Double { meters - stepMeters0 }

    /// Metres or seconds left in the step.
    func stepLeft(now: Date) -> (meters: Int?, seconds: Int?) {
        guard let step else { return (nil, nil) }
        if let m = step.meters { return (max(0, m - Int(stepMeters)), nil) }
        if let sec = step.seconds { return (nil, max(0, sec - Int(now.timeIntervalSince(stepStart ?? now)))) }
        return (nil, nil)
    }

    /// Live pace, seconds per km; nil when standing.
    var pace: Int? { speed > 2 ? Int(3600 / speed) : nil }

    private func startRun() {
        cue()
        runTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStep() }
        }
    }

    /// Next step when its distance or time is done; the last one ends the plan (tracking carries on until End).
    private func checkStep(now: Date = Date()) {
        guard !paused, let step else { return }
        let left = stepLeft(now: now)
        if (step.meters != nil && left.meters == 0) || (step.meters == nil && left.seconds == 0) { nextStep(now: now) }
    }

    /// Skip or step done: segment in Health, buzz, voice cue, the new step's target zone.
    func nextStep(now: Date = Date()) {
        guard let run, stepIndex < run.steps.count else { return }
        if let s = stepStart, let builder {
            let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: s, end: now), metadata: nil)
            Task { try? await builder.addWorkoutEvents([event]) }
        }
        stepIndex += 1
        stepStart = now
        stepMeters0 = meters
        WKInterfaceDevice.current().play(stepIndex < run.steps.count ? .notification : .success)
        if stepIndex >= run.steps.count {
            runTimer?.invalidate()
            runTimer = nil
            ZoneTracker.shared.target = run.zone
            speak("Plan done. Great work.")
            return
        }
        ZoneTracker.shared.target = step?.zone ?? run.zone
        cue()
    }

    /// Coach voice cue: "Rep 3 of 6. 400 metres at 4:30 a kilometre."
    private func cue() {
        guard let step else { return }
        var parts = [step.title]
        if let m = step.meters { parts.append(m >= 1000 && m % 1000 == 0 ? "\(m / 1000) kilometres" : "\(m) metres") }
        else if let sec = step.seconds { parts.append(sec >= 60 ? "\(sec / 60) minutes" : "\(sec) seconds") }
        if let p = step.pace { parts.append("at \(p / 60) \(String(format: "%02d", p % 60)) a kilometre") }
        else if let z = step.zone { parts.append("in zone \(z)") }
        speak(parts.joined(separator: ". "))
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        voice.speak(u)
    }

    private func startLocation() {
        guard let sport else { return }
        // One route per session: resume keeps adding to the same builder.
        if routeBuilder == nil { routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil) }
        location.delegate = self
        location.activityType = sport.locationActivity
        location.requestWhenInUseAuthorization()
        if power == .full {
            location.desiredAccuracy = kCLLocationAccuracyBest
            // Fast sports need fewer points per metre.
            location.distanceFilter = sport.downhill || sport == .roadBike ? 15 : 8
            location.startUpdatingLocation()
        } else {
            location.desiredAccuracy = kCLLocationAccuracyHundredMeters
            location.requestLocation()
            saverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.location.requestLocation() }
            }
        }
    }

    private func stopLocation() {
        saverTimer?.invalidate()
        saverTimer = nil
        location.stopUpdatingLocation()
    }

    func pause() {
        session?.pause()
        paused = true
        stopLocation()
    }

    func resume() {
        session?.resume()
        paused = false
        if sport?.usesGPS == true { startLocation() }
    }

    /// LAP: closes the current lap / station as a workout segment (the iPhone shows them as splits).
    func markLap() {
        guard let builder, let s = lapStart else { return }
        let now = Date()
        let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: s, end: now), metadata: nil)
        Task { try? await builder.addWorkoutEvents([event]) }
        lastLapMinutes = now.timeIntervalSince(s) / 60
        lap += 1
        lapStart = now
        WKInterfaceDevice.current().play(.click)
    }


    func finish() async {
        guard let session, let builder, let sport else { discard(); return }
        stopLocation()
        flushRoute()
        impacts.stop()
        session.end()
        let end = Date()
        let used = batteryStart.map { start -> Int in
            let now = WKInterfaceDevice.current().batteryLevel
            return now >= 0 ? max(0, Int(((start - now) * 100).rounded())) : 0
        }
        summary = Summary(sport: sport, minutes: Int(end.timeIntervalSince(started ?? end) / 60), km: meters / 1000,
                          vertical: sport.downhill ? down : up, runs: runs, topKmh: topSpeed, batteryUsed: used,
                          trail: trail, rideSeconds: rideSeconds, liftSeconds: liftSeconds,
                          swings: sport.swingLever == nil ? [:] : impacts.swings.counts, topSwing: impacts.swings.top)
        do {
            var meta: [String: Any] = [HKMetadataKeyIndoorWorkout: !sport.usesGPS]
            if sport.swingLever != nil, impacts.swings.total > 0 {
                meta["MonkeyWorkoutSwings"] = SwingCounter.Shot.allCases.map { "\($0.short) \(impacts.swings.counts[$0] ?? 0)" }.joined(separator: " · ")
            }
            if up > 0 { meta[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: up) }
            try? await builder.addMetadata(meta)
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout(), let routeBuilder {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {}
        cleanup()
    }

    func discard() {
        stopLocation()
        impacts.stop()
        session?.end()
        builder?.discardWorkout()
        routeBuilder?.discard()
        cleanup()
    }

    func closeSummary() { summary = nil }

    // MARK: Compass (#617)

    /// Only while the compass page shows: the magnetometer costs battery.
    func startHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        location.delegate = self
        location.headingFilter = 3
        location.startUpdatingHeading()
    }

    func stopHeading() {
        location.stopUpdatingHeading()
        heading = nil
    }

    /// Drops a waypoint where you are; the arrow points to it from now on.
    func markWaypoint() {
        guard let here = last else { return }
        let n = waypoints.count + 1
        waypoints.append(Waypoint(id: n, name: "WP \(n)", coordinate: here.coordinate))
        target = waypoints.count - 1
        WKInterfaceDevice.current().play(.success)
    }

    /// Next waypoint for the arrow, round the list.
    func nextTarget() {
        guard !waypoints.isEmpty else { return }
        target = ((target ?? -1) + 1) % waypoints.count
        WKInterfaceDevice.current().play(.click)
    }

    /// Metres and bearing (degrees from north) from here to a point.
    func toward(_ c: CLLocationCoordinate2D) -> (meters: Double, bearing: Double)? {
        guard let here = last else { return nil }
        let rad = Double.pi / 180
        let lat1 = here.coordinate.latitude * rad, lat2 = c.latitude * rad
        let dLon = (c.longitude - here.coordinate.longitude) * rad
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let meters = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return (meters, (atan2(y, x) / rad + 360).truncatingRemainder(dividingBy: 360))
    }

    fileprivate func setHeading(_ v: Double) {
        if v >= 0 { heading = v }
    }
    #if DEBUG
    /// CI screenshots: a padel match with its swing counts (#611 B).
    func demo(_ sport: TrackedSport, minutes: Double) {
        self.sport = sport
        started = Date().addingTimeInterval(-minutes * 60)
        heartRate = 142
        impacts.demo(swings: 148, 96, 22, top: 71)
    }
    #endif

    private func cleanup() {
        runTimer?.invalidate()
        runTimer = nil
        run = nil
        if sport?.bike == true { BikeSensors.shared.disconnect() }
        session = nil
        builder = nil
        routeBuilder = nil
        sport = nil
        paused = false
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
    }

    /// Route points go to Health in batches of 30, never one by one.
    private func flushRoute() {
        guard !pending.isEmpty, let routeBuilder else { return }
        let batch = pending
        pending = []
        Task { try? await routeBuilder.insertRouteData(batch) }
    }

    fileprivate func add(_ locations: [CLLocation]) {
        guard !paused, let sport else { return }
        for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy <= (power == .full ? 50 : 200) {
            if let prev = last {
                let d = l.distance(from: prev)
                let dt = l.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { continue }
                meters += d
                let kmh = (l.speed >= 0 ? l.speed : d / dt) * 3.6
                // Smoothed live speed; top speed only from a believable fix.
                speed = speed * 0.5 + kmh * 0.5
                if l.horizontalAccuracy <= 20, kmh < 150 {
                    topSpeed = max(topSpeed, speed)
                    runTopSpeed = max(runTopSpeed, speed)
                }
                // Gaps (Saver, tunnels) longer than 2 minutes count for neither.
                if sport.downhill && dt < 120 {
                    if onLift { liftSeconds += dt } else { rideSeconds += dt }
                }
            }
            last = l
            pending.append(l)
            breadcrumb(l)
            if l.verticalAccuracy >= 0 { climb(l.altitude, downhill: sport.downhill) }
        }
        if pending.count >= 30 { flushRoute() }
        if run != nil { checkStep() }
    }

    /// Live map (#445 C): trail, distance and bearing home, direction of travel. Halves the trail when full.
    private func breadcrumb(_ l: CLLocation) {
        trail.append(l.coordinate)
        if trail.count > trailMax { trail = trail.enumerated().filter { $0.offset % 2 == 0 || $0.offset == trail.count - 1 }.map(\.element) }
        if l.course >= 0 && l.speed > 0.5 { course = l.course }
        guard let home else { home = l; return }
        homeMeters = l.distance(from: home)
        let rad = Double.pi / 180
        let lat1 = l.coordinate.latitude * rad, lat2 = home.coordinate.latitude * rad
        let dLon = (home.coordinate.longitude - l.coordinate.longitude) * rad
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        homeBearing = (atan2(y, x) / rad + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Vertical up/down ignoring < 3 m wobble; a downhill run counts once it dropped 40 m and the lift climbs 25 m.
    private func climb(_ alt: Double, downhill: Bool) {
        altitude = alt
        highest = max(highest ?? alt, alt)
        guard let ref = altRef else { altRef = alt; runTop = alt; runLow = alt; return }
        let d = alt - ref
        if abs(d) >= 3 {
            if d > 0 { up += d } else { down -= d }
            altRef = alt
        }
        guard downhill, let top = runTop, let low = runLow else { return }
        if alt < low { runLow = alt }
        if alt - (runLow ?? alt) >= 25 {
            if top - (runLow ?? top) >= 40 {
                runs += 1
                lastRun = (top - (runLow ?? top), runTopSpeed)
                WKInterfaceDevice.current().play(.click)
            }
            onLift = true
            runTop = alt
            runLow = alt
        } else if onLift && alt < top - 15 {
            // Going down again: a new run.
            onLift = false
            runTopSpeed = 0
        } else if alt > top && runLow == top {
            runTop = alt
            runLow = alt
        }
    }

    fileprivate func update(_ stats: HKStatistics) {
        switch stats.quantityType {
        case HKQuantityType(.heartRate):
            guard let v = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
            heartRate = v
            maxHeartRate = max(maxHeartRate ?? 0, v)
            ZoneTracker.shared.heart(v)
        case HKQuantityType(.activeEnergyBurned):
            kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? kcal
        default:
            break
        }
    }
}

extension SportTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.add(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let v = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.setHeading(v) }
    }
}

extension SportTracker: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension SportTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    /// watchOS 27: Apple's zone changed (#609).
    @available(watchOS 27, *)
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutZoneUpdate) {
        guard let p = AppleZones.position(zoneUpdate) else { return }
        Task { @MainActor in ZoneTracker.shared.apple(p.zone, count: p.count) }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}
