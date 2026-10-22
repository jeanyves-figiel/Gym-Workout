import Foundation
import WorkoutEngine

/// Calisthenics skill tree (#621).
extension AppModel {
    var skills: SkillProgress { state.synced?.skills ?? SkillProgress() }

    private func saveSkills(_ s: SkillProgress) {
        guard var sp = state.synced, sp.skills != s else { return }
        sp.skills = s
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Records a level test (B); returns the node it unlocked.
    @discardableResult
    func recordSkillTest(_ node: Skills.Node, result: Int) -> Skills.Node? {
        var s = skills
        let unlocked = s.record(node, result: result)
        saveSkills(s)
        return unlocked
    }

    /// Skill of the month (C); nil stops it.
    func setSkillOfMonth(_ node: Skills.Node?) {
        var s = skills
        s.focus = node?.exerciseId
        s.focusMonth = node.map { _ in Skills.monthKey(Date(), planCalendar) }
        saveSkills(s)
    }

    var skillOfMonth: Skills.Node? { skills.focusNode(now: Date(), calendar: planCalendar) }

    /// Days this month with a finished skill practice, and the month's goal (its Mon/Wed/Fri count).
    var skillPracticeDays: (done: Int, goal: Int) {
        let cal = planCalendar
        let month = Skills.monthKey(Date(), cal)
        let days = Set(state.history.filter { Skills.isPractice($0.sessionId) && Skills.monthKey($0.startedAt, cal) == month }
            .map { cal.startOfDay(for: $0.startedAt) })
        return (days.count, Skills.practiceGoal(month: month, calendar: cal))
    }
}
