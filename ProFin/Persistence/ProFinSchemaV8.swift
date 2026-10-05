import Foundation
import SwiftData

enum ProFinSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    static var models: [any PersistentModel.Type] { [FinancialTransaction.self, Category.self, FinancialAccount.self, AccountTransfer.self,
         RecurringExpense.self, RecurringExpenseOccurrence.self,
         SavingsYieldConfiguration.self, SavingsYieldLot.self, Goal.self, CreditCard.self, CardPurchase.self, CardInstallment.self,
         CardInvoice.self, CardInvoicePayment.self, MonthlyPlanSettings.self, MonthlyAllocationRule.self] }
}

extension ProFinSchemaV8 {
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

extension ProFinSchemaV8 {
    @Model final class CreditCard {
        var id: UUID
        var name: String
        var limitInCents: Int64
        var closingDay: Int
        var dueDay: Int
        var isActive: Bool
        @Relationship(deleteRule: .deny, inverse: \CardInvoice.card) var invoices: [CardInvoice] = []
        @Relationship(deleteRule: .deny, inverse: \CardPurchase.card) var purchases: [CardPurchase] = []
        init(name: String, limitInCents: Int64, closingDay: Int, dueDay: Int) {
            id = UUID(); self.name = name; self.limitInCents = limitInCents
            self.closingDay = closingDay; self.dueDay = dueDay; isActive = true
        }
    }

    @Model final class CardPurchase {
        var id: UUID
        var title: String
        var amountInCents: Int64
        var date: Date
        var category: Category
        var classification: ExpenseClassification
        var card: CreditCard
        var notes: String?
        var recurringOccurrence: RecurringExpenseOccurrence?
        @Relationship(deleteRule: .cascade, inverse: \CardInstallment.purchase) var installments: [CardInstallment] = []
        init(title: String, amountInCents: Int64, date: Date, category: Category,
             classification: ExpenseClassification, card: CreditCard, notes: String?) {
            id = UUID(); self.title = title; self.amountInCents = amountInCents; self.date = date
            self.category = category; self.classification = classification; self.card = card; self.notes = notes
        }
    }

    @Model final class CardInstallment {
        var id: UUID
        var number: Int
        var amountInCents: Int64
        var purchase: CardPurchase
        var invoice: CardInvoice
        init(number: Int, amountInCents: Int64, purchase: CardPurchase, invoice: CardInvoice) {
            id = UUID(); self.number = number; self.amountInCents = amountInCents
            self.purchase = purchase; self.invoice = invoice
        }
    }

    @Model final class CardInvoice {
        var id: UUID
        var invoiceKey: String
        var card: CreditCard
        var referenceMonth: Date
        var closingDate: Date
        var dueDate: Date
        @Relationship(deleteRule: .deny, inverse: \CardInstallment.invoice) var installments: [CardInstallment] = []
        @Relationship(deleteRule: .nullify, inverse: \CardInvoicePayment.invoice) var payment: CardInvoicePayment?
        init(card: CreditCard, month: Date, closingDate: Date, dueDate: Date, key: String) {
            id = UUID(); self.card = card; referenceMonth = month
            self.closingDate = closingDate; self.dueDate = dueDate; invoiceKey = key
        }
    }

    @Model final class CardInvoicePayment {
        var id: UUID
        var invoice: CardInvoice
        var account: FinancialAccount
        var amountInCents: Int64
        var date: Date
        init(invoice: CardInvoice, account: FinancialAccount, amountInCents: Int64, date: Date) {
            id = UUID(); self.invoice = invoice; self.account = account
            self.amountInCents = amountInCents; self.date = date
        }
    }
}

extension ProFinSchemaV8 {
@Model
final class Goal {
    var id: UUID
    var name: String
    var targetAmountInCents: Int64
    @Relationship(deleteRule: .nullify) var savingsAccount: FinancialAccount?
    var createdAt: Date
    var isArchived: Bool

    init(name: String, targetAmountInCents: Int64, savingsAccount: FinancialAccount? = nil) {
        id = UUID()
        self.name = name
        self.targetAmountInCents = targetAmountInCents
        self.savingsAccount = savingsAccount
        createdAt = Date()
        isArchived = false
    }
}

}

extension ProFinSchemaV8 {
// Uma posição informada para simulação. Não substitui o histórico financeiro.
@Model
final class SavingsYieldConfiguration {
    @Attribute(.unique) var accountID: UUID
    var annualCDIBasisPoints: Int
    var cdiPercentageBasisPoints: Int
    var referenceDate: Date
    var businessDays: Int
    var ledgerSignature: String
    @Relationship(deleteRule: .cascade) var lots: [SavingsYieldLot] = []

    init(accountID: UUID, annualCDIBasisPoints: Int, cdiPercentageBasisPoints: Int,
         referenceDate: Date, businessDays: Int, ledgerSignature: String) {
        self.accountID = accountID
        self.annualCDIBasisPoints = annualCDIBasisPoints
        self.cdiPercentageBasisPoints = cdiPercentageBasisPoints
        self.referenceDate = referenceDate
        self.businessDays = businessDays
        self.ledgerSignature = ledgerSignature
    }
}

@Model
final class SavingsYieldLot {
    var id: UUID
    var applicationDate: Date
    var principalInCents: Int64
    var grossBalanceInCents: Int64

    init(input: SavingsYieldLotInput) {
        id = input.id
        applicationDate = input.applicationDate
        principalInCents = input.principalInCents
        grossBalanceInCents = input.grossBalanceInCents
    }

    var input: SavingsYieldLotInput {
        SavingsYieldLotInput(id: id, applicationDate: applicationDate,
            principalInCents: principalInCents, grossBalanceInCents: grossBalanceInCents)
    }
}

}

extension ProFinSchemaV8 {
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
        var isEmergencyReserve: Bool = false
        // nil para contas antigas, cuja data de criação não era registrada.
        var createdAt: Date?

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.account)
        var transactions: [FinancialTransaction] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.sourceAccount)
        var outgoingTransfers: [AccountTransfer] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.destinationAccount)
        var incomingTransfers: [AccountTransfer] = []

        @Relationship(deleteRule: .deny, inverse: \CardInvoicePayment.account)
        var cardPayments: [CardInvoicePayment] = []

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

extension ProFinSchemaV8 {
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

extension ProFinSchemaV8 {
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

extension ProFinSchemaV8 {
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

        @Relationship(deleteRule: .deny, inverse: \CardPurchase.category)
        var cardPurchases: [CardPurchase] = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.isActive = true
        }
    }
}

extension ProFinSchemaV8 {
    @Model final class MonthlyPlanSettings {
        @Attribute(.unique) var key: String
        var month: Date
        var extraExpensesInCents: Int64
        var marginInCents: Int64
        init(month: Date, key: String, extras: Int64, margin: Int64) {
            self.month = month; self.key = key; extraExpensesInCents = extras; marginInCents = margin
        }
    }
    @Model final class MonthlyAllocationRule {
        var id: UUID
        // ID é estável e evita apagar o planejamento ao arquivar uma conta.
        @Attribute(.unique) var accountID: UUID
        var monthlyAmountInCents: Int64
        var priority: Int
        init(accountID: UUID, amount: Int64, priority: Int) {
            id = UUID(); self.accountID = accountID; monthlyAmountInCents = amount; self.priority = priority
        }
    }
}

extension ProFinSchemaV8 {
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
