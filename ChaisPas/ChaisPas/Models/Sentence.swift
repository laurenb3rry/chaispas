import Foundation
import SwiftData

@Model
final class Sentence {
    @Attribute(.unique) var id: String
    var conceptIds: [String]
    var english: String
    var frenchFormal: String
    var frenchStreet: String
    var audioRefs: AudioRefs
    // FSRS state flattened (not a nested struct) so the scheduler can run
    // #Predicate queries against the due date
    var fsrsStability: Double
    var fsrsDifficulty: Double
    var fsrsDue: Date
    // Needed to compute elapsed days (retrievability) at review time;
    // nil until the first review
    var fsrsLastReviewed: Date?

    init(
        id: String,
        conceptIds: [String],
        english: String,
        frenchFormal: String,
        frenchStreet: String,
        audioRefs: AudioRefs,
        fsrsStability: Double = 0,
        fsrsDifficulty: Double = 0,
        fsrsDue: Date = .distantPast
    ) {
        self.id = id
        self.conceptIds = conceptIds
        self.english = english
        self.frenchFormal = frenchFormal
        self.frenchStreet = frenchStreet
        self.audioRefs = audioRefs
        self.fsrsStability = fsrsStability
        self.fsrsDifficulty = fsrsDifficulty
        self.fsrsDue = fsrsDue
    }
}
