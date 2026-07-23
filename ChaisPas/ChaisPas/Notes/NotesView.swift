import SwiftData
import SwiftUI

/// The kept list of notes. Each is editable in place, Apple-Notes style — edits
/// autosave and bump `updatedAt`. Ordered newest-captured first (stable while
/// editing), one after another, split by hairlines, the whole thing scrolling as
/// notes grow. Reached from the Home header, left of Settings.
struct NotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PullToDismissDetector { dismiss() }.frame(height: 0)
                    header
                    if notes.isEmpty {
                        emptyState
                    } else {
                        Hairline(strong: true)
                        ForEach(notes) { note in
                            NoteRow(note: note)
                            Hairline()
                        }
                    }
                }
                .padding(.bottom, DSSpacing.xxl)
            }
            .pullDismissBounce()
            StatusBarScrim()
        }
        .preferredColorScheme(.dark)
        .tint(DSColor.accent)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Eyebrow(notes.isEmpty
                        ? "Notes"
                        : "\(notes.count) note\(notes.count == 1 ? "" : "s")")
                Text("Notes")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("notes-close")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.xl)
        .padding(.bottom, DSSpacing.lg)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Hairline(strong: true)
            Text("Nothing yet.")
                .font(DSType.body)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.top, DSSpacing.lg)
            Text("Two-finger tap anywhere while you're learning to jot a note. It lands here.")
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .padding(.horizontal, DSSpacing.margin)
    }
}

/// One note: breadcrumb + edited-date on top, then the body as an inline,
/// autosizing, autosaving field. Swipe left, Messages-style, to reveal a trash
/// button that deletes it.
private struct NoteRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note

    /// How far the row slides to reveal the trash button.
    private let revealWidth: CGFloat = 76
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
            content
                .background(DSColor.background)
                .offset(x: offset)
                .highPriorityGesture(swipe)
        }
        .clipped()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                if !note.context.isEmpty {
                    Eyebrow(note.context, color: DSColor.textTertiary, micro: true)
                }
                Spacer()
                MonoData(note.updatedAt.formatted(.dateTime.month(.abbreviated).day()))
            }
            TextField("Note", text: $note.body, axis: .vertical)
                .font(DSType.body)
                .foregroundStyle(DSColor.textPrimary)
                .tint(DSColor.accent)
                .onChange(of: note.body) {
                    note.updatedAt = .now
                    try? modelContext.save()
                }
                .accessibilityIdentifier("note-row-field")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.vertical, DSSpacing.lg)
        .contentShape(Rectangle())
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: delete) {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(DSColor.gradeFailure)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("note-delete")
        .opacity(offset < -1 ? 1 : 0)
    }

    /// A horizontal drag that only reveals the trash on a leftward pull, snapping
    /// open or closed on release. `highPriorityGesture` keeps a real horizontal
    /// swipe from scrolling the list, while leaving taps into the field alone.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height)
                else { return }
                offset = min(0, max(-revealWidth, value.translation.width))
            }
            .onEnded { value in
                let open = value.translation.width < -revealWidth / 2
                withAnimation(DSMotion.spring) {
                    offset = open ? -revealWidth : 0
                }
            }
    }

    private func delete() {
        modelContext.delete(note)
        try? modelContext.save()
        DSHaptics.reveal()
    }
}

#Preview {
    NotesView()
        .modelContainer(for: Note.self, inMemory: true)
}
