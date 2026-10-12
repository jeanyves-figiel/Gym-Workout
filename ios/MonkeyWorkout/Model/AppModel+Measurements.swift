import APIClient
import Foundation
import WorkoutEngine

/// Body measurements (#185): dated girths, weight and body fat, stored locally with an offline queue and synced.
extension AppModel {
    /// Oldest first.
    var measurements: [BodyMeasurement] { (state.measurements ?? []).sorted { $0.date < $1.date } }

    /// Values of one metric over time, oldest first, with Apple Health samples for weight, body fat and waist.
    func measurementSeries(_ metric: BodyMetric) -> [BodyMeasurements.Point] {
        BodyMeasurements.series(metric, in: measurements, extra: healthPoints(metric))
    }

    private func healthPoints(_ metric: BodyMetric) -> [BodyMeasurements.Point] {
        guard let snap = health?.snapshot else { return [] }
        let trend: [HealthSnapshot.TrendPoint] = switch metric {
        case .weight: snap.weightTrend
        case .bodyFat: snap.bodyFatTrend
        case .leanMass: snap.leanTrend
        case .girth(.waist): snap.waistTrend
        default: []
        }
        return trend.map { .init(date: $0.date, value: $0.value) }
    }

    /// Adds or replaces an entry; an entry emptied while editing is deleted.
    func saveMeasurement(_ m: BodyMeasurement) {
        guard !m.isEmpty else { return deleteMeasurement(m.id) }
        var list = state.measurements ?? []
        list.removeAll { $0.id == m.id }
        list.append(m)
        state.measurements = list
        var pending = state.pendingMeasurementIds ?? []
        pending.insert(m.id)
        state.pendingMeasurementIds = pending
        persist()
        Task { await sync() }
    }

    func deleteMeasurement(_ id: UUID) {
        state.measurements?.removeAll { $0.id == id }
        state.pendingMeasurementIds?.remove(id)
        var deleted = state.deletedMeasurementIds ?? []
        deleted.insert(id)
        state.deletedMeasurementIds = deleted
        persist()
        Task { await sync() }
    }

    /// Pushes queued deletes and new entries, then pulls the full list. Called from `sync()`.
    func syncMeasurements() async throws {
        for id in state.deletedMeasurementIds ?? [] {
            try await api.deleteBodyMeasurement(id)
            state.deletedMeasurementIds?.remove(id)
        }
        let pendingIds = state.pendingMeasurementIds ?? []
        let pending = (state.measurements ?? []).filter { pendingIds.contains($0.id) }
        if !pending.isEmpty {
            try await api.pushBodyMeasurements(pending)
            state.pendingMeasurementIds?.subtract(pending.map(\.id))
        }
        let remote = try await api.fetchBodyMeasurements(BodyMeasurement.self)
        let stillPending = state.pendingMeasurementIds ?? []
        let deleted = state.deletedMeasurementIds ?? []
        var merged = remote.filter { !stillPending.contains($0.id) && !deleted.contains($0.id) }
        merged += (state.measurements ?? []).filter { stillPending.contains($0.id) }
        var seen = Set<UUID>()
        state.measurements = merged.filter { seen.insert($0.id).inserted }
    }
}
