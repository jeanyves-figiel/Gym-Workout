import Foundation

/// Wrist Coach (#608, design C): during the rest the Watch looks at the sets just logged and answers the question you'd
/// ask ("Too heavy?") with one tap to apply. Rules on the Watch itself: instant, no iPhone, no signal needed.
enum WristCoach {
    struct Advice: Equatable {
        let question: String
        let answer: String
        /// Weight for the remaining sets; nil when the advice isn't a weight change.
        let kg: Double?
    }

    /// `rows`: the exercise's sets; `done`: sets finished. Nil when there's nothing worth saying or no set left.
    static func advice(rows: [WatchPlayer.Row], done: Int, kgStep: Double) -> Advice? {
        guard done < rows.count, done > 0 else { return nil }
        let coming = rows[done].kg
        let logged = rows.prefix(done).filter(\.logged)
        guard coming > 0, let lastRir = logged.last?.rir else { return nil }
        let step = max(kgStep, 0.5)
        let change = max(step, (coming * 0.05 / step).rounded() * step)
        let recent = logged.suffix(2).compactMap(\.rir)
        if recent.count == 2, recent.allSatisfy({ $0 == 0 }) {
            let kg = max(0, coming - change)
            return Advice(question: "Too heavy?", answer: "Failed twice. Drop to \(WatchPlayer.kg(kg)) kg.", kg: kg)
        }
        if recent.count == 2, recent.allSatisfy({ $0 >= 4 }) {
            let kg = coming + change
            return Advice(question: "Too light?", answer: "Easy twice. Go to \(WatchPlayer.kg(kg)) kg.", kg: kg)
        }
        if lastRir == 0 {
            return Advice(question: "Too heavy?", answer: "Keep \(WatchPlayer.kg(coming)) kg, stop one rep short.", kg: nil)
        }
        return nil
    }
}

extension WatchPlayer {
    /// Wrist Coach "Apply" (#608 C): the weight for every set still to do.
    func applyKg(_ kg: Double) {
        guard let step, var r = rows[step.uid] else { return }
        for i in r.indices where i >= done && !r[i].logged { r[i].kg = kg }
        rows[step.uid] = r
        coachApplied = "\(step.uid)#\(done)"
    }

    var wristAdvice: WristCoach.Advice? {
        guard let step, step.loggable, let r = rows[step.uid], coachApplied != "\(step.uid)#\(done)" else { return nil }
        return WristCoach.advice(rows: r, done: done, kgStep: step.kgStep)
    }
}
