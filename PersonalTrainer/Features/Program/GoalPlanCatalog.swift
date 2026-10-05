import Foundation
import TrainerCore

/// Objetivo = plano (SPEC RF-45, RF-35): a partir dos programas do repositório, os 5 objetivos na
/// ordem das pétalas (DESIGN §4), cada um com o plano que vale para ele e, na Hipertrofia, os
/// formatos. Puro e sem relógio: só lê a lista recebida (ordem do repositório, ativo primeiro).
///
/// Regra de RF-45 para um objetivo sem formatos: o programa ativo, se tiver aquele objetivo;
/// senão, o do seed (se ainda tiver aquele objetivo); senão, o primeiro com aquele
/// `effectiveGoal`; senão, nenhum ("Sem plano pronto", não escolhível). Na Hipertrofia, os
/// formatos são os 3 do seed que existirem, nessa ordem (Equilibrado, Mais pernas e glúteos, Mais
/// tronco e braços; SPEC RF-35, versão 2.3); um ativo de Hipertrofia que não é um deles entra como
/// formato extra: o antigo Corpo todo com o título "Corpo todo", e os outros (cópia, o antigo
/// Empurrar/Inferior/Puxar) com o próprio nome. Sem nenhum formato, vale o primeiro programa de
/// Hipertrofia como formato único. Os demais programas ficam no banco e no backup, só fora da tela.
///
/// Vários planos (SPEC §7.15 M1, versão 2.3): até dois programas ativos, de objetivos diferentes, na
/// ordem de `ActivePlanOrder` (o principal primeiro). Cada objetivo olha o ativo dele; com um plano só,
/// tudo fica como antes.
struct GoalPlanCatalog: Sendable, Hashable {
    /// Um formato da Hipertrofia (RF-35): um programa com um título leigo.
    struct Format: Sendable, Hashable, Identifiable {
        /// `ProgramTemplate.id`.
        let id: UUID
        /// "Equilibrado", "Mais pernas e glúteos", "Mais tronco e braços"; num formato extra,
        /// "Corpo todo" (o antigo completo) ou o nome do programa.
        let title: String
        let dayCount: Int
        let isActive: Bool
        /// Programa ativo que não é um dos formatos do seed (só aparece enquanto está ativo).
        let isExtra: Bool
    }

    /// Uma linha da folha "Seu objetivo".
    struct Entry: Sendable, Hashable, Identifiable {
        let goal: ProgramGoal
        /// Programa escolhido ao tocar no objetivo: o ativo, se for deste objetivo; senão, o
        /// plano do objetivo (na Hipertrofia, o primeiro formato). `nil` = sem plano pronto.
        let defaultProgramID: UUID?
        /// Só na Hipertrofia; vazio nos outros objetivos.
        let formats: [Format]
        /// Um programa ativo é deste objetivo ("· atual"). Com dois planos, vale para os dois.
        let isCurrent: Bool
        /// "3 dias", "3 ou 4 dias" ou "Sem plano pronto".
        let dayCountText: String

        var id: ProgramGoal { goal }

        /// Dá para escolher este objetivo.
        var isAvailable: Bool { defaultProgramID != nil }

        /// Programas que este objetivo pode ativar (os formatos, ou o plano).
        var programIDs: [UUID] {
            if !formats.isEmpty {
                return formats.map(\.id)
            }
            if let defaultProgramID {
                return [defaultProgramID]
            }
            return []
        }

        func format(id: UUID?) -> Format? {
            guard let id else { return nil }
            return formats.first { $0.id == id }
        }
    }

    // MARK: - Ids do seed (`programs.v2.json`)

    /// O Equilibrado (SPEC RF-35, 2.3, D1): 4 dias alternando Superior e Inferior, o padrão do seed.
    static let hypertrophyBalancedID = UUID(uuidString: "9FE0818F-1417-4953-B357-43D757054FCC") ?? UUID()
    /// O antigo Corpo todo (3 dias): escondido desde a 2.3, a não ser que esteja ativo.
    static let hypertrophyFullBodyID = UUID(uuidString: "14E3FAC0-8424-4360-AF9D-20D18DCB0E45") ?? UUID()
    static let hypertrophyLowerFocusID = UUID(uuidString: "C7DDB9BA-1897-40D8-BDC8-A14EB6219FDD") ?? UUID()
    static let hypertrophyUpperFocusID = UUID(uuidString: "ADE28A46-680B-4701-A51F-992519A8AD63") ?? UUID()
    /// O antigo Empurrar/Inferior/Puxar: escondido, a não ser que esteja ativo.
    static let legacyPushLegsPullID = UUID(uuidString: "26262EE7-89B0-4048-93F9-1720FD9CBE40") ?? UUID()
    static let strengthID = UUID(uuidString: "32FA941A-31C4-4D4F-86F5-F3EA366BBB49") ?? UUID()
    /// O plano do Cardio (SPEC RF-48, 2.3): cardio simples em minutos.
    static let enduranceCardioID = UUID(uuidString: "09AB286E-D2B2-49C6-8C9F-400D118D8D03") ?? UUID()
    /// O antigo "Resistência muscular", que saiu do seed na 2.3. Instalações antigas o mantêm no
    /// banco; ele só vale como plano do Cardio enquanto estiver ativo (RF-45: "o ativo primeiro").
    static let legacyEnduranceID = UUID(uuidString: "CBE66162-1F29-41BE-9FF6-7A9E34C179BA") ?? UUID()
    static let longevityID = UUID(uuidString: "2F776C4F-4E46-47AB-9150-7DC04C4A980B") ?? UUID()
    static let combatID = UUID(uuidString: "C1EB32E3-D082-411E-9DB8-5D2AEFFE5B21") ?? UUID()

