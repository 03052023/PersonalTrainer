import Foundation

/// Apelidos para a versão corrente do esquema.
///
/// O resto do app (Services, Features, Mappers) usa só estes nomes. Quando `SchemaV2`
/// existir, basta apontar os typealiases para ela: nenhum `@Query`, `#Predicate` ou
/// repositório precisa mudar (ARCHITECTURE §5, decisão 4).
typealias CurrentSchema = SchemaV1

typealias ExerciseModel = SchemaV1.ExerciseModel
typealias ProgramModel = SchemaV1.ProgramModel
typealias ProgramDayModel = SchemaV1.ProgramDayModel
typealias ProgramExerciseModel = SchemaV1.ProgramExerciseModel
typealias WorkoutSessionModel = SchemaV1.WorkoutSessionModel
typealias SessionExerciseModel = SchemaV1.SessionExerciseModel
typealias SetLogModel = SchemaV1.SetLogModel
typealias UserSettingsModel = SchemaV1.UserSettingsModel
