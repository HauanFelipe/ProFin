import Foundation
import SwiftData

enum CreditCardError: LocalizedError, Equatable {
    case noPayment, invalidRefund, laterPaidInvoice, purchaseHasRefund
    case invalidCard, invalidPurchase, invalidInvoice, paidInvoice, alreadyLinked, insufficientBalance, openInvoice
    var errorDescription: String? {
        switch self {
        case .noPayment: "Esta fatura não possui pagamento para desfazer."
        case .invalidRefund: "Informe um estorno positivo, sem superar o valor ainda não estornado da compra, com data entre a compra e hoje."
        case .laterPaidInvoice: "A alteração afetaria uma fatura paga deste mês ou de um mês seguinte. Confira e desfaça os registros de pagamento afetados antes de corrigir."
        case .purchaseHasRefund: "Remova os estornos registrados antes de excluir a compra."
        case .invalidCard: "Informe nome, limite positivo e dias entre 1 e 31."
        case .invalidPurchase: "Informe descrição, valor positivo, categoria ativa e de 1 a 120 parcelas. Cada parcela precisa ter ao menos um centavo."
        case .invalidInvoice: "Confira a primeira fatura e as datas. O vencimento não pode ser anterior à compra."
        case .paidInvoice: "Esta operação afetaria uma fatura já paga."
        case .alreadyLinked: "A cobrança já está vinculada a um pagamento ou a uma compra no cartão."
        case .insufficientBalance: "A conta não tem saldo conhecido suficiente para pagar esta fatura na data informada."
        case .openInvoice: "Registre o pagamento após o fechamento e após todas as compras da fatura. Nesta etapa o pagamento é integral."
        }
    }
}

@MainActor
enum CreditCardService {
    static func dates(month: Date, closingDay: Int, dueDay: Int, calendar: Calendar = .current) throws -> (closing: Date, due: Date) {
        let month = try RecurringSchedule.month(containing: month, calendar: calendar)
        let due = try RecurringSchedule.dueDate(day: dueDay, month: month, calendar: calendar)
        var close = try RecurringSchedule.dueDate(day: closingDay, month: month, calendar: calendar)
        if close >= due {
            guard let previous = calendar.date(byAdding: .month, value: -1, to: month) else { throw CreditCardError.invalidInvoice }
            close = try RecurringSchedule.dueDate(day: closingDay, month: previous, calendar: calendar)
        }
        return (close, due)
    }

    // Compras no dia do fechamento vão, por padrão, para a próxima fatura.
    // A primeira competência permanece ajustável conforme a fatura do banco.
    static func firstMonth(for date: Date, card: CreditCard, calendar: Calendar = .current) throws -> Date {
        var month = try RecurringSchedule.month(containing: date, calendar: calendar)
        for _ in 0..<3 {
            let schedule = try dates(month: month, closingDay: card.closingDay, dueDay: card.dueDay, calendar: calendar)
            if calendar.startOfDay(for: date) < schedule.closing { return month }
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        throw CreditCardError.invalidInvoice
    }

    static func saveCard(_ card: CreditCard? = nil, name: String, limit: Int64, closingDay: Int,
                         dueDay: Int, active: Bool = true, in context: ModelContext) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, limit > 0, (1...31).contains(closingDay), (1...31).contains(dueDay) else { throw CreditCardError.invalidCard }
        if let card, card.modelContext !== context { throw FinancialOperationError.differentContext }
        let saved = card ?? CreditCard(name: name, limitInCents: limit, closingDay: closingDay, dueDay: dueDay)
        if card == nil { context.insert(saved) }
        saved.name = name; saved.limitInCents = limit; saved.closingDay = closingDay; saved.dueDay = dueDay; saved.isActive = active
        try FinancialOperations.save(in: context)
    }

