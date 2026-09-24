@testable import PersonalTrainer

// TEMPORÁRIO (onda 3, branch v3/coach). O INTEGRADOR APAGA ESTE ARQUIVO junto com
// PersonalTrainer/Services/Coach/SessionPlanning+CoachShim.swift ao mesclar v3/planner.
//
// Liga o double de `CoachServiceTests` à ponte `CoachPlanningShim`, para que as chamadas do
// `CoachService` por `any SessionPlanning` cheguem aos métodos do double enquanto eles ainda não
// são requisitos do protocolo. Depois da mescla, os mesmos métodos do double implementam os
// requisitos reais e esta conformidade deixa de existir.
extension CoachTestPlanner: CoachPlanningShim {}
