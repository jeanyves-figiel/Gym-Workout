import APIClient
import Foundation
import SwiftUI
import WorkoutEngine

/// Train around pain (#870): one spot protected across the whole plan, from the body figure (A) or Ask Coach (B),
/// until the member says it feels better (C). Swaps come from the catalog through the engine, never from the model.
extension AppModel {
    var painProtect: PainProtect? { state.synced?.pain }

    func setPainProtect(_ p: PainProtect?) {
        guard var sp = state.synced, sp.pain != p else { return }
        sp.pain = p
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// The plan with the protected spot's risky moves swapped or removed.
    func painGuarded(_ plan: WeekPlan) -> WeekPlan {
        guard let p = painProtect, let profile else { return plan }
        return p.guarded(plan, profile: profile).plan
    }

    /// What protecting `p` would change in this week's plan (the sheet's and the chat card's list).
    func painPreview(_ p: PainProtect) -> PainProtect.Result? {
        // The plan without the current guard, so a new spot or level previews from scratch.
        guard let base = unguardedPlan(), let profile else { return nil }
        return p.guarded(base, profile: profile)
    }

    /// Swapped items in the plan (uids), marked 🛡.
    var painSwapped: Set<String> {
        // The guard already ran on `plan`: swapped items carry its note.
        guard let p = painProtect, let plan else { return [] }
        return Set(plan.sessions.flatMap { $0.blocks.flatMap(\.items) }.filter { $0.prescription.note == p.swapNote }.map(\.uid))
    }

    /// "Feels better": ends it, with Undo.
    func endPainProtect() {
        guard let p = painProtect else { return }
        setPainProtect(nil)
        UndoCloseCenter.shared.show(UndoOffer(title: "Your \(p.spot) is back in the plan", detail: "Protected for \(p.day()) days",
                                              symbol: "shield.slash.fill", reopen: { .init(EmptyView()) },
                                              revert: { [weak self] in self?.setPainProtect(p) }))
    }
}

extension PainProtect {
    /// Coach's offer (#870); nil when the area or level is unknown to this app version.
    init?(chat p: CoachChatProtect) {
        guard let area = PainArea(rawValue: p.area), let level = PainLevel(rawValue: p.level) else { return nil }
        self.init(area: area, side: PainSide(rawValue: p.side) ?? .both, level: level, seeDoctor: p.seeDoctor)
    }
}
