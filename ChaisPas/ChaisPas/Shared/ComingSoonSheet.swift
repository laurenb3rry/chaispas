import SwiftUI

/// A mode player that isn't built yet (PLAN2 phase 9: the library is fully
/// browsable ahead of the players landing). Every stub names its phase.
/// Learn landed in phase 10, Speak in 11; these fall away one by one.
struct ModeStub: Identifiable {
    let title: String
    let phase: Int
    let blurb: String
    var id: String { title }

    static let listen = ModeStub(
        title: "Listen", phase: 12,
        blurb: "Cold listen at full speed, comprehension questions, transcript reveal — then an optional slow pass and shadowing."
    )
    static let read = ModeStub(
        title: "Read", phase: 13,
        blurb: "A cleanly set page with a gloss behind every word, then comprehension questions."
    )
}

/// Design-system placeholder sheet for stubbed players.
struct ComingSoonSheet: View {
    let stub: ModeStub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            VStack(spacing: DSSpacing.lg) {
                Text("COMING IN PHASE \(stub.phase)")
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.accent)
                Text(stub.title)
                    .font(DSType.title)
                    .foregroundStyle(DSColor.textPrimary)
                Text(stub.blurb)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button { dismiss() } label: {
                    Text("D'accord")
                        .font(DSType.body.weight(.medium))
                        .foregroundStyle(DSColor.background)
                        .padding(.horizontal, DSSpacing.xxl)
                        .frame(height: 44)
                        .background(DSColor.accent, in: Capsule())
                }
                .padding(.top, DSSpacing.sm)
            }
            .padding(DSSpacing.xxl)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        ComingSoonSheet(stub: .listen)
    }
}
