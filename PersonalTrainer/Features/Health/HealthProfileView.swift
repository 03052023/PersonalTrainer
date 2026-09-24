import SwiftUI
import TrainerCore

/// Perfil usado só pelo painel de saúde (SPEC §7.10 A1 e A3): ano de nascimento, sexo e FCmáx
/// medida. Serve quando o app Saúde não informa data de nascimento ou sexo (o usuário pode negar
/// esses dois tipos) e para registrar uma FCmáx medida em teste.
///
/// Grava pelo `HealthViewModel.saveProfile` (chaves `profileBirthYear`, `profileSex` e
/// `profileMaxHeartRate` em `UserDefaults`); nada vai para o SwiftData nem para o motor de
/// musculação (SPEC P12). O que vem do Saúde tem prioridade sobre ano e sexo daqui.
struct HealthProfileView: View {
    private typealias Format = HealthCardView.Format

    private let model: HealthViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var birthYear: Int?
    @State private var sex: BiologicalSexValue?
    /// Texto livre para não depender de `TextField` com valor opcional formatado; validado em
    /// `parsedMaxHeartRate`.
    @State private var maxHeartRateText: String

    /// Ordem fixa das opções (o contrato não garante `CaseIterable`).
    private static let sexOptions: [BiologicalSexValue] = [.female, .male, .other]
    /// Idades aceitas no seletor: de 10 a 100 anos.
    private static let youngestAge = 10
    private static let oldestAge = 100

    init(model: HealthViewModel) {
        self.model = model
        _birthYear = State(initialValue: model.profileBirthYear)
        _sex = State(initialValue: model.profileSex)
        _maxHeartRateText = State(initialValue: model.profileMaxHeartRate.map { String($0) } ?? "")
    }

    var body: some View {
        Form {
            if let health = model.healthProvidedPhysiology {
                healthSection(health)
            }

            Section {
                Picker("Ano de nascimento", selection: $birthYear) {
                    Text("Não informado").tag(Int?.none)
                    ForEach(yearOptions, id: \.self) { year in
                        Text(verbatim: String(year)).tag(Int?.some(year))
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("Sexo", selection: $sex) {
                    Text("Não informado").tag(BiologicalSexValue?.none)
                    ForEach(Self.sexOptions, id: \.self) { option in
                        Text(Self.sexLabel(option)).tag(BiologicalSexValue?.some(option))
                    }
                }
            } header: {
                Text("Idade e sexo")
            } footer: {
                Text("A idade estima a sua FCmáx (208 − 0,7 × idade), que separa minutos moderados de vigorosos. Idade e sexo escolhem a tabela da faixa de VO2máx; a tabela só existe para feminino e masculino.")
            }

            Section {
                TextField("Ex.: 185", text: $maxHeartRateText)
                    .keyboardType(.numberPad)
                if maxHeartRateIsInvalid {
                    Text("Use um valor entre \(HealthViewModel.maxHeartRateRange.lowerBound) e \(HealthViewModel.maxHeartRateRange.upperBound) bpm.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("FCmáx medida (opcional)")
            } footer: {
                Text("Só preencha se mediu a sua frequência cardíaca máxima num teste de esforço. Em branco, o app usa a estimativa pela idade.")
            }

            Section {
                Text("Estes dados ficam só neste aparelho, servem apenas ao painel de saúde e nunca mudam a carga da musculação.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Perfil de saúde")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") {
                    save()
                }
                .disabled(maxHeartRateIsInvalid)
            }
        }
    }

    // MARK: - Dados do app Saúde

    private func healthSection(_ health: UserPhysiology) -> some View {
        Section {
            LabeledContent("Data de nascimento") {
                Text(health.birthDate.map { Format.date($0, calendar: model.calendar) } ?? "não informada")
            }
            LabeledContent("Sexo") {
                Text(health.sex.map { Self.sexLabel($0) } ?? "não informado")
            }
        } header: {
            Text("Do app Saúde")
        } footer: {
            Text("Quando o app Saúde informa data de nascimento ou sexo, esses valores têm prioridade sobre os preenchidos abaixo.")
        }
    }

    // MARK: - Validação e gravação

    /// Anos do mais recente ao mais antigo; comparações diretas evitam montar intervalo invertido
    /// com um relógio absurdo.
    private var yearOptions: [Int] {
        let latest = model.currentYear - Self.youngestAge
        let earliest = model.currentYear - Self.oldestAge
        guard earliest <= latest else { return [] }
        var years = Array((earliest...latest).reversed())
        // Um ano salvo fora da janela (ex.: gravado anos atrás) continua selecionável.
        if let birthYear, !years.contains(birthYear) {
            years.append(birthYear)
        }
        return years
    }

    private var trimmedMaxHeartRateText: String {
        maxHeartRateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` quando em branco ou inválido.
    private var parsedMaxHeartRate: Int? {
        guard let value = Int(trimmedMaxHeartRateText),
              HealthViewModel.maxHeartRateRange.contains(value) else { return nil }
        return value
    }

    private var maxHeartRateIsInvalid: Bool {
        !trimmedMaxHeartRateText.isEmpty && parsedMaxHeartRate == nil
    }

    private func save() {
        model.saveProfile(birthYear: birthYear, sex: sex, maxHeartRate: parsedMaxHeartRate)
        dismiss()
    }

    /// Rótulo pt-BR do sexo (o contrato do TrainerCore não traz `displayName` para esse enum).
    /// `nonisolated`: função pura, chamável de qualquer fechamento sem herdar o MainActor da view.
    nonisolated private static func sexLabel(_ value: BiologicalSexValue) -> String {
        switch value {
        case .female: return "Feminino"
        case .male: return "Masculino"
        case .other: return "Outro"
        }
    }
}