    /// Os 3 formatos da Hipertrofia na ordem da folha (RF-35).
    static let hypertrophyFormats: [(id: UUID, title: String)] = [
        (hypertrophyBalancedID, "Equilibrado"),
        (hypertrophyLowerFocusID, "Mais pernas e glúteos"),
        (hypertrophyUpperFocusID, "Mais tronco e braços"),
    ]

    /// Título leigo de um programa do seed que só aparece como formato extra, enquanto está ativo
    /// (RF-45). Os outros extras usam o nome do programa.
    static func extraFormatTitle(for programID: UUID) -> String? {
        programID == hypertrophyFullBodyID ? "Corpo todo" : nil
    }

    /// O plano do seed de cada objetivo sem formatos.
    static func seedPlanID(for goal: ProgramGoal) -> UUID? {
        switch goal {
        case .strength: return strengthID
        case .endurance: return enduranceCardioID
        case .longevity: return longevityID
        case .combat: return combatID
        case .hypertrophy: return nil
        }
    }

    /// Os 5 objetivos na ordem das pétalas (DESIGN §4): Longevidade, Hipertrofia, Força,
    /// Combate, Cardio.
    static var orderedGoals: [ProgramGoal] {
        ProgramGoal.allCases.sorted { $0.petalIndex < $1.petalIndex }
    }

    // MARK: - Estado

    /// Uma linha por objetivo, na ordem das pétalas.
    let entries: [Entry]
    /// Os programas ativos na ordem de `ActivePlanOrder` (SPEC §7.15 M1): o principal primeiro.
    /// Um só programa por objetivo efetivo: se o banco trouxer dois do mesmo, fica o primeiro.
    let activePrograms: [ProgramTemplate]
    private let programsByID: [UUID: ProgramTemplate]

