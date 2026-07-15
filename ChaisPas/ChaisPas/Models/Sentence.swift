import Foundation
import SwiftData

@Model
final class Sentence {
    @Attribute(.unique) var id: String
    var conceptIds: [String]
    // The concept this drill was generated for (conceptIds also lists the
    // prereqs the sentence happens to use); default enables lightweight
    // migration of stores imported before this field existed
    var targetConceptId: String = ""
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
    // Which content pack the sentence ships in (1 or 2) — audio resolves
    // against that pack's directory. Default keeps migration lightweight.
    var packVersion: Int = 1
    // `{id}_english.mp3` in content_pack_v2/english_prompts (hands-free
    // prompt audio); nil until the importer backfills it
    var englishAudioRef: String?

    init(
        id: String,
        conceptIds: [String],
        targetConceptId: String,
        english: String,
        frenchFormal: String,
        frenchStreet: String,
        audioRefs: AudioRefs,
        fsrsStability: Double = 0,
        fsrsDifficulty: Double = 0,
        fsrsDue: Date = .distantPast,
        packVersion: Int = 1,
        englishAudioRef: String? = nil
    ) {
        self.id = id
        self.conceptIds = conceptIds
        self.targetConceptId = targetConceptId
        self.english = english
        self.frenchFormal = frenchFormal
        self.frenchStreet = frenchStreet
        self.audioRefs = audioRefs
        self.fsrsStability = fsrsStability
        self.fsrsDifficulty = fsrsDifficulty
        self.fsrsDue = fsrsDue
        self.packVersion = packVersion
        self.englishAudioRef = englishAudioRef
    }
}
