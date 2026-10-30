import APIClient
import Foundation
import WorkoutEngine

/// Saved gyms, gym memory and "Not here?" (#162).
extension AppModel {
    /// Gyms the member set up, latest first.
    var savedGyms: [SavedGym] { (state.synced?.savedGyms ?? []).sorted { $0.updated > $1.updated } }

    /// The home gym from the training profile as a saved gym.
    var homeGym: SavedGym {
        let ref = profile?.gym ?? Gym.puls5.ref
        let saved = state.synced?.savedGyms?.first { $0.id == ref.id }
        return SavedGym(ref: ref, kind: saved?.kind, equipment: profile?.equipment ?? Gym.puls5.equipment,
                        unsure: saved?.unsure, updated: saved?.updated ?? Date(), layout: profile?.gymLayout, extras: saved?.extras)
    }

    /// Adds or replaces a saved gym (max 20, oldest dropped) and shares a place's list with gym memory.
    /// A gym saved without zones keeps the ones it had (a redo in swipes, #274) unless `keepLayout` is false.
    func saveGym(_ gym: SavedGym, share: Bool = true, keepLayout: Bool = true) {
        guard state.synced != nil else { return }
        var list = state.synced?.savedGyms ?? []
        var gym = gym
        if keepLayout, gym.layout == nil { gym.layout = list.first { $0.id == gym.id }?.layout }
        // What it also has (#960) is set on Your gym only: a redo of its equipment keeps it.
        if gym.extras == nil { gym.extras = list.first { $0.id == gym.id }?.extras }
        list.removeAll { $0.id == gym.id }
        list.insert(gym, at: 0)
        state.synced?.savedGyms = Array(list.sorted { $0.updated > $1.updated }.prefix(20))
        state.profileDirty = true
        persist()
        Task { await sync() }
        if share { shareGym(gym) }
    }

    func deleteSavedGym(_ id: String) {
        state.synced?.savedGyms?.removeAll { $0.id == id }
        state.profileDirty = true
        persist()
        let api = api
        Task {
            await sync()
            try? await api.deleteGymReport(id: id)
        }
    }

    /// Saves the home gym as edited in Training profile → Your gym, so switching back restores its list.
    func rememberHomeGym() {
        let g = homeGym
        if let saved = state.synced?.savedGyms?.first(where: { $0.id == g.id }), saved.equipment == g.equipment,
           saved.layout == g.layout { return }
        var updated = g
        updated.unsure = g.unsure?.filter { g.equipment.contains($0) }
        updated.updated = Date()
        saveGym(updated, keepLayout: false)
    }

    /// Where the home gym's equipment sits (#274): re-plans so supersets and circuits stay in one zone; nil = off.
    func setGymLayout(_ layout: GymLayout?) {
        guard var p = profile, p.gymLayout != layout else { return }
        p.gymLayout = layout
        updateProfile(p)
        rememberHomeGym()
        shareGymMap(layout)
    }

    /// Machines and zones edited from Explore's gym sheet (#662): re-plans the week like Training profile → Your gym.
    func setGymEquipment(_ equipment: [Equipment], layout: GymLayout?) {
        guard var p = profile, p.equipment != equipment || p.gymLayout != layout else { return }
        p.equipment = equipment
        p.gymLayout = layout
        updateProfile(p)
        rememberHomeGym()
        shareGymMap(layout)
    }

    /// Zones (and ticks) set from the player (#352): saved now, re-planned when the workout ends so the running one
    /// keeps its exercise list.
    func setGymLayoutDuringWorkout(_ layout: GymLayout?, equipment: [Equipment]) {
        guard var p = profile, p.gymLayout != layout || p.equipment != equipment else { return }
        p.gymLayout = layout
        p.equipment = equipment
        state.synced?.profile = p
        rememberHomeGym()
        replanAfterWorkout = true
        shareGymMap(layout)
    }

    // MARK: Gym Map (#406)

    /// The home gym as the server matches it; nil for a custom gym.
    var homePlace: GymPlace? {
        let g = homeGym
        guard g.isPlace else { return nil }
        return GymPlace(id: g.ref.id, name: g.ref.name, latitude: g.ref.latitude, longitude: g.ref.longitude)
    }

    /// Shares a drawn plan with members at the same gym (counts and the plan only, never who).
    private func shareGymMap(_ layout: GymLayout?) {
        guard let layout, layout.hasPlan, let place = homePlace else { return }
        #if DEBUG
        if demo { return }
        #endif
        let api = api
        Task { try? await api.shareGymMap(place, layout: layout) }
    }

    /// Other members' plan for the home gym (shown as "Map ready" when the member has none yet).
    func loadSharedGymMap() async {
        #if DEBUG
        if demo { sharedGymMap = Demo.sharedGymMap; return }
        #endif
        guard let place = homePlace else { sharedGymMap = nil; return }
        sharedGymMap = (try? await api.sharedGymMap(place, as: GymLayout.self)) ?? nil
    }

