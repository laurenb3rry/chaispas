import SwiftData
import SwiftUI

/// Vocabulary player (PLAN2 §5.1): the pack's 25 words as swipeable cards
/// with audio — a browsable introduction, never a memorization test — then
/// the sentence drill run (words are only ever drilled inside sentences).
struct VocabPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let unit: ConceptNode

    @State private var packNode: ContentPackV2.LearnNode?
    @State private var drilling = false
    @State private var wordIndex = 0
    @State private var audio = AudioPlayer()
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if drilling {
                DrillRunView(unit: unit) { dismiss() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                intro
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard packNode == nil else { return }
            audio.configureSession()
            packNode = ContentPackV2.learnNode(id: unit.id, module: .vocab)
            if let first = packNode?.words?.first {
                play(first)
            }
        }
    }

    // MARK: Intro (word cards)

    private var words: [ContentPackV2.VocabWord] { packNode?.words ?? [] }

    private var intro: some View {
        VStack(spacing: 0) {
            // The pack title already says "Vocabulary 1 · words 1–25" —
            // no mode prefix, or the chrome stutters and truncates.
            PlayerChrome(caption: unit.title) {
                playTask?.cancel()
                audio.stop()
                dismiss()
            }

            if words.isEmpty {
                Spacer()
            } else {
                wordPager
            }

            StartDrillButton {
                playTask?.cancel()
                audio.stop()
                withAnimation(DSMotion.spring) { drilling = true }
            }
        }
    }

    private var wordPager: some View {
        VStack(spacing: DSSpacing.lg) {
            TabView(selection: $wordIndex) {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    wordCard(word)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: wordIndex) { _, newIndex in
                // Hear every word as it arrives — swiping is the lesson.
                if words.indices.contains(newIndex) {
                    play(words[newIndex])
                }
            }

            VStack(spacing: DSSpacing.md) {
                Eyebrow("\(wordIndex + 1) of \(words.count)")
                // Position through the pack as a hairline, not dots.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DSColor.surface)
                        Capsule().fill(DSColor.accent)
                            .frame(width: geo.size.width
                                   * Double(wordIndex + 1) / Double(max(words.count, 1)))
                    }
                }
                .frame(width: 120, height: 2)
                .animation(DSMotion.spring, value: wordIndex)
            }
            .padding(.bottom, DSSpacing.lg)
        }
    }

    private func wordCard(_ word: ContentPackV2.VocabWord) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                Eyebrow(word.pos, micro: true)

                Text(word.lemma)
                    .font(DSType.stageFrench)
                    .foregroundStyle(DSColor.textPrimary)

                Text(word.english)
                    .font(DSType.stagePrompt)
                    .foregroundStyle(DSColor.textSecondary)

                if let note = word.note {
                    Text(note)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.accent)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.margin)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { play(word) }
    }

    private func play(_ word: ContentPackV2.VocabWord) {
        playTask?.cancel()
        playTask = Task {
            await audio.play(fileName: ContentPackV2.wordAudio(wordId: word.id),
                             from: .v2Learn)
        }
    }
}
