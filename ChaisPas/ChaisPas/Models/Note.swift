import Foundation
import SwiftData

/// A quick note jotted while consuming content anywhere in the app — raised with
/// a two-finger tap over any surface, kept and edited later in `NotesView`.
/// Local-only for now (no iCloud sync): survives a relaunch, not a reinstall.
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var body: String
    /// A super-light breadcrumb of where it was taken ("Grammar", "Speak").
    /// Empty when captured from a surface that doesn't set one.
    var context: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        body: String = "",
        context: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.body = body
        self.context = context
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
