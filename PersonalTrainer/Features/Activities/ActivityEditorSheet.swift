import SwiftUI
import TrainerCore

/// Folha "Registrar atividade" (SPEC §7.17 X1, X2, RF-53; DESIGN §9.3 ponto 2), a mesma para editar um
/// registro e para a fixa: título em New York; o tipo em chips de duas colunas, na ordem da tabela X1;
/// "Duração" de 5 em 5 min; "Intensidade" em três opções com o teste da fala; "Quando" (ou o dia da semana e a
/// hora, na fixa); a chave "Toda semana" no registro novo; e o botão principal "Registrar" ("Salvar").
///
/// Sem texto livre, sem FC, sem calorias (X1, X7). Quem grava é o `ActivityEditorModel`, pelo
/// `ActivitiesModel` (AGENTS R4). Numa falha, a folha fica aberta com o que a pessoa escolheu e a mensagem.
struct ActivityEditorSheet: View {
    @State private var editor: ActivityEditorModel
    @State private var isConfirmingDeletion = false
    @Environment(\.dismiss) private var dismiss

    init(activities: ActivitiesModel, mode: ActivityEditorModel.Mode) {
        self._editor = State(initialValue: ActivityEditorModel(mode: mode, activities: activities))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(editor.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    kindSection
                    durationSection
                    intensitySection
                    if editor.isFixedMode {
                        weekdayAndTimeSection
                    } else {
                        whenSection
                    }
                    if let message = editor.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if editor.canDelete {
                        deleteButton
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .paperBackground()
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                ActivityText.deleteQuestion,
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button(ActivityText.deleteShort, role: .destructive) {
                    if editor.delete() {
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(editor.isFixedMode ? ActivityText.deleteFixedMessage : ActivityText.deleteEntryMessage)
            }
            .onChange(of: editor.draft.repeatsWeekly) { _, isOn in
                if !isOn {
                    editor.keepStartInThePast()
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - Tipo (chips de duas colunas, ordem da tabela X1)

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(ActivityText.kind)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8, alignment: .leading),
                    GridItem(.flexible(), spacing: 8, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(OutsideActivityKind.allCases, id: \.self) { kind in
                    kindChip(kind)
                }
            }
        }
    }

    private func kindChip(_ kind: OutsideActivityKind) -> some View {
        let isSelected = editor.draft.kind == kind
        return Button {
            editor.selectKind(kind)
        } label: {
            Text(kind.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Theme.accentSoft : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Theme.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Duração (5 em 5 min, X1)

    private var durationSection: some View {
        Stepper(
            value: $editor.draft.minutes,
            in: OutsideActivities.minutesRange,
            step: 5
        ) {
            HStack {
                Text(ActivityText.duration)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(ActivityText.minutesText(editor.draft.minutes))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityValue(Text(ActivityText.minutesSpoken(editor.draft.minutes)))
        .padding(14)
        .inkCard()
    }

    // MARK: - Intensidade pelo teste da fala (§7.14 F2)

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(ActivityText.intensity)
            VStack(spacing: 8) {
                ForEach(CardioIntensity.allCases, id: \.self) { intensity in
                    intensityOption(intensity)
                }
            }
        }
    }

    private func intensityOption(_ intensity: CardioIntensity) -> some View {
        let isSelected = editor.draft.intensity == intensity
        return Button {
            editor.draft.intensity = intensity
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ActivityText.talkTestLine(intensity))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.line)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isSelected ? Theme.accentSoft : Theme.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Quando (registro) ou dia e hora (fixa)

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                ActivityText.when,
                selection: $editor.draft.start,
                in: ...editor.latestStart,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            if editor.showsRepeatToggle {
                Divider()
                Toggle(isOn: $editor.draft.repeatsWeekly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ActivityText.everyWeek)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(editor.repeatHint)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.accent)
            }
        }
        .padding(14)
        .inkCard()
    }

    private var weekdayAndTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ActivityText.day)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Picker(ActivityText.day, selection: $editor.draft.weekday) {
                    ForEach(PlanWeekday.allCases, id: \.self) { weekday in
                        Text(ActivityText.weekdayTitle(weekday)).tag(weekday)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            Divider()
            DatePicker(
                ActivityText.time,
                selection: $editor.draft.start,
                displayedComponents: [.hourAndMinute]
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(14)
        .inkCard()
    }

    // MARK: - Botões

    /// O único botão proeminente da folha (DESIGN §9).
    private var saveButton: some View {
        Button(editor.saveTitle) {
            if editor.submit() {
                dismiss()
            }
        }
        .buttonStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    private var deleteButton: some View {
        Button {
            isConfirmingDeletion = true
        } label: {
            Label(ActivityText.delete, systemImage: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.destructive)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .serif))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
