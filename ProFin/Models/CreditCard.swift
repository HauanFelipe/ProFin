import Foundation
import SwiftData

typealias CreditCard = ProFinSchemaV9.CreditCard
typealias CardPurchase = ProFinSchemaV9.CardPurchase
typealias CardInstallment = ProFinSchemaV9.CardInstallment
typealias CardInvoice = ProFinSchemaV9.CardInvoice
typealias CardInvoicePayment = ProFinSchemaV9.CardInvoicePayment

extension ProFinSchemaV9 {
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
        @Relationship(deleteRule: .deny, inverse: \CardRefund.purchase) var refunds: [CardRefund] = []
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
        @Relationship(deleteRule: .deny, inverse: \CardRefund.invoice) var refunds: [CardRefund] = []
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
