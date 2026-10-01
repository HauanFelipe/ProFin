import Foundation
import SwiftData

// Retrato do schema original. Não alterar: necessário para abrir bancos já existentes.
enum ProFinSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [FinancialTransaction.self, Category.self] }

    @Model
    final class FinancialTransaction {
        @Attribute(.unique) var id: UUID
        var title: String
        var amountInCents: Int64
        var date: Date
        var category: Category
        var type: TransactionType
        var classification: ExpenseClassification?
        var notes: String?

        init(
            title: String,
            amountInCents: Int64,
            date: Date,
            category: Category,
            type: TransactionType,
            classification: ExpenseClassification? = nil,
            notes: String? = nil
        ) {
            self.id = UUID()
            self.title = title
            self.amountInCents = amountInCents
            self.date = date
            self.category = category
            self.type = type
            self.classification = type == .expense ? classification : nil
            self.notes = notes
        }
    }

    @Model
    final class Category {
        @Attribute(.unique) var id: UUID
        var name: String
        var isActive: Bool

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.category)
        var transactions: [FinancialTransaction] = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.isActive = true
        }
    }
}
