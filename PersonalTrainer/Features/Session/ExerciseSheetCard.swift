import SwiftUI
import TrainerCore

/// Um exercício da ficha da sessão (SPEC RF-44 a/b/c, RF-46, §7.14; DESIGN §13; mockup "Sessão: a ficha").
///
/// Estados: pendente e atual (o primeiro pendente, com borda de 1,5 pt em `accent`) mostram o cartão
/// inteiro: número, nome (abre "Informações do exercício"), o botão "Como fazer" quando há guia (SPEC
/// RF-40, E1), selo da nota (abre o "Por quê?"), a meta de hoje em SF Rounded grande com a carga
/// sublinhada quando dá para tocar nela, as bolinhas, "Feito" e a linha pequena "3 séries · descanso
/// 4 min". Feito vira uma linha compacta ("✓ 5, 5, 4 · 60 kg") que se abre com um toque para corrigir
/// uma série; pulado fica esmaecido com "Pulado". Nada de RIR (SPEC RF-41).
///
/// Desde a 2.3: a carga é opcional ("sem carga" no lugar do número, que se toca para pôr uma; RF-44 c,
/// D3), a sugestão de anotar a carga aparece embaixo do cartão uma vez na vida do exercício, e o
/// aeróbico mostra "30 min" ou "4 × 3 min" com a intensidade pelo teste da fala no lugar da carga, o
/// nível opcional, a recuperação andando e a linha fixa de aquecimento dos intervalos (§7.14 F1, F2).
///
/// Lê o `ActiveSessionViewModel` e grava só por ele (AGENTS R4). O selo, o "Como fazer" e o nome são
/// botões separados, lado a lado, nunca um dentro do outro.
struct ExerciseSheetCard: View {
    private let model: ActiveSessionViewModel
    private let exercise: SessionExerciseModel
    private let number: Int
    private let references: ReferenceCatalog
    private let focus: FocusState<UUID?>.Binding
    private let isEditingLoad: Bool
    private let isExpanded: Bool
    private let onOpenInfo: () -> Void
    private let onOpenWhy: (String) -> Void
    private let onEditLoad: () -> Void
    private let onToggleExpanded: () -> Void

    /// Guias do "Como fazer" (SPEC RF-40): o botão só aparece com guia para o exercício realizado.
    @Environment(\.exerciseGuides) private var guides

