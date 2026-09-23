import Foundation

/// Janela dos últimos `SessionEvent.id` já aplicados pelo `SessionCoordinator` (ARCHITECTURE §7,
/// passo 1): é a chave de idempotência que impede um reenvio do relógio (M3) ou do importador de
/// duplicar uma série (SPEC RF-22).
///
/// Estado em memória (`Set` para consulta O(1) + fila ordenada do mais antigo ao mais novo) com
/// espelho em `UserDefaults` como `[String]`. Quando a fila excede `capacity`, o id mais antigo
/// sai: a janela é por quantidade, não por tempo, para não depender de relógio (SPEC P11).
///
/// `@MainActor` porque só o coordinator usa a classe e tudo que toca SwiftData já roda no ator
/// principal (ARCHITECTURE §10); assim não há estado compartilhado a proteger.
@MainActor
final class AppliedEventStore {
    private var ids: Set<UUID>
    /// Ordem de inserção, do mais antigo (índice 0) ao mais novo.
    private var order: [UUID]
    /// `nil` no modo puramente em memória (`inMemory()`), usado por previews e testes.
    private let storage: UserDefaults?
    private let key: String
    private let capacity: Int

    /// Carrega os ids já gravados em `userDefaults[key]`, descartando entradas que não são
    /// UUID válidos e mantendo só os últimos `capacity` (se a janela encolheu entre versões).
    convenience init(userDefaults: UserDefaults, key: String = "appliedEventIDs", capacity: Int = 2000) {
        self.init(storage: userDefaults, key: key, capacity: capacity)
    }

    /// Sem persistência: cada instância começa vazia e nada sobrevive ao processo. É o que os
    /// testes e previews precisam, sem deixar suites de `UserDefaults` órfãs no simulador.
    static func inMemory() -> AppliedEventStore {
        AppliedEventStore(storage: nil, key: "appliedEventIDs", capacity: 2000)
    }

    private init(storage: UserDefaults?, key: String, capacity: Int) {
        // Capacidade zero ou negativa tornaria a dedup inútil; um id é o mínimo que faz sentido.
        let clampedCapacity = max(1, capacity)
        self.storage = storage
        self.key = key
        self.capacity = clampedCapacity

        var loaded: [UUID] = []
        if let stored = storage?.stringArray(forKey: key) {
            loaded = stored.compactMap { UUID(uuidString: $0) }
        }
        if loaded.count > clampedCapacity {
            loaded = Array(loaded.suffix(clampedCapacity))
        }
        // Remove repetições preservando a primeira ocorrência: a fila nunca deve ter o mesmo id
        // duas vezes, senão a remoção do mais antigo tiraria do `Set` um id ainda na janela.
        var seen: Set<UUID> = []
        var unique: [UUID] = []
        for id in loaded where !seen.contains(id) {
            seen.insert(id)
            unique.append(id)
        }
        self.ids = seen
        self.order = unique
    }

    /// `true` se o evento já foi aplicado dentro da janela.
    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    /// Registra o id como aplicado. Idempotente: um id já presente não é movido nem duplicado.
    func insert(_ id: UUID) {
        guard !ids.contains(id) else {
            return
        }
        ids.insert(id)
        order.append(id)
        while order.count > capacity {
            let oldest = order.removeFirst()
            ids.remove(oldest)
        }
        persist()
    }

    private func persist() {
        storage?.set(order.map { $0.uuidString }, forKey: key)
    }
}
