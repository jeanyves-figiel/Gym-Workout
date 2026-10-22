import Foundation
import WorkoutEngine

/// Life-stage programmes (#625): the check-in, the safety guard on the plan and loads by feel.
extension AppModel {
    /// The life stage of the programme running now (not paused); nil otherwise.
    var lifeStage: LifeStage? {
        guard let a = activeProgramme, !a.paused else { return nil }
        return LifeStage.of(programmeId: a.programmeId)
    }

    var lifeStageCheckIn: LifeStageCheckIn? { state.synced?.lifeStage }

    func setLifeStageCheckIn(_ c: LifeStageCheckIn?) {
        guard var sp = state.synced, sp.lifeStage != c else { return }
        sp.lifeStage = c
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// The plan through the stage's guard (B) and talk-test loads (C) while a life-stage programme runs.
    func lifeGuarded(_ plan: WeekPlan) -> WeekPlan {
        guard let stage = lifeStage else { return plan }
        return stage.guarded(plan, lifeStageCheckIn, now: Date()).plan
    }
}
