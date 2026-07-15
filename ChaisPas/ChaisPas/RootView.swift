import SwiftData
import SwiftUI

/// Launch gate: populated stores go straight to the Home library; stores
/// that need pack import show a minimal loading state while the import runs
/// on a background context, then spring-transition in. `needsImport` is
/// decided synchronously at app init (cheap fetchCounts) so a normal launch
/// never flashes the loading screen.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var importing: Bool
    @State private var stage = "Preparing"
    @State private var stageIndex = 0

    init(needsImport: Bool) {
        _importing = State(initialValue: needsImport)
    }

    var body: some View {
        Group {
            if importing {
                loadingState
                    .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
        }
        .task {
            guard importing else { return }
            let container = modelContext.container
            await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                ContentPackImporter.importIfNeeded(context: context) { label, index in
                    Task { @MainActor in
                        withAnimation(DSMotion.spring) {
                            stage = label
                            stageIndex = index
                        }
                    }
                }
            }.value
            withAnimation(DSMotion.spring) { importing = false }
        }
    }

    private var loadingState: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            VStack(spacing: DSSpacing.xl) {
                Text("Chais pas.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)

                VStack(spacing: DSSpacing.md) {
                    // progress as a thin hairline, per the design language
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DSColor.surface)
                            Capsule().fill(DSColor.accent)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(width: 160, height: 2)

                    Text(stage)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .contentTransition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var fraction: CGFloat {
        CGFloat(stageIndex + 1) / CGFloat(ContentPackImporter.stages.count)
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
