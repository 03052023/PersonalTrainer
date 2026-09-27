import SwiftUI
import TrainerCore

/// Folha de leitura "Informações do exercício" (SPEC RF-47; DESIGN §13; docs/V22-CONTRACT.md §2.2),
/// aberta ao tocar no nome do exercício na tela Hoje e na ficha da sessão.
///
/// Andaime do arquiteto: a assinatura do `init` é o contrato entre as tarefas `home`, `session` e
/// `exercise-info`; o conteúdo completo (por que esta carga, da última vez, notas da máquina e as
/// ações) é da tarefa `exercise-info`.
///
/// As ações só aparecem quando quem apresenta passa o fechamento: a Home não passa nenhum; a ficha
/// passa "Trocar" só antes da primeira série do exercício (SPEC RF-34) e "Pular" enquanto ele não
/// foi pulado. A folha só chama o fechamento: fechar a folha e fazer a ação é de quem apresenta.
struct ExerciseInfoSheet: View {
    private let content: ExerciseInfoContent
    private let references: ReferenceCatalog
    private let onSubstitute: (() -> Void)?
    private let onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        content: ExerciseInfoContent,
        references: ReferenceCatalog,
        onSubstitute: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil
    ) {
        self.content = content
        self.references = references
        self.onSubstitute = onSubstitute
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Hoje") {
                    Text(todayText)
                    Text(TodayTargetText.detail(sets: content.sets, restSeconds: content.restSeconds))
                        .foregroundStyle(Theme.textSecondary)
                }
                if onSubstitute != nil || onSkip != nil {
                    Section {
                        if let onSubstitute {
                            Button("Máquina ocupada? Trocar por outro parecido") {
                                onSubstitute()
                            }
                        }
                        if let onSkip {
                            Button("Pular este exercício") {
                                onSkip()
                            }
                        }
                    }
                }
            }
            .navigationTitle(content.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    private var todayText: String {
        TodayTargetText.row(
            sets: content.sets,
            goal: content.targetReps,
            measure: content.measure,
            load: content.loadDisplay
        )
    }
}
