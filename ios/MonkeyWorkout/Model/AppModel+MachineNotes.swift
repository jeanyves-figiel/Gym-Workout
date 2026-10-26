import APIClient
import Foundation
import WorkoutEngine

/// Machine setup notes (#355): per gym and exercise, synced like climbs; photos uploaded once the note is on the server.
extension AppModel {
    var machineNotes: [MachineNote] { state.machineNotes ?? [] }

    /// The gym the planned item is done at: the trip's (its gym, else the trip itself), else the home gym.
    func gymRef(forItem uid: String?) -> GymRef {
        if let uid, let t = trip(forItem: uid) {
            return t.gym ?? GymRef(id: "trip:\(t.id.uuidString.lowercased())", name: t.title, address: "")
        }
        return homeGym.ref
    }

    func machineNote(exerciseId: String, gymId: String) -> MachineNote? {
        machineNotes.first { $0.exerciseId == exerciseId && $0.gymId == gymId }
    }

    /// Notes for this exercise or its machine, at every gym: this exercise first, then other exercises on the machine.
    func machineNotes(for exercise: Exercise) -> [MachineNote] {
        let machine = exercise.equipment.first?.rawValue
        return machineNotes
            .filter { $0.exerciseId == exercise.id || (machine != nil && $0.equipment == machine) }
            .sorted { ($0.exerciseId == exercise.id ? 0 : 1, $0.gymName) < ($1.exerciseId == exercise.id ? 0 : 1, $1.gymName) }
    }

    /// Saves the note; `photo` nil leaves the photo as is, `.some(nil)` removes it.
    func saveMachineNote(_ note: MachineNote, photo: Data?? = .none) {
        var note = note.cleaned
        if case let .some(newPhoto) = photo {
            if let newPhoto { MachineNotePhotos.save(newPhoto, for: note.id) } else { MachineNotePhotos.remove(note.id) }
            note.photoId = nil
            state.pendingMachinePhotoIds = (state.pendingMachinePhotoIds ?? []).union([note.id])
        }
        var list = state.machineNotes ?? []
        let serverPhoto = photo == nil && list.first { $0.id == note.id }?.photoId != nil
        if note.isEmpty && !serverPhoto && MachineNotePhotos.load(note.id) == nil { return deleteMachineNote(note.id) }
        if let i = list.firstIndex(where: { $0.id == note.id }) {
            if photo == nil { note.photoId = list[i].photoId }
            list[i] = note
        } else {
            list.append(note)
        }
        state.machineNotes = list
        state.pendingMachineNoteIds = (state.pendingMachineNoteIds ?? []).union([note.id])
        persist()
        Task { await sync() }
    }

    func deleteMachineNote(_ id: UUID) {
        state.machineNotes?.removeAll { $0.id == id }
        state.pendingMachineNoteIds?.remove(id)
        state.pendingMachinePhotoIds?.remove(id)
        state.deletedMachineNoteIds = (state.deletedMachineNoteIds ?? []).union([id])
        MachineNotePhotos.remove(id)
        persist()
        Task { await sync() }
    }

    /// Copies a setup from another gym to `gym` (same machine elsewhere), photo included.
    @discardableResult
    func copyMachineNote(_ source: MachineNote, to gym: GymRef, exerciseId: String) async -> MachineNote {
        let photo = await machineNotePhoto(source)
        var copy = machineNote(exerciseId: exerciseId, gymId: gym.id) ?? MachineNote(gymId: gym.id, gymName: gym.name, exerciseId: exerciseId)
        copy.fields = source.fields.map { .init(label: $0.label, value: $0.value) }
        copy.text = source.text
        copy.splitLoad = source.splitLoad
        copy.equipment = source.equipment ?? Exercise.find(exerciseId)?.equipment.first?.rawValue
        saveMachineNote(copy, photo: photo.map { Optional($0) })
        return copy
    }

