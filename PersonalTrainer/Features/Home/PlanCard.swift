import SwiftUI

/// Card "Próximo treino" da Home (SPEC F1, RF-01): dia em destaque, nome do programa e uma
/// `PrescriptionRow` por exercício, na ordem do plano.
struct PlanCard: View {
    let plan: SessionPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if plan.exercises.isEmpty {
                Text("Este dia não tem exercícios.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                exerciseList
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Próximo treino")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(plan.programDayName)
                .font(.largeTitle.weight(.bold))
            Text(plan.programName)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var exerciseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                if index > 0 {
                    Divider()
                }
                PrescriptionRow(exercise: exercise)
                    .padding(.vertical, 10)
            }
        }
    }
}