    /// Live crowd at the home gym (members' "Taken?" taps in the last 20 minutes, rush hours today).
    func refreshGymCrowd() async {
        #if DEBUG
        if demo { gymCrowd = Demo.gymCrowd; return }
        #endif
        guard let place = homePlace else { gymCrowd = nil; return }
        let offset = TimeZone.current.secondsFromGMT() / 60
        if let c = try? await api.gymCrowd(gymId: place.id, utcOffsetMinutes: offset) { gymCrowd = c }
    }

    /// Members who found `zone` busy in the last 20 minutes.
    func busyNow(_ zone: GymLayout.Zone) -> Int { gymCrowd?.reports(zone.name) ?? 0 }

    /// Busy now (members' taps) or usually busy at this time (your own taps).
    func zoneBusy(_ zone: GymLayout.Zone) -> Bool { busyNow(zone) > 0 || usuallyBusy(zone.id) }

    /// Hour today (from now on) with the fewest busy taps across zones, when members' taps give a rush-hour picture.
    func quietestHour(after date: Date = Date()) -> Int? {
        guard let f = gymCrowd?.forecast, f.contains(where: { $0.hours.contains { $0 > 0 } }) else { return nil }
        let from = Calendar.current.component(.hour, from: date)
        let hours = Array(from..<min(24, from + 6))
        return hours.min { a, b in f.reduce(0) { $0 + $1.hours[a] } < f.reduce(0) { $0 + $1.hours[b] } }
    }

    /// Equipment seen on a photo of one area of the gym (Gym scan).
    func scanGym(jpeg: Data) async throws -> [Equipment] {
        #if DEBUG
        if demo { return [.rack, .bench, .dumbbells, .barbell] }
        #endif
        let catalog = Equipment.allCases.map { GymScanItem(id: $0.rawValue, label: $0.label) }
        return try await api.gymScan(jpeg: jpeg, catalog: catalog).items.compactMap(Equipment.init(rawValue:))
    }

    /// Zone of the home gym an exercise is done in (#274); nil without zones, or anywhere (bodyweight, mat…).
    /// Route of a session through the home gym (#406); nil without zones or with fewer than one stop.
    func gymRoute(_ session: Session) -> GymRoute? {
        guard let layout = profile?.gymLayout else { return nil }
        let r = layout.route(session.blocks.flatMap { $0.items.map(\.exerciseId) })
        return r.stops.isEmpty ? nil : r
    }

    /// "Taken?" in the player (#406): remembers the zone was busy now (last 8 weeks kept) and tells members at the
    /// same gym (live crowd).
    func logBusy(_ zone: GymLayout.Zone, at date: Date = Date()) {
        var taps = (state.busyTaps ?? []).filter { date.timeIntervalSince($0.at) <= GymBusy.window }
        taps.append(BusyTap(zoneId: zone.id, at: date))
        state.busyTaps = Array(taps.suffix(300))
        persist()
        #if DEBUG
        if demo { return }
        #endif
        guard let place = homePlace else { return }
        let api = api
        Task { try? await api.reportBusy(gymId: place.id, zone: zone.name) }
    }

    /// Zone usually busy around this time of day (from the member's own "Taken?" taps).
    func usuallyBusy(_ zoneId: String, at date: Date = Date()) -> Bool {
        GymBusy.usuallyBusy(state.busyTaps ?? [], zone: zoneId, at: date)
    }

    func gymZone(_ exerciseId: String) -> GymLayout.Zone? {
        guard let layout = profile?.gymLayout, let e = Exercise.find(exerciseId) else { return nil }
        return layout.zone(of: e)
    }

    /// Training profile → Your gym edit (#271), kept as soon as it's made: the gym and its list from `edited`, the
    /// rest of the profile as it is. Switching gyms keeps the previous one saved with its list (#180); the gym's own
    /// list is kept for switching back later (#162).
    func editGym(_ edited: Profile) {
        guard var p = profile else { return updateProfile(edited) }
        guard p.gym != edited.gym || p.equipment != edited.equipment else { return }
        if (edited.gym ?? Gym.puls5.ref).id != homeGym.id { rememberHomeGym() }
        // Another gym brings its own zones (#274): the ones picked with it, else the ones it was saved with.
        if (edited.gym ?? Gym.puls5.ref).id != (p.gym ?? Gym.puls5.ref).id {
            let id = (edited.gym ?? Gym.puls5.ref).id
            p.gymLayout = edited.gymLayout ?? state.synced?.savedGyms?.first { $0.id == id }?.layout
        }
        p.gym = edited.gym
        p.equipment = edited.equipment
        updateProfile(p)
        rememberHomeGym()
    }

