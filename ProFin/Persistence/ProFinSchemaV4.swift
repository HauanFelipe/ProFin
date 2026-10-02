import Foundation
import SwiftData

// Estrutura congelada: não usar modelos vivos em schemas anteriores.
enum ProFinSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] { [FinancialTransaction.self, Category.self, FinancialAccount.self, AccountTransfer.self, RecurringExpense.self, RecurringExpenseOccurrence.self] }
}

extension ProFinSchemaV4 {
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

extension ProFinSchemaV4 {
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

extension ProFinSchemaV4 {
    @Model
    final class FinancialAccount {
        // UUID gerado pelo app. .unique é incompatível com as inversas
        // obrigatórias de transferências protegidas pela regra .deny.
        var id: UUID
        var name: String
        var kindRawValue: String
        // Saldo anterior a TODOS os lançamentos da conta. nil significa desconhecido.
        var openingBalanceInCents: Int64?
        var isActive: Bool
        // nil para contas antigas, cuja data de criação não era registrada.
        var createdAt: Date?

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.account)
        var transactions: [FinancialTransaction] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.sourceAccount)
        var outgoingTransfers: [AccountTransfer] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.destinationAccount)
        var incomingTransfers: [AccountTransfer] = []

        var kind: FinancialAccountKind {
            get { FinancialAccountKind(rawValue: kindRawValue) ?? .other }
            set { kindRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            name: String,
            kind: FinancialAccountKind = .other,
            openingBalanceInCents: Int64? = nil,
            createdAt: Date? = Date()
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kind.rawValue
            self.openingBalanceInCents = openingBalanceInCents
            self.isActive = true
            self.createdAt = createdAt
        }
    }
}

extension ProFinSchemaV4 {
    @Model
    final class AccountTransfer {
        @Attribute(.unique) var id: UUID
        var amountInCents: Int64
        var date: Date
        var sourceAccount: FinancialAccount
        var destinationAccount: FinancialAccount
        var notes: String?

        init(
            amountInCents: Int64,
            date: Date,
            sourceAccount: FinancialAccount,
            destinationAccount: FinancialAccount,
            notes: String? = nil
        ) {
            self.id = UUID()
            self.amountInCents = amountInCents
            self.date = date
            self.sourceAccount = sourceAccount
            self.destinationAccount = destinationAccount
            self.notes = notes
        }
    }
}

extension ProFinSchemaV4 {
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

extension ProFinSchemaV4 {
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
