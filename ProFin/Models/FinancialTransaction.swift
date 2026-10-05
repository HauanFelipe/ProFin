import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: "Receita"
        case .expense: "Despesa"
        }
    }
}

enum ExpenseClassification: String, Codable, CaseIterable, Identifiable {
    case essential
    case nonEssential

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essential: "Essencial"
        case .nonEssential: "Não essencial"
        }
    }
}

typealias FinancialTransaction = ProFinSchemaV9.FinancialTransaction

extension ProFinSchemaV9 {
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
        // Opcional apenas para permitir a migração dos lançamentos da V1.
        var account: FinancialAccount?
        var recurringOccurrence: RecurringExpenseOccurrence?

        init(
            title: String,
            amountInCents: Int64,
            date: Date,
            category: Category,
            type: TransactionType,
            account: FinancialAccount,
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
            self.account = account
        }
    }
}
