import SwiftUI
import TrainerCore

/// "Mais opções" (T7.5, SPEC RF-39, §7.5 b; contrato V22 §3.5): o seletor por frequência
/// ("Escolher o dia pela semana"), as semanas entre semanas leves, as referências científicas e a
/// versão do app. Aberta a partir de uma linha do Ajustes; não traz a própria `NavigationStack`
/// (o `SettingsView` já tem uma).
///
/// Só leitura de `model`, exceto pelos dois ajustes de planejamento, que gravam pelos métodos do
/// `SettingsViewModel` (AGENTS R4: nenhuma escrita direta em `UserDefaults` aqui).
struct MoreOptionsView: View {
    private let model: SettingsViewModel
    private let references: ReferenceCatalog

    init(model: SettingsViewModel, references: ReferenceCatalog) {
        self.model = model
        self.references = references
    }

    var body: some View {
        Form {
            planningSection
            scienceSection
            aboutSection
        }
        // Papel (DESIGN §14): o fundo do formulário dá lugar ao papel.
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle("Mais opções")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Seções

    /// SPEC RF-39 (seletor por frequência, chave `plannerFrequencySelector`) e §7.5 (semanas
    /// entre semanas leves, `plannerDeloadWeeks`).
    private var planningSection: some View {
        // Valores lidos aqui, no corpo: a view depende deles e os `Binding`s abaixo ficam em dia.
        let mode = model.frequencySelector
        let weeks = model.deloadWeeks
        return Section {
            Picker(
                "Escolher o dia pela semana",
                selection: Binding<PlannerSettings.FrequencySelectorMode>(
                    get: { mode },
                    set: { newMode in
                        model.setFrequencySelector(newMode)
                    }
                )
            ) {
                Text("Automático").tag(PlannerSettings.FrequencySelectorMode.auto)
                Text("Ligado").tag(PlannerSettings.FrequencySelectorMode.on)
                Text("Desligado").tag(PlannerSettings.FrequencySelectorMode.off)
            }
            Stepper(
                value: Binding<Int>(
                    get: { weeks },
                    set: { newWeeks in
                        model.setDeloadWeeks(newWeeks)
                    }
                ),
                in: SettingsViewModel.deloadWeeksRange
            ) {
                Text(SettingsView.deloadWeeksText(weeks))
            }
        } footer: {
            Text("Ligado, o app escolhe o dia que treina os músculos que ficaram para trás na semana. No automático, liga em planos de 4 dias ou mais.")
        }
    }

    private var scienceSection: some View {
        Section {
            NavigationLink {
                ReferenceListView(catalog: references)
            } label: {
                Label("Referências científicas", systemImage: "book")
            }
        } header: {
            Text("Ciência")
        } footer: {
            Text("As fontes por trás das regras de progressão, volume, descanso e objetivos.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Versão", value: model.appVersion)
        } header: {
            Text("Sobre")
        }
    }
}
