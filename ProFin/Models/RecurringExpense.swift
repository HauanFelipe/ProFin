import Foundation
import SwiftData

enum RecurringAmountType: String, Codable, CaseIterable, Identifiable {
    case fixed, variable
    var id: String { rawValue }
    var title: String { self == .fixed ? "Fixa" : "Variável" }
}

enum RecurringFrequency: String, Codable {
    case monthly
}

typealias RecurringExpense = ProFinSchemaV9.RecurringExpense

extension ProFinSchemaV9 {
    @Model
    final class RecurringExpense {
        var id: UUID
        var title: String
        var category: Category
        var expectedAmountInCents: Int64?
        var dueDay: Int
        var frequency: RecurringFrequency
        var amountType: RecurringAmountType
        var classification: ExpenseClassification
        var isActive: Bool
        var createdAt: Date
        // Início do período ativo atual. Ao reativar, não preenche o intervalo inativo.
        var startMonth: Date

        @Relationship(deleteRule: .deny, inverse: \RecurringExpenseOccurrence.recurringExpense)
        var occurrences: [RecurringExpenseOccurrence] = []

        init(title: String, category: Category, expectedAmountInCents: Int64?, dueDay: Int,
             amountType: RecurringAmountType, classification: ExpenseClassification,
             startMonth: Date, createdAt: Date) {
            self.id = UUID()
            self.title = title
            self.category = category
            self.expectedAmountInCents = expectedAmountInCents
            self.dueDay = dueDay
            self.frequency = .monthly
            self.amountType = amountType
            self.classification = classification
            self.isActive = true
            self.createdAt = createdAt
            self.startMonth = startMonth
        }
    }
}
