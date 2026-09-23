import Foundation

/// Apelidos para a versão corrente do esquema.
///
/// O resto do app (Services, Features, Mappers) usa só estes nomes. Uma versão nova de
/// esquema só aponta os typealiases para ela: nenhum `@Query`, `#Predicate` ou repositório
/// precisa mudar (ARCHITECTURE §5, decisão 4). `CurrentSchema` precisa ser sempre a última
/// versão de `PersonalTrainerMigrationPlan.schemas` (há teste para isso).
///
/// Para codificar grupos musculares use `CurrentSchema.encodeMuscleGroups(_:)` /
/// `CurrentSchema.decodeMuscleGroups(_:)` (mesmo CSV em V1 e V2).
typealias CurrentSchema = SchemaV2

typealias ExerciseModel = SchemaV2.ExerciseModel
typealias ProgramModel = SchemaV2.ProgramModel
typealias ProgramDayModel = SchemaV2.ProgramDayModel
typealias ProgramExerciseModel = SchemaV2.ProgramExerciseModel
typealias WorkoutSessionModel = SchemaV2.WorkoutSessionModel
typealias SessionExerciseModel = SchemaV2.SessionExerciseModel
typealias SetLogModel = SchemaV2.SetLogModel
typealias UserSettingsModel = SchemaV2.UserSettingsModel
