import Foundation
import SwiftData

typealias RecurringExpenseOccurrence = ProFinSchemaV9.RecurringExpenseOccurrence

extension ProFinSchemaV9 {
    @Model
    final class RecurringExpenseOccurrence {
        var id: UUID
        @Attribute(.unique) var occurrenceKey: String
        var recurringExpense: RecurringExpense
        var referenceMonth: Date
        var dueDate: Date
        var title: String
        var category: Category
        var expectedAmountInCents: Int64?
        var classification: ExpenseClassification
        var amountType: RecurringAmountType

        @Relationship(deleteRule: .nullify, inverse: \FinancialTransaction.recurringOccurrence)
        var paymentTransaction: FinancialTransaction?

        @Relationship(deleteRule: .nullify, inverse: \CardPurchase.recurringOccurrence)
        var cardPurchase: CardPurchase?

        init(expense: RecurringExpense, month: Date, dueDate: Date, key: String) {
            self.id = UUID()
            self.occurrenceKey = key
            self.recurringExpense = expense
            self.referenceMonth = month
            self.dueDate = dueDate
            self.title = expense.title
            self.category = expense.category
            self.expectedAmountInCents = expense.expectedAmountInCents
            self.classification = expense.classification
            self.amountType = expense.amountType
        }
    }
}
