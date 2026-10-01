import Foundation
import SwiftData

typealias Category = ProFinSchemaV3.Category

extension ProFinSchemaV3 {
    @Model
    final class Category {
        // Mantém os UUIDs existentes sem o índice incompatível com
        // a inversa obrigatória FinancialTransaction.category e .deny.
        var id: UUID
        var name: String
        var isActive: Bool

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.category)
        var transactions: [FinancialTransaction] = []

        @Relationship(deleteRule: .deny, inverse: \RecurringExpense.category)
        var recurringExpenses: [RecurringExpense] = []

        @Relationship(deleteRule: .deny, inverse: \RecurringExpenseOccurrence.category)
        var recurringOccurrences: [RecurringExpenseOccurrence] = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.isActive = true
        }
    }
}
