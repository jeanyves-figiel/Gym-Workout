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
                        unsure: saved?.unsure, updated: saved?.updated ?? Date())
    }

    /// Adds or replaces a saved gym (max 20, oldest dropped) and shares a place's list with gym memory.
    func saveGym(_ gym: SavedGym, share: Bool = true) {
        guard state.synced != nil else { return }
        var list = state.synced?.savedGyms ?? []
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
        if let saved = state.synced?.savedGyms?.first(where: { $0.id == g.id }), saved.equipment == g.equipment { return }
        var updated = g
        updated.unsure = g.unsure?.filter { g.equipment.contains($0) }
        updated.updated = Date()
        saveGym(updated)
    }

    /// Training profile → Your gym edit (#271), kept as soon as it's made: the gym and its list from `edited`, the
    /// rest of the profile as it is. Switching gyms keeps the previous one saved with its list (#180); the gym's own
    /// list is kept for switching back later (#162).
    func editGym(_ edited: Profile) {
        guard var p = profile else { return updateProfile(edited) }
        guard p.gym != edited.gym || p.equipment != edited.equipment else { return }
        if (edited.gym ?? Gym.puls5.ref).id != homeGym.id { rememberHomeGym() }
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
        p.gym = gym.ref
        p.equipment = gym.equipment
        saveGym(SavedGym(ref: gym.ref, kind: gym.kind, equipment: gym.equipment, unsure: gym.unsure), share: false)
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
