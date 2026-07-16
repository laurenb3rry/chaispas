import SwiftData
import SwiftUI

/// Conjugation player (PLAN2 §5.1): the verb's table as a typography moment —
/// aligned columns, formal beside its street form, every form speakable —
/// then the drill run. The politesse mini-module renders its fixed forms as
/// rows instead of a tense table.
struct ConjugationPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let unit: ConceptNode

    @State private var packNode: ContentPackV2.LearnNode?
    @State private var tenseUsage: [String: ContentPackV2.TenseUsage] = [:]
    @State private var drilling = false
    @State private var selectedTense = Self.tenses.first!.key
    @State private var playingKey: String?
    @State private var audio = AudioPlayer()
    @State private var playTask: Task<Void, Never>?

    /// Pack tense keys in teaching order, with display labels.
    static let tenses: [(key: String, label: String)] = [
        ("present", "Présent"),
        ("passe_compose", "Passé composé"),
        ("imparfait", "Imparfait"),
        ("futur_proche", "Futur proche"),
    ]
    static let persons = ["je", "tu", "il", "on", "vous", "ils"]

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
            let file = try? ContentPackV2.loadLearn(.conjugation)
            packNode = file?.nodes.first { $0.id == unit.id }
            tenseUsage = file?.tenseUsage ?? [:]
        }
    }

    // MARK: Intro (the table)

    private var intro: some View {
        VStack(spacing: 0) {
            PlayerChrome(caption: chromeCaption) {
                playTask?.cancel()
                audio.stop()
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    header

                    if let node = packNode {
                        if let table = node.table {
                            tenseSelector(table)
                            tableGrid(node: node, table: table)
                            if let usage = tenseUsage[selectedTense] {
                                TenseUsageView(usage: usage)
                                    .id("usage-\(selectedTense)")
                                    .transition(.opacity)
                                    .padding(.top, DSSpacing.sm)
                            }
                        }
                        if let forms = node.forms {
                            formRows(node: node, forms: forms)
                        }
                        if let notes = node.streetNotes {
                            streetNotes(notes)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xl)
            }

            StartDrillButton {
                playTask?.cancel()
                audio.stop()
                withAnimation(DSMotion.spring) { drilling = true }
            }
        }
    }

    private var chromeCaption: String {
        var parts = ["CONJUGATION"]
        if let family = packNode?.family { parts.append(family.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                // The infinitive is the star; the politesse module has none,
                // so its full title carries the moment.
                Text(packNode?.infinitive ?? unit.title)
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                if let english = packNode?.english {
                    Text(english)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(.top, DSSpacing.lg)

            if let sections = packNode?.explanation, !sections.isEmpty {
                ExplanationSectionsView(sections: sections)
            }
        }
    }

    // MARK: Tense selector

    private func tenseSelector(_ table: [String: [String: ContentPackV2.TableForm]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xl) {
                ForEach(Self.tenses.filter { table[$0.key] != nil }, id: \.key) { tense in
                    Button {
                        withAnimation(DSMotion.spring) { selectedTense = tense.key }
                    } label: {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text(tense.label.uppercased())
                                .font(DSType.caption.weight(.medium))
                                .tracking(1.2)
                                .foregroundStyle(selectedTense == tense.key
                                                 ? DSColor.textPrimary : DSColor.textSecondary)
                            Capsule()
                                .fill(selectedTense == tense.key ? DSColor.accent : .clear)
                                .frame(width: 24, height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, DSSpacing.sm)
    }

    // MARK: The table (aligned columns — a typography moment)

    private func tableGrid(node: ContentPackV2.LearnNode,
                           table: [String: [String: ContentPackV2.TableForm]]) -> some View {
        let tense = table[selectedTense] ?? [:]
        let persons = Self.persons.filter { tense[$0] != nil }
        // NB: GridRow itself must stay unmodified (a modified GridRow
        // collapses into one spanning cell) — the row rhythm lives on the
        // cells instead.
        return Grid(alignment: .leadingFirstTextBaseline,
                    horizontalSpacing: DSSpacing.xl, verticalSpacing: 0) {
            ForEach(persons, id: \.self) { person in
                if let form = tense[person] {
                    GridRow {
                        Text(person)
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .gridColumnAlignment(.leading)
                            .padding(.vertical, DSSpacing.sm + 2)

                        formCell(text: form.formal,
                                 fileName: ContentPackV2.tableAudio(
                                    nodeId: node.id, tense: selectedTense, person: person),
                                 key: "\(selectedTense)_\(person)_formal",
                                 baseColor: DSColor.textPrimary)
                            .padding(.vertical, DSSpacing.sm + 2)

                        if let street = form.street, street != form.formal {
                            formCell(text: street,
                                     fileName: ContentPackV2.tableAudio(
                                        nodeId: node.id, tense: selectedTense,
                                        person: person, street: true),
                                     key: "\(selectedTense)_\(person)_street",
                                     baseColor: DSColor.accent)
                                .padding(.vertical, DSSpacing.sm + 2)
                        } else {
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                    if person != persons.last {
                        GridRow {
                            RowDivider()
                                .gridCellColumns(3)
                        }
                    }
                }
            }
        }
        .id(selectedTense)
        .transition(.opacity)
    }

    // MARK: Politesse fixed forms

    private func formRows(node: ContentPackV2.LearnNode,
                          forms: [ContentPackV2.NamedForm]) -> some View {
        VStack(spacing: 0) {
            ForEach(forms, id: \.id) { form in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(form.english)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    HStack(spacing: DSSpacing.lg) {
                        formCell(text: form.formal,
                                 fileName: ContentPackV2.namedFormAudio(
                                    nodeId: node.id, formId: form.id),
                                 key: "\(form.id)_formal",
                                 baseColor: DSColor.textPrimary)
                        if let street = form.street, street != form.formal {
                            formCell(text: street,
                                     fileName: ContentPackV2.namedFormAudio(
                                        nodeId: node.id, formId: form.id, street: true),
                                     key: "\(form.id)_street",
                                     baseColor: DSColor.accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DSSpacing.sm + 2)
                if form.id != forms.last?.id {
                    RowDivider()
                }
            }
        }
    }

    // MARK: Pieces

    /// One speakable form: tap to hear it; the text glows accent while its
    /// audio plays. No speaker glyphs — the table stays an instrument.
    private func formCell(text: String, fileName: String, key: String,
                          baseColor: Color) -> some View {
        Button { play(fileName, key: key) } label: {
            Text(text)
                .font(DSType.tableForm)
                // long forms (vous avez été) shrink a touch rather than
                // wrap — a wrapped cell breaks the table's row rhythm
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(playingKey == key ? DSColor.accent : baseColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func streetNotes(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("ON THE STREET")
                .font(DSType.caption.weight(.medium))
                .tracking(1.2)
                .foregroundStyle(DSColor.textSecondary)
            Text(notes)
                .font(DSType.frenchCompact)
                .foregroundStyle(DSColor.accent)
                .lineSpacing(3)
        }
        .padding(.top, DSSpacing.sm)
    }

    private func play(_ fileName: String, key: String) {
        playTask?.cancel()
        playTask = Task {
            withAnimation(DSMotion.spring) { playingKey = key }
            await audio.play(fileName: fileName, from: .v2Learn)
            guard !Task.isCancelled else { return }
            withAnimation(DSMotion.spring) { playingKey = nil }
        }
    }
}

// MARK: - Shared player pieces

/// Top chrome of a Learn player's intro stage: what this is + a way out.
struct PlayerChrome: View {
    let caption: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(caption)
                .font(DSType.caption.weight(.medium))
                .tracking(1.2)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("player-close")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.sm)
    }
}

/// The CTA every Learn player's intro ends in.
struct StartDrillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Start the drill")
                .font(DSType.body.weight(.medium))
                .foregroundStyle(DSColor.background)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DSColor.accent, in: Capsule())
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.bottom, DSSpacing.xxl)
    }
}