    @discardableResult
    static func purchase(card: CreditCard, title: String, amount: Int64, date: Date, category: Category,
                         classification: ExpenseClassification, count: Int, firstMonth: Date,
                         notes: String? = nil, occurrence: RecurringExpenseOccurrence? = nil,
                         now: Date = Date(), calendar: Calendar = .current, in context: ModelContext) throws -> CardPurchase {
        guard card.modelContext === context, category.modelContext === context else { throw FinancialOperationError.differentContext }
        guard card.isActive, category.isActive, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...120).contains(count), amount >= Int64(count), date <= now else { throw CreditCardError.invalidPurchase }
        if let occurrence {
            guard occurrence.modelContext === context else { throw FinancialOperationError.differentContext }
            guard occurrence.paymentTransaction == nil, occurrence.cardPurchase == nil else { throw CreditCardError.alreadyLinked }
        }
        let start = try RecurringSchedule.month(containing: firstMonth, calendar: calendar)
        var planned: [(Date, Date, Date, String, CardInvoice?)] = []
        let existing = try context.fetch(FetchDescriptor<CardInvoice>())
        for index in 0..<count {
            let month = calendar.date(byAdding: .month, value: index, to: start)!
            let key = RecurringSchedule.key(expenseID: card.id, month: month, calendar: calendar)
            let invoice = existing.first { $0.invoiceKey == key }
            let schedule = try dates(month: month, closingDay: card.closingDay, dueDay: card.dueDay, calendar: calendar)
            guard invoice?.payment == nil else { throw CreditCardError.paidInvoice }
            guard (invoice?.dueDate ?? schedule.due) >= calendar.startOfDay(for: date) else { throw CreditCardError.invalidInvoice }
            planned.append((month, schedule.closing, schedule.due, key, invoice))
        }
        try requireEditableTimeline(card: card, from: start)
        let purchase = CardPurchase(title: title.trimmingCharacters(in: .whitespacesAndNewlines), amountInCents: amount,
                                    date: date, category: category, classification: classification, card: card, notes: notes)
        context.insert(purchase)
        for (index, item) in planned.enumerated() {
            let invoice = item.4 ?? CardInvoice(card: card, month: item.0, closingDate: item.1, dueDate: item.2, key: item.3)
            if item.4 == nil { context.insert(invoice) }
            let cents = amount / Int64(count) + (Int64(index) < amount % Int64(count) ? 1 : 0)
            context.insert(CardInstallment(number: index + 1, amountInCents: cents, purchase: purchase, invoice: invoice))
        }
        purchase.recurringOccurrence = occurrence
        try FinancialOperations.save(in: context)
        return purchase
    }

    static func link(_ purchase: CardPurchase, to occurrence: RecurringExpenseOccurrence, in context: ModelContext) throws {
        guard purchase.modelContext === context, occurrence.modelContext === context else { throw FinancialOperationError.differentContext }
        guard purchase.recurringOccurrence == nil, occurrence.cardPurchase == nil, occurrence.paymentTransaction == nil else { throw CreditCardError.alreadyLinked }
        purchase.recurringOccurrence = occurrence
        try FinancialOperations.save(in: context)
    }

    static func deletePurchase(_ purchase: CardPurchase, in context: ModelContext) throws {
        guard purchase.modelContext === context else { throw FinancialOperationError.differentContext }
        guard purchase.installments.allSatisfy({ $0.invoice.payment == nil }) else { throw CreditCardError.paidInvoice }
        guard purchase.refunds.isEmpty else { throw CreditCardError.purchaseHasRefund }
        if let first = purchase.installments.map({ $0.invoice.referenceMonth }).min() {
            try requireEditableTimeline(card: purchase.card, from: first)
        }
        purchase.recurringOccurrence?.cardPurchase = nil
        context.delete(purchase)
        try FinancialOperations.save(in: context)
    }

    static func pay(_ invoice: CardInvoice, from account: FinancialAccount, date: Date,
                    now: Date = Date(), calendar: Calendar = .current, in context: ModelContext) throws {
        guard invoice.modelContext === context, account.modelContext === context else { throw FinancialOperationError.differentContext }
        guard invoice.payment == nil else { throw CreditCardError.paidInvoice }
        guard account.isActive else { throw FinancialOperationError.inactiveAccount }
        guard date <= now else { throw FinancialOperationError.futureDate }
        guard calendar.startOfDay(for: date) >= invoice.closingDate,
              invoice.installments.allSatisfy({ $0.purchase.date <= date }),
              invoice.card.invoices.filter({ $0.referenceMonth <= invoice.referenceMonth }).flatMap(\.refunds).allSatisfy({ $0.date <= date }) else { throw CreditCardError.openInvoice }
        let amount = try pending(invoice, asOf: date)
        guard amount > 0 else { throw CreditCardError.invalidInvoice }
        guard let available = try FinancialSummary.transferableBalance(of: account, on: date, now: now), available >= amount else { throw CreditCardError.insufficientBalance }
        let payment = CardInvoicePayment(invoice: invoice, account: account, amountInCents: amount, date: date)
        context.insert(payment)
        invoice.payment = payment
        try FinancialOperations.save(in: context)
    }

    static func total(_ invoice: CardInvoice, asOf date: Date = .distantFuture) throws -> Int64 {
        try FinancialSummary.cents(invoice.installments.filter { $0.purchase.date <= date }.reduce(Decimal.zero) { $0 + Decimal($1.amountInCents) }
            - invoice.refunds.filter { $0.date <= date }.reduce(Decimal.zero) { $0 + Decimal($1.amountInCents) })
    }
    static func pending(_ invoice: CardInvoice, asOf date: Date = Date()) throws -> Int64 {
        try balance(invoice, asOf: date).pending
    }
    static func debt(_ invoices: [CardInvoice], asOf date: Date = Date()) throws -> Int64 {
        try FinancialSummary.cents(invoices.reduce(Decimal.zero) { try $0 + Decimal(pending($1, asOf: date)) })
    }
    static func status(_ invoice: CardInvoice, now: Date = Date(), calendar: Calendar = .current) -> String {
        if let payment = invoice.payment, payment.date <= now { return "Paga" }
        if let total = try? total(invoice, asOf: now), total < 0 { return "Crédito para próximas faturas" }
        if let pending = try? pending(invoice, asOf: now), pending == 0 { return "Sem valor a pagar" }
        let today = calendar.startOfDay(for: now)
        if invoice.dueDate < today { return "Atrasada" }
        return today >= invoice.closingDate ? "Fechada" : "Aberta"
    }
}
