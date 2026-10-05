import Foundation
import SwiftData

struct CardInvoiceBalance {
    let pending: Int64
    let appliedCredit: Int64
    let remainingCredit: Int64
}

@MainActor
extension CreditCardService {
    static func balance(_ invoice: CardInvoice, asOf date: Date = Date()) throws -> CardInvoiceBalance {
        var credit = Decimal.zero
        for item in invoice.card.invoices.sorted(by: { $0.referenceMonth < $1.referenceMonth }) {
            let net = Decimal(try total(item, asOf: date))
            let applied = min(credit, max(0, net))
            credit = max(0, credit - net)
            let payment = item.payment.flatMap { $0.date <= date ? $0.amountInCents : nil } ?? 0
            let pending = max(0, net - applied - Decimal(payment))
            if item.id == invoice.id {
                return try CardInvoiceBalance(pending: FinancialSummary.cents(pending),
                    appliedCredit: FinancialSummary.cents(applied), remainingCredit: FinancialSummary.cents(credit))
            }
        }
        throw CreditCardError.invalidInvoice
    }

    static func creditBalance(_ invoices: [CardInvoice], asOf date: Date = Date()) throws -> Int64 {
        let cards = Dictionary(grouping: invoices, by: { $0.card.id })
        return try FinancialSummary.cents(cards.values.reduce(Decimal.zero) { sum, items in
            guard let last = items.first?.card.invoices.max(by: { $0.referenceMonth < $1.referenceMonth }) else { return sum }
            return try sum + Decimal(balance(last, asOf: date).remainingCredit)
        })
    }

    static func undoPayment(_ invoice: CardInvoice, in context: ModelContext) throws {
        guard invoice.modelContext === context else { throw FinancialOperationError.differentContext }
        guard let payment = invoice.payment else { throw CreditCardError.noPayment }
        guard payment.account.isActive else { throw FinancialOperationError.inactiveAccount }
        invoice.payment = nil
        context.delete(payment)
        try FinancialOperations.save(in: context)
    }

    // Impede reescrever créditos que possam ter sido consumidos por uma fatura já paga.
    static func requireEditableTimeline(card: CreditCard, from month: Date) throws {
        guard !card.invoices.contains(where: { $0.referenceMonth >= month && $0.payment != nil }) else {
            throw CreditCardError.laterPaidInvoice
        }
    }

    @discardableResult
    static func refund(purchase: CardPurchase, amount: Int64, date: Date, month: Date,
                       notes: String? = nil, now: Date = Date(), calendar: Calendar = .current,
                       in context: ModelContext) throws -> CardRefund {
        guard purchase.modelContext === context else { throw FinancialOperationError.differentContext }
        let refunded = try FinancialSummary.cents(purchase.refunds.reduce(Decimal.zero) { $0 + Decimal($1.amountInCents) })
        guard amount > 0, Decimal(amount) + Decimal(refunded) <= Decimal(purchase.amountInCents),
              date >= purchase.date, date <= now else { throw CreditCardError.invalidRefund }
        let month = try RecurringSchedule.month(containing: month, calendar: calendar)
        try requireEditableTimeline(card: purchase.card, from: month)
        let key = RecurringSchedule.key(expenseID: purchase.card.id, month: month, calendar: calendar)
        let existing = purchase.card.invoices.first { $0.invoiceKey == key }
        let dates = try dates(month: month, closingDay: purchase.card.closingDay, dueDay: purchase.card.dueDay, calendar: calendar)
        guard (existing?.dueDate ?? dates.due) >= calendar.startOfDay(for: date) else { throw CreditCardError.invalidInvoice }
        let invoice = existing ?? CardInvoice(card: purchase.card, month: month, closingDate: dates.closing, dueDate: dates.due, key: key)
        if existing == nil { context.insert(invoice) }
        let refund = CardRefund(purchase: purchase, invoice: invoice, amount: amount, date: date, notes: notes)
        context.insert(refund)
        try FinancialOperations.save(in: context)
        return refund
    }

    static func deleteRefund(_ refund: CardRefund, in context: ModelContext) throws {
        guard refund.modelContext === context else { throw FinancialOperationError.differentContext }
        try requireEditableTimeline(card: refund.invoice.card, from: refund.invoice.referenceMonth)
        context.delete(refund)
        try FinancialOperations.save(in: context)
    }
}