    init(
        model: ActiveSessionViewModel,
        exercise: SessionExerciseModel,
        number: Int,
        references: ReferenceCatalog,
        focus: FocusState<UUID?>.Binding,
        isEditingLoad: Bool,
        isExpanded: Bool,
        onOpenInfo: @escaping () -> Void,
        onOpenWhy: @escaping (String) -> Void,
        onEditLoad: @escaping () -> Void,
        onToggleExpanded: @escaping () -> Void
    ) {
        self.model = model
        self.exercise = exercise
        self.number = number
        self.references = references
        self.focus = focus
        self.isEditingLoad = isEditingLoad
        self.isExpanded = isExpanded
        self.onOpenInfo = onOpenInfo
        self.onOpenWhy = onOpenWhy
        self.onEditLoad = onEditLoad
        self.onToggleExpanded = onToggleExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardContent
            if model.showsLoadHint(exercise) {
                loadHint
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if exercise.wasSkipped {
            skippedCard
        } else if model.isDone(exercise) && !isExpanded {
            doneCard
        } else {
            fullCard
        }
    }

    // MARK: - Cartão inteiro

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if exercise.substitutedFromUUID != nil {
                Label("Trocado nesta sessão", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if showsLoadField {
                amountText
                    .accessibilityLabel(Text(spokenAmount))
                loadField
            } else if let intensity = model.cardioIntensity(for: exercise) {
                cardioHeadline(intensity)
            } else {
                headline
            }

            actionsRow

            if let detail = detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if model.isCardioIntervals(exercise) {
                Text(CardioText.intervalsWarmup)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded && model.isDone(exercise) {
                Button("Recolher", action: onToggleExpanded)
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isCurrent ? Theme.accent : Color.clear, lineWidth: 1.5)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            numberText

            Button(action: onOpenInfo) {
                Text(exercise.exerciseName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(String(number)). \(exercise.exerciseName)"))
            .accessibilityHint(Text("Abre as informações do exercício"))

            if let guide {
                ExerciseGuideButton(
                    guide: guide,
                    exerciseName: exercise.exerciseName,
                    primaryMuscles: exercise.exercise?.primaryMuscles ?? [],
                    style: .compact
                )
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + 6
                }
            }

            if let badge {
                Button {
                    onOpenWhy(badge.topic)
                } label: {
                    HStack(spacing: 4) {
                        Text(badge.text)
                        Image(systemName: "questionmark.circle")
                            .accessibilityHidden(true)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(badge.text))
                .accessibilityHint(Text("Mostra por que e as referências"))
            }
        }
    }

    private var numberText: some View {
        Text(String(number))
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
    }

    /// A meta de hoje em letra grande (RF-44 a): "3 repetições · 62,5 kg" ou "10 repetições · sem
    /// carga". Com Dynamic Type grande, a carga desce para a linha de baixo em vez de cortar.
    private var headline: some View {
        let loadLabel = model.loadLabel(for: exercise)
        let spoken = SessionSheetText.spokenHeadline(amount: spokenAmount, loadLabel: loadLabel)
        let isLoadTappable = loadLabel != nil && canEditLoad
        let hint = isLoadTappable ? "Toque duas vezes para mudar a carga de hoje" : ""
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                amountText
                if let loadLabel {
                    separator
                    loadButton(loadLabel)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                amountText
                if let loadLabel {
                    loadButton(loadLabel)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(isLoadTappable ? .isButton : [])
        .accessibilityAction {
            if isLoadTappable {
                onEditLoad()
            }
        }
    }

    /// Aeróbico (SPEC §7.14 F1, F2): "30 min" ou "4 × 3 min" em letra grande, o nível da máquina
    /// opcional ao lado ("sem nível", que se toca) e, embaixo, a intensidade pelo teste da fala.
    private func cardioHeadline(_ intensity: CardioIntensity) -> some View {
        let loadLabel = model.loadLabel(for: exercise)
        let intensityLine = CardioText.intensityLine(intensity)
        let spokenBase = SessionSheetText.spokenHeadline(amount: spokenAmount, loadLabel: loadLabel)
        let isLoadTappable = loadLabel != nil && canEditLoad
        let hint = isLoadTappable ? "Toque duas vezes para mudar o nível de hoje" : ""
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    amountText
                    if let loadLabel {
                        separator
                        loadButton(loadLabel)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    amountText
                    if let loadLabel {
                        loadButton(loadLabel)
                    }
                }
            }
            Text(intensityLine)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(spokenBase). \(intensityLine)"))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(isLoadTappable ? .isButton : [])
        .accessibilityAction {
            if isLoadTappable {
                onEditLoad()
            }
        }
    }

    private var separator: some View {
        Text("·")
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    private var amountText: some View {
        Text(amount)
            .font(.system(.title2, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Carga sublinhada em `accent`: tocar abre o teclado (RF-44 b, P10). "sem carga" fica em
    /// `textSecondary`, sublinhado em `accent` porque se toca (DESIGN §13).
    private func loadButton(_ label: String) -> some View {
        let isPlaceholder = model.isLoadPlaceholder(for: exercise)
        return Button(action: onEditLoad) {
            Text(label)
                .font(
                    isPlaceholder
                        ? Font.system(.title3, design: .rounded, weight: .semibold)
                        : Font.system(.title2, design: .rounded, weight: .bold)
                )
                .monospacedDigit()
                .foregroundStyle(isPlaceholder ? Theme.textSecondary : Theme.accent)
                .underline(true, pattern: .dot, color: Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .disabled(!canEditLoad)
    }

    private var loadField: some View {
        let unit = model.loadUnit(of: exercise)
        let placeholder = model.workingLoad(for: exercise).map { SessionSheetText.editableLoadText($0) } ?? "0"
        return LoadEntryField(
            exerciseID: exercise.uuid,
            title: loadFieldTitle(unit: unit),
            unitLabel: SessionSheetText.unitLabel(unit),
            placeholder: placeholder,
            initialValue: nil,
            allowsZero: true,
            focus: focus,
            autoFocus: isEditingLoad,
            onChange: { value in
                if let value {
                    model.setWorkingLoad(value, for: exercise.uuid)
                } else {
                    model.clearWorkingLoad(for: exercise.uuid)
                }
            }
        )
    }

    private func loadFieldTitle(unit: LoadUnit) -> String {
        if unit == .level {
            return "Nível"
        }
        return model.isBodyweight(exercise) ? "Carga extra" : "Carga"
    }

    /// Bolinhas e "Feito". Com Dynamic Type grande ou muitas séries, "Feito" desce.
    private var actionsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dots
                Spacer(minLength: 8)
                feitoButton
            }
            VStack(alignment: .leading, spacing: 8) {
                dots
                feitoButton
            }
        }
    }

    private var dots: some View {
        SetDotsView(
            dots: dotItems,
            measure: measure,
            canMark: model.canMark(exercise),
            canEdit: model.isOpen,
            onMark: { model.markSet(sessionExerciseID: exercise.uuid) },
            onEdit: { model.beginEditingSet(id: $0) }
        )
    }

    @ViewBuilder
    private var feitoButton: some View {
        if model.isPending(exercise) {
            let canMark = model.canMark(exercise)
            Button {
                model.markExerciseDone(sessionExerciseID: exercise.uuid)
            } label: {
                Label("Feito", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(canMark ? Theme.accent : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(canMark ? Theme.accentSoft : Color.clear, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(canMark ? Color.clear : Theme.textSecondary.opacity(0.4), lineWidth: 1.5)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canMark)
            .accessibilityLabel(Text(SessionSheetText.feitoLabel(exerciseName: exercise.exerciseName)))
        }
    }

    // MARK: - Sugestão delicada (SPEC RF-44 c)

    /// "Anotar a carga ajuda a sugerir quando subir." com "Anotar carga" e "Agora não", em
    /// `textSecondary`, sem ícone de alerta (DESIGN §13).
    private var loadHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(SessionSheetText.loadHint)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Button {
                    model.dismissLoadHint(for: exercise.uuid)
                    if model.isDone(exercise) && !isExpanded {
                        onToggleExpanded()
                    }
                    onEditLoad()
                } label: {
                    Text(SessionSheetText.loadHintAccept)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    model.dismissLoadHint(for: exercise.uuid)
                } label: {
                    Text(SessionSheetText.loadHintDismiss)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Feito e pulado

    private var doneCard: some View {
        Button(action: onToggleExpanded) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                numberText
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        Text(SessionSheetText.doneSummary(loggedSets, unit: loadUnit, equipment: equipment, measure: measure))
                            .font(.system(.subheadline, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(doneAccessibilityText))
        .accessibilityHint(Text("Toque duas vezes para ver as séries e corrigir"))
    }

    private var skippedCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            numberText
            Button(action: onOpenInfo) {
                Text(exercise.exerciseName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(exercise.exerciseName), pulado"))
            .accessibilityHint(Text("Abre as informações do exercício"))
            Text("Pulado")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .opacity(0.6)
    }

    // MARK: - Dados

    private var goal: Int {
        model.goal(for: exercise)
    }

    private var measure: ExerciseMeasure {
        model.measure(for: exercise)
    }

    /// A meta em letra grande: "3 repetições", "15 segundos"; no aeróbico, "30 min" ou "4 × 3 min"
    /// (SPEC §7.14 F1).
    private var amount: String {
        if model.isCardio(exercise) {
            return CardioText.amount(sets: exercise.prescribedSets, minutes: goal)
        }
        return TodayTargetText.amount(goal, measure: measure)
    }

    private var spokenAmount: String {
        if model.isCardio(exercise) {
            return CardioText.spokenAmount(sets: exercise.prescribedSets, minutes: goal)
        }
        return TodayTargetText.amount(goal, measure: measure)
    }

    /// "3 séries · descanso 4 min"; nos intervalos, "4 séries · recuperação andando 3 min"; num
    /// aeróbico de uma série, nada.
    private var detailText: String? {
        if model.isCardio(exercise) {
            return CardioText.detail(sets: exercise.prescribedSets, restSeconds: exercise.restSeconds)
        }
        return TodayTargetText.detail(sets: exercise.prescribedSets, restSeconds: exercise.restSeconds)
    }

    private var loadUnit: LoadUnit {
        model.loadUnit(of: exercise)
    }

    private var equipment: Equipment? {
        exercise.exercise?.equipment
    }

    private var isCurrent: Bool {
        model.currentExerciseID == exercise.uuid
    }

    private var canEditLoad: Bool {
        model.isOpen && !exercise.wasSkipped
    }

    /// Campo de carga à vista só quando a pessoa toca na carga (ou em "Anotar carga").
    private var showsLoadField: Bool {
        canEditLoad && isEditingLoad
    }

    /// A guia do exercício realizado (o substituto, se houve troca; SPEC E1).
    private var guide: ExerciseGuide? {
        ExerciseGuideText.guide(
            forSlug: exercise.exercise?.slug,
            isCustom: exercise.exercise?.isCustom ?? false,
            in: guides
        )
    }

    /// Selo leigo da nota (DESIGN §7): some sem novidade (`hold`) ou sem referência no catálogo.
    private var badge: (text: String, topic: String)? {
        guard let note = exercise.note, let text = note.badgeText else {
            return nil
        }
        let topic = ReferenceCatalog.topic(for: note)
        guard !references.references(for: topic).isEmpty else {
            return nil
        }
        return (text: text, topic: topic)
    }

    private var loggedSets: [SessionSheetText.LoggedSet] {
        model.workingSets(of: exercise).map { SessionSheetText.LoggedSet(load: $0.load, reps: $0.reps) }
    }

    private var dotItems: [SetDotsView.Dot] {
        let sets = model.workingSets(of: exercise)
        let total = max(exercise.prescribedSets, sets.count)
        return (0..<total).map { (position: Int) -> SetDotsView.Dot in
            guard position < sets.count else {
                return SetDotsView.Dot(id: position, setID: nil, reps: nil)
            }
            let setLog = sets[position]
            return SetDotsView.Dot(id: position, setID: setLog.uuid, reps: setLog.reps)
        }
    }

    private var doneAccessibilityText: String {
        let summary = SessionSheetText.spokenDoneSummary(loggedSets, unit: loadUnit, equipment: equipment, measure: measure)
        return "\(exercise.exerciseName), feito: \(summary)"
    }
}
