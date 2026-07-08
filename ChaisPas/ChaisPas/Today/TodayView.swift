import SwiftData
import SwiftUI

/// App entry point: one glance (due count, what's new today), one CTA.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var dueCount = 0
    @State private var upNextTitle: String?
    @State private var practicedToday = false
    @State private var showingSession = false
    @State private var showingDebug = false

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                            .font(DSType.caption.weight(.medium))
                            .tracking(1.2)
                            .foregroundStyle(DSColor.textSecondary)
                        Text("Chais pas.")
                            .font(DSType.largeTitle)
                            .tracking(DSType.largeTitleTracking)
                            .foregroundStyle(DSColor.textPrimary)
                    }
                    Spacer()
                    // Out-of-the-way door to the phase-3 debug screen
                    Button { showingDebug = true } label: {
                        Image(systemName: "ant")
                            .font(.system(size: 13))
                            .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.top, DSSpacing.xl)

                Spacer()

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("\(dueCount)")
                        .font(DSType.statNumeral.monospacedDigit())
                        .foregroundStyle(DSColor.textPrimary)
                        .contentTransition(.numericText())
                    Text(dueCount == 1 ? "review due" : "reviews due")
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textSecondary)
                    if let upNextTitle {
                        Text("new today · \(upNextTitle)")
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.accent)
                            .padding(.top, DSSpacing.sm)
                    }
                }

                Spacer()

                VStack(spacing: DSSpacing.md) {
                    Button { showingSession = true } label: {
                        Text(practicedToday ? "Practice again" : "Start session")
                            .font(DSType.body.weight(.medium))
                            .foregroundStyle(DSColor.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(DSColor.accent, in: Capsule())
                    }
                    if practicedToday {
                        Text("done for today")
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .padding(.bottom, DSSpacing.lg)
            }
            .padding(.horizontal, DSSpacing.margin)
        }
        .preferredColorScheme(.dark)
        .task { refresh() }
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) {
            SessionView()
        }
        .sheet(isPresented: $showingDebug) {
            DebugView()
        }
    }

    private func refresh() {
        let now = Date.now
        dueCount = (try? modelContext.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.fsrsStability > 0 && $0.fsrsDue <= now }
        ))) ?? 0

        let startOfDay = Calendar.current.startOfDay(for: now)
        practicedToday = ((try? modelContext.fetchCount(FetchDescriptor<SessionLog>(
            predicate: #Predicate { $0.date >= startOfDay }
        ))) ?? 0) > 0

        let nodes = (try? modelContext.fetch(FetchDescriptor<ConceptNode>())) ?? []
        let unlocked = (try? MasteryModel.unlockedConceptIds(context: modelContext)) ?? []
        upNextTitle = nodes
            .filter { unlocked.contains($0.id) && !$0.introduced }
            .min { ($0.tier, $0.id) < ($1.tier, $1.id) }?
            .title
    }
}

#Preview {
    TodayView()
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self, SessionLog.self],
            inMemory: true
        )
}
