import SwiftData

enum ProFinSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [FinancialTransaction.self, Category.self, FinancialAccount.self, AccountTransfer.self,
         RecurringExpense.self, RecurringExpenseOccurrence.self]
    }
}

enum ProFinMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ProFinSchemaV1.self, ProFinSchemaV2.self, ProFinSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ProFinSchemaV1.self, toVersion: ProFinSchemaV2.self),
         .lightweight(fromVersion: ProFinSchemaV2.self, toVersion: ProFinSchemaV3.self)]
    }
}
