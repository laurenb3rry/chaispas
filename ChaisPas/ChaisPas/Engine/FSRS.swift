import Foundation

/// FSRS-4.5 scheduler operating on the flat scalar fields of `Sentence`
/// (fsrsStability / fsrsDifficulty / fsrsDue / fsrsLastReviewed).
///
/// Port of the reference algorithm:
/// https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
enum FSRS {
    enum Grade: Int {
        case again = 1
        case hard = 2
        case good = 3
        case easy = 4
    }

    /// Default FSRS-4.5 weight vector.
    static let w: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
        1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
    ]

    static let desiredRetention = 0.9
    static let maximumIntervalDays = 365.0
    /// A lapse comes back into the queue after 10 minutes, same session.
    static let relearnInterval: TimeInterval = 10 * 60

    private static let decay = -0.5
    /// 19/81 — chosen so interval == stability at 0.9 retention
    private static let factor = pow(0.9, 1 / decay) - 1

    /// Probability of recall after `elapsedDays` at stability `s`.
    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + factor * elapsedDays / max(stability, 0.1), decay)
    }

    /// Next interval in days for a given stability at the desired retention.
    static func intervalDays(stability: Double) -> Double {
        let raw = stability / factor * (pow(desiredRetention, 1 / decay) - 1)
        return min(max(raw, 0), maximumIntervalDays)
    }

    /// Applies one review to the sentence's FSRS state and reschedules it.
    static func review(_ sentence: Sentence, grade: Grade, now: Date = .now) {
        let stability: Double
        let difficulty: Double

        if sentence.fsrsStability <= 0 {
            stability = initialStability(grade)
            difficulty = initialDifficulty(grade)
        } else {
            let lastReviewed = sentence.fsrsLastReviewed ?? now
            let elapsedDays = max(0, now.timeIntervalSince(lastReviewed) / 86_400)
            let r = retrievability(elapsedDays: elapsedDays, stability: sentence.fsrsStability)
            difficulty = nextDifficulty(sentence.fsrsDifficulty, grade: grade)
            if grade == .again {
                stability = forgetStability(
                    difficulty: sentence.fsrsDifficulty,
                    stability: sentence.fsrsStability,
                    retrievability: r
                )
            } else {
                stability = recallStability(
                    difficulty: sentence.fsrsDifficulty,
                    stability: sentence.fsrsStability,
                    retrievability: r,
                    grade: grade
                )
            }
        }

        sentence.fsrsStability = stability
        sentence.fsrsDifficulty = difficulty
        sentence.fsrsLastReviewed = now
        sentence.fsrsDue = grade == .again
            ? now.addingTimeInterval(relearnInterval)
            : now.addingTimeInterval(intervalDays(stability: stability) * 86_400)
    }

    // MARK: - FSRS-4.5 formulas

    static func initialStability(_ grade: Grade) -> Double {
        max(w[grade.rawValue - 1], 0.1)
    }

    static func initialDifficulty(_ grade: Grade) -> Double {
        clampDifficulty(w[4] - Double(grade.rawValue - 3) * w[5])
    }

    static func nextDifficulty(_ d: Double, grade: Grade) -> Double {
        let next = d - w[6] * Double(grade.rawValue - 3)
        // mean reversion toward D0(good) = w4
        return clampDifficulty(w[7] * w[4] + (1 - w[7]) * next)
    }

    static func recallStability(
        difficulty d: Double, stability s: Double, retrievability r: Double, grade: Grade
    ) -> Double {
        let hardPenalty = grade == .hard ? w[15] : 1
        let easyBonus = grade == .easy ? w[16] : 1
        return s * (1 + exp(w[8])
            * (11 - d)
            * pow(s, -w[9])
            * (exp(w[10] * (1 - r)) - 1)
            * hardPenalty
            * easyBonus)
    }

    static func forgetStability(
        difficulty d: Double, stability s: Double, retrievability r: Double
    ) -> Double {
        // post-lapse stability can never exceed the prior stability
        min(w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r)), s)
    }

    private static func clampDifficulty(_ d: Double) -> Double {
        min(max(d, 1), 10)
    }
}