    /// Saved gyms other than the home gym, to switch to in one tap (#180).
    var otherGyms: [SavedGym] { savedGyms.filter { $0.id != homeGym.id } }

    /// Switches the home gym (#180): the current one stays saved with its own list, so switching back restores it.
    func switchGym(to gym: SavedGym) {
        rememberHomeGym()
        useGym(gym)
    }

    /// Makes a saved gym the home gym (re-plans the week for its equipment).
    func useGym(_ gym: SavedGym) {
        guard var p = profile else { return }
        // A redo in swipes has no zones yet: the gym keeps the ones it had (#274).
        let layout = gym.layout ?? state.synced?.savedGyms?.first { $0.id == gym.id }?.layout
        p.gym = gym.ref
        p.equipment = gym.equipment
        p.gymLayout = layout
        saveGym(SavedGym(ref: gym.ref, kind: gym.kind, equipment: gym.equipment, unsure: gym.unsure, layout: layout, extras: gym.extras), share: false)
        updateProfile(p)
    }

    private func shareGym(_ gym: SavedGym) {
        guard gym.isPlace else { return }
        #if DEBUG
        if demo { return }
        #endif
        let api = api
        let place = GymPlace(id: gym.ref.id, name: gym.ref.name, latitude: gym.ref.latitude, longitude: gym.ref.longitude)
        Task { try? await api.reportGym(place, equipment: gym.equipment.map(\.rawValue), unsure: (gym.unsure ?? []).map(\.rawValue)) }
    }

    /// What other members found at this gym (nil offline, for custom gyms, or when nobody did).
    func knownGym(_ ref: GymRef) async -> KnownGym? {
        guard !ref.id.hasPrefix("custom:") else { return nil }
        #if DEBUG
        if demo { return Demo.knownGym }
        #endif
        return try? await api.knownGym(GymPlace(id: ref.id, name: ref.name, latitude: ref.latitude, longitude: ref.longitude))
    }

    // MARK: Not here?

    /// The travel period the session holding `uid` falls in, if any.
    func trip(forItem uid: String) -> AwayPeriod? {
        guard let sessionId = plannedItem(uid: uid)?.sessionId, let weekday = plan?.sessions.first(where: { $0.id == sessionId })?.weekday,
              let p = awayThisWeek(weekday), p.kind == .travel else { return nil }
        return p
    }

    /// Equipment of the gym the session holding `uid` is planned at: the trip's, else the home gym's.
    func gymEquipment(forItem uid: String) -> [Equipment] {
        trip(forItem: uid)?.travelEquipment ?? profile?.equipment ?? []
    }

    /// Name of that gym ("Hotel Adlon", "Fitnesspark Puls 5").
    func gymName(forItem uid: String) -> String {
        trip(forItem: uid)?.title ?? gymName
    }

    /// The member says `items` aren't at this gym: they're removed from it (the trip's list on a travel day, else the
    /// home gym), and every exercise still to do this week at that gym that needs them is swapped for the best
    /// match with what's left. Done sessions stay as they were; next week is generated from the new list.
    func notHere(_ items: [Equipment], uid: String) {
        guard !items.isEmpty, var p = profile else { return }
        let trip = trip(forItem: uid)
        let equipment: [Equipment]
        if var t = trip {
            t.equipment = t.travelEquipment.filter { !items.contains($0) }
            if let i = state.synced?.away?.firstIndex(where: { $0.id == t.id }) { state.synced?.away?[i] = t }
            equipment = t.travelEquipment
            if let ref = t.gym {
                let old = state.synced?.savedGyms?.first { $0.id == ref.id }
                saveGym((old ?? SavedGym(ref: ref, equipment: equipment)).removing(items), share: true)
            }
        } else {
            p.equipment.removeAll { items.contains($0) }
            state.synced?.profile = p
            equipment = p.equipment
            saveGym(homeGym.removing(items))
        }
        p.equipment = equipment
        // Sessions at the same gym: the trip's days, or the days outside any trip.
        let done = doneIds
        let atGym = (plan?.sessions ?? []).filter { s in
            !done.contains(s.id) && s.weekday.flatMap { awayThisWeek($0) }.flatMap { $0.kind == .travel ? $0.id : nil } == trip?.id
        }
        for s in atGym {
            for item in s.blocks.flatMap(\.items) where canSwap(uid: item.uid) {
                let e = Exercise.get(item.exerciseId)
                guard !e.missing(from: equipment).isEmpty else { continue }
                if let to = e.swapOptions(for: p).first(where: { $0.missing(from: equipment).isEmpty }) {
                    swap(uid: item.uid, to: to.id)
                }
            }
        }
        state.profileDirty = true
        persist()
        Task { await sync() }
    }
}
