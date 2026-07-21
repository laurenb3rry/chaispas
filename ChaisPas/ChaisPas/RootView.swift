import SwiftData
import SwiftUI

/// Launch gate: populated stores go straight to the Home library; a store that
/// needs the pack import runs it on a background context behind a plain dark
/// screen (no loading UI — the dark launch screen already covers the brief
/// flash), then spring-transitions in. `needsImport` is decided synchronously
/// at app init (cheap fetchCounts) so a normal launch never waits. A first
/// launch (no drill history, never offered) lands on the placement assessment
/// before Home — skippable, and suppressible in UI tests via
/// `-placementOffered YES` launch arguments.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var importing: Bool
    @State private var offeringPlacement = false

    init(needsImport: Bool) {
        _importing = State(initialValue: needsImport)
    }

    var body: some View {
        Group {
            if importing {
                // First-launch import runs behind a plain dark screen — no
                // loading UI; the dark launch screen already covers the flash.
                DSColor.background.ignoresSafeArea()
                    .transition(.opacity)
            } else if offeringPlacement {
                PlacementView(isFirstRun: true) {
                    PlacementGate.markOffered()
                    withAnimation(DSMotion.spring) { offeringPlacement = false }
                }
                .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
        }
        .task {
            if importing {
                let container = modelContext.container
                await Task.detached(priority: .userInitiated) {
                    ContentPackImporter.importIfNeeded(context: ModelContext(container))
                }.value
            }
            withAnimation(DSMotion.spring) {
                offeringPlacement = PlacementGate.shouldOffer(context: modelContext)
                importing = false
            }
        }
    }
}

#Preview("Importing") {
    RootView(needsImport: true)
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
