import SwiftData

enum ProFinSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] { [FinancialTransaction.self, Category.self, FinancialAccount.self, AccountTransfer.self,
         RecurringExpense.self, RecurringExpenseOccurrence.self,
         SavingsYieldConfiguration.self, SavingsYieldLot.self, Goal.self] }
}

enum ProFinMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ProFinSchemaV1.self, ProFinSchemaV2.self, ProFinSchemaV3.self, ProFinSchemaV4.self, ProFinSchemaV5.self, ProFinSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ProFinSchemaV1.self, toVersion: ProFinSchemaV2.self),
         .lightweight(fromVersion: ProFinSchemaV2.self, toVersion: ProFinSchemaV3.self),
         .lightweight(fromVersion: ProFinSchemaV3.self, toVersion: ProFinSchemaV4.self),
         .lightweight(fromVersion: ProFinSchemaV4.self, toVersion: ProFinSchemaV5.self),
         .lightweight(fromVersion: ProFinSchemaV5.self, toVersion: ProFinSchemaV6.self)]
    }
}