    init(programs: [ProgramTemplate]) {
        let actives = Self.activePlans(in: programs)
        self.activePrograms = actives
        self.programsByID = Dictionary(programs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.entries = Self.orderedGoals.map { goal in
            Self.makeEntry(
                for: goal,
                programs: programs,
                active: actives.first { $0.effectiveGoal == goal }
            )
        }
    }

    /// O plano principal (SPEC §7.15 M1), se houver.
    var activeProgram: ProgramTemplate? {
        activePrograms.first
    }

    /// Objetivo do plano principal.
    var activeGoal: ProgramGoal? {
        activeProgram?.effectiveGoal
    }

    /// Objetivos dos planos ativos, o principal primeiro (a flor pinta uma pétala por objetivo).
    var activeGoals: [ProgramGoal] {
        activePrograms.map(\.effectiveGoal)
    }

    /// O plano ativo de um objetivo, se houver.
    func activePlan(for goal: ProgramGoal) -> ProgramTemplate? {
        activePrograms.first { $0.effectiveGoal == goal }
    }

    func entry(for goal: ProgramGoal) -> Entry? {
        entries.first { $0.goal == goal }
    }

    func program(id: UUID?) -> ProgramTemplate? {
        guard let id else { return nil }
        return programsByID[id]
    }

    /// Formato do plano principal, quando a Hipertrofia tem mais de um (o título aparece na aba
    /// Plano e no botão da folha).
    var activeFormat: Format? {
        guard let active = activeProgram else {
            return nil
        }
        return formatOfActive(active)
    }

    /// Formato de um plano ativo, quando o objetivo dele tem mais de um formato.
    func formatOfActive(_ program: ProgramTemplate) -> Format? {
        guard
            let goalEntry = self.entry(for: program.effectiveGoal),
            goalEntry.formats.count > 1
        else {
            return nil
        }
        return goalEntry.format(id: program.id)
    }

    // MARK: - Montagem

    /// Os ativos na ordem de M1, sem repetir objetivo efetivo (M1: objetivos diferentes).
    private static func activePlans(in programs: [ProgramTemplate]) -> [ProgramTemplate] {
        var seenGoals: Set<ProgramGoal> = []
        var result: [ProgramTemplate] = []
        for program in ActivePlanOrder.sorted(programs.filter(\.isActive)) {
            guard !seenGoals.contains(program.effectiveGoal) else { continue }
            seenGoals.insert(program.effectiveGoal)
            result.append(program)
        }
        return result
    }

    /// `active` é o plano ativo deste objetivo, se houver.
    private static func makeEntry(
        for goal: ProgramGoal,
        programs: [ProgramTemplate],
        active: ProgramTemplate?
    ) -> Entry {
        let isCurrent = active != nil
        if goal == .hypertrophy {
            let formats = makeHypertrophyFormats(programs: programs, active: active)
            let defaultID: UUID?
            if let active, isCurrent, formats.contains(where: { $0.id == active.id }) {
                defaultID = active.id
            } else {
                defaultID = formats.first?.id
            }
            let counts = formats.map(\.dayCount)
            let text: String
            if let low = counts.min(), let high = counts.max() {
                text = dayRangeText(min: low, max: high)
            } else {
                text = noPlanText
            }
            return Entry(goal: goal, defaultProgramID: defaultID, formats: formats, isCurrent: isCurrent, dayCountText: text)
        }

        let resolved = resolvePlan(for: goal, programs: programs, active: active)
        let text: String
        if let resolved {
            text = dayCountText(resolved.days.count)
        } else {
            text = noPlanText
        }
        return Entry(
            goal: goal,
            defaultProgramID: resolved?.id,
            formats: [],
            isCurrent: isCurrent,
            dayCountText: text
        )
    }

    /// RF-45 para um objetivo sem formatos.
    private static func resolvePlan(for goal: ProgramGoal, programs: [ProgramTemplate], active: ProgramTemplate?) -> ProgramTemplate? {
        if let active, active.effectiveGoal == goal {
            return active
        }
        if
            let seedID = seedPlanID(for: goal),
            let seed = programs.first(where: { $0.id == seedID }),
            seed.effectiveGoal == goal
        {
            return seed
        }
        return programs.first { $0.effectiveGoal == goal }
    }

    /// RF-35 e RF-45 na Hipertrofia.
    private static func makeHypertrophyFormats(programs: [ProgramTemplate], active: ProgramTemplate?) -> [Format] {
        var formats: [Format] = []
        for (id, title) in Self.hypertrophyFormats {
            guard let program = programs.first(where: { $0.id == id }), program.effectiveGoal == .hypertrophy else {
                continue
            }
            formats.append(Format(
                id: program.id,
                title: title,
                dayCount: program.days.count,
                isActive: program.isActive,
                isExtra: false
            ))
        }
        if let active, active.effectiveGoal == .hypertrophy, !formats.contains(where: { $0.id == active.id }) {
            formats.append(Format(
                id: active.id,
                title: Self.extraFormatTitle(for: active.id) ?? active.name,
                dayCount: active.days.count,
                isActive: true,
                isExtra: true
            ))
        }
        if formats.isEmpty, let first = programs.first(where: { $0.effectiveGoal == .hypertrophy }) {
            formats.append(Format(
                id: first.id,
                title: first.name,
                dayCount: first.days.count,
                isActive: first.isActive,
                isExtra: false
            ))
        }
        return formats
    }

    // MARK: - Textos (pt-BR)

    static let noPlanText = "Sem plano pronto"

    /// "1 dia", "3 dias".
    static func dayCountText(_ count: Int) -> String {
        count == 1 ? "1 dia" : "\(count) dias"
    }

    /// "3 dias", "3 ou 4 dias", "3 a 5 dias".
    static func dayRangeText(min low: Int, max high: Int) -> String {
        if low >= high {
            return dayCountText(low)
        }
        if high == low + 1 {
            return "\(low) ou \(high) dias"
        }
        return "\(low) a \(high) dias"
    }

    /// "3 dias por semana", "1 dia por semana".
    static func weeklyText(_ count: Int) -> String {
        "\(dayCountText(count)) por semana"
    }

    /// "Equilibrado · 4 dias".
    static func chipText(_ format: Format) -> String {
        "\(format.title) · \(dayCountText(format.dayCount))"
    }

    /// Leitura do VoiceOver do chip, sem o "·": "Equilibrado, 4 dias".
    static func spokenChipText(_ format: Format) -> String {
        "\(format.title), \(dayCountText(format.dayCount))"
    }

    /// "Dia A — Superior" → "Dia A". Nome sem travessão fica inteiro.
    static func shortDayName(_ name: String) -> String {
        guard let range = name.range(of: " — ") else {
            return name
        }
        let prefix = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? name : prefix
    }
}