    /// The note's photo: local file, else downloaded from the server and kept.
    func machineNotePhoto(_ note: MachineNote) async -> Data? {
        if let d = MachineNotePhotos.load(note.id) { return d }
        guard let photoId = note.photoId, !demo, let data = try? await api.machineNotePhoto(photoId) else { return nil }
        MachineNotePhotos.save(data, for: note.id)
        return data
    }

    func syncMachineNotes() async throws {
        let epoch = accountEpoch
        for id in state.deletedMachineNoteIds ?? [] {
            do {
                try await api.deleteMachineNote(id)
            } catch let APIError.server(status, _, _) where status == 404 {
                // Already gone.
            }
            state.deletedMachineNoteIds?.remove(id)
        }
        let pendingIds = state.pendingMachineNoteIds ?? []
        let pending = (state.machineNotes ?? []).filter { pendingIds.contains($0.id) }
        if !pending.isEmpty {
            let result = try await api.pushMachineNotes(pending)
            // Only clear what is unchanged since the push started (an edit made meanwhile stays queued).
            for n in pending where state.machineNotes?.first(where: { $0.id == n.id }) == n { state.pendingMachineNoteIds?.remove(n.id) }
            // Changed on another device since this edit's base: the server copy wins. Written ones keep their new version.
            if accountEpoch == epoch, !result.isEmpty {
                // Its photo changed there too: drop the stale local file (downloaded again when shown), unless a new
                // photo from this device is still waiting to go up.
                let photosQueued = state.pendingMachinePhotoIds ?? []
                for n in result.conflicts where !photosQueued.contains(n.id) && state.machineNotes?.first(where: { $0.id == n.id })?.photoId != n.photoId {
                    MachineNotePhotos.remove(n.id)
                }
                let applied = result.applied(to: state.machineNotes ?? [], pending: state.pendingMachineNoteIds ?? [])
                state.machineNotes = applied.list
                state.pendingMachineNoteIds = applied.pending
            }
        }
        // Photos once their note is on the server.
        for id in state.pendingMachinePhotoIds ?? [] where !(state.pendingMachineNoteIds ?? []).contains(id) {
            guard state.machineNotes?.contains(where: { $0.id == id }) == true else {
                state.pendingMachinePhotoIds?.remove(id)
                continue
            }
            let jpeg = MachineNotePhotos.load(id)
            var photoId: String?
            if let jpeg {
                photoId = try await api.uploadMachineNotePhoto(noteId: id, jpeg: jpeg)
            } else {
                try await api.deleteMachineNotePhoto(noteId: id)
            }
            // The photo changed during the upload: keep it queued for the next sync.
            guard MachineNotePhotos.load(id) == jpeg else { continue }
            // Look the note up again: the list may have changed during the upload (deleted, reordered).
            if let i = state.machineNotes?.firstIndex(where: { $0.id == id }) { state.machineNotes?[i].photoId = photoId }
            state.pendingMachinePhotoIds?.remove(id)
        }
        let remote = try await api.fetchMachineNotes(MachineNote.self)
        // Signed out or another account signed in meanwhile: the list belongs to the previous account.
        guard accountEpoch == epoch else { return }
        let stillPending = (state.pendingMachineNoteIds ?? []).union(state.pendingMachinePhotoIds ?? [])
        let deleted = state.deletedMachineNoteIds ?? []
        let local = Dictionary((state.machineNotes ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var merged = remote.filter { !stillPending.contains($0.id) && !deleted.contains($0.id) }
        // Another device changed the photo: drop the stale local copy (downloaded again when shown).
        for n in merged where local[n.id]?.photoId != n.photoId { MachineNotePhotos.remove(n.id) }
        merged += (state.machineNotes ?? []).filter { stillPending.contains($0.id) }
        var seen = Set<UUID>()
        state.machineNotes = merged.filter { seen.insert($0.id).inserted }
        for gone in local.keys where !seen.contains(gone) { MachineNotePhotos.remove(gone) }
    }
}
