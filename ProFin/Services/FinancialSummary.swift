import Foundation

enum FinancialSummaryError: Error, Equatable {
    case amountOverflow
    case invalidMonth
}

struct MonthlySummary: Equatable {
    let incomeInCents: Int64
    let expenseInCents: Int64
    let resultInCents: Int64
}

@MainActor
enum FinancialSummary {
    // nil indica que falta o saldo inicial; zero é um saldo conhecido.
    static func balance(of account: FinancialAccount, asOf date: Date = Date()) throws -> Int64? {
        guard let total = balanceInDecimal(of: account, asOf: date) else { return nil }
        return try cents(total)
    }

    // O patrimônio exibido inclui apenas contas ativas; o histórico permanece intacto.
    static func netWorth(accounts: [FinancialAccount], asOf date: Date = Date()) throws -> Int64? {
        var total = Decimal.zero
        for account in accounts where account.isActive {
            guard let balance = balanceInDecimal(of: account, asOf: date) else { return nil }
            total += balance
        }
        return try cents(total)
    }

    // Dinheiro fora das caixinhas, incluindo contas antigas do tipo "outro".
    static func availableMoney(accounts: [FinancialAccount], asOf date: Date = Date()) throws -> Int64? {
        try netWorth(accounts: accounts.filter { $0.kind != .savingsBox }, asOf: date)
    }

    // Converte o saldo atual informado para a base já usada pelo histórico.
    // Não cria receita/despesa e não soma novamente lançamentos existentes.
    static func openingBalance(forCurrentBalance current: Int64, of account: FinancialAccount,
                               asOf date: Date = Date()) throws -> Int64 {
        try cents(Decimal(current) - movementsInDecimal(of: account, asOf: date))
    }

    // Limita uma transferência retroativa pelo menor saldo entre sua data e hoje.
    // Movimentos no mesmo instante são agrupados, sem depender da ordem do fetch.
    static func transferableBalance(
        of account: FinancialAccount, on date: Date, now: Date = Date()
    ) throws -> Int64? {
        guard var balance = balanceInDecimal(of: account, asOf: date) else { return nil }
        var minimum = balance
        var changes: [Date: Decimal] = [:]
        for entry in AccountHistory.entries(for: account, asOf: now) where entry.date > date {
            changes[entry.date, default: .zero] += entry.isIncoming ? Decimal(entry.amountInCents) : -Decimal(entry.amountInCents)
        }
        for date in changes.keys.sorted() {
            balance += changes[date] ?? .zero
            minimum = min(minimum, balance)
        }
        return try cents(minimum)
    }

    static func monthlySummary(
        transactions: [FinancialTransaction],
        monthContaining date: Date,
        installments: [CardInstallment] = [],
        refunds: [CardRefund] = [],
        calendar: Calendar = .current
    ) throws -> MonthlySummary {
        guard let month = calendar.dateInterval(of: .month, for: date) else {
            throw FinancialSummaryError.invalidMonth
        }
        var income = Decimal.zero
        var expense = Decimal.zero
        // Intervalo semiaberto: o primeiro instante do mês seguinte fica de fora.
        for transaction in transactions where transaction.date >= month.start && transaction.date < month.end {
            switch transaction.type {
            case .income: income += Decimal(transaction.amountInCents)
            case .expense: expense += Decimal(transaction.amountInCents)
            }
        }
        for installment in installments where installment.invoice.referenceMonth >= month.start
            && installment.invoice.referenceMonth < month.end && installment.purchase.date <= Date() {
            expense += Decimal(installment.amountInCents)
        }
        for refund in refunds where refund.invoice.referenceMonth >= month.start
            && refund.invoice.referenceMonth < month.end && refund.date <= Date() {
            expense -= Decimal(refund.amountInCents)
        }
        return try MonthlySummary(
            incomeInCents: cents(income), expenseInCents: cents(expense), resultInCents: cents(income - expense)
        )
    }

    private static func balanceInDecimal(of account: FinancialAccount, asOf date: Date) -> Decimal? {
        guard let openingBalance = account.openingBalanceInCents else { return nil }
        return Decimal(openingBalance) + movementsInDecimal(of: account, asOf: date)
    }

    private static func movementsInDecimal(of account: FinancialAccount, asOf date: Date) -> Decimal {
        var total = Decimal.zero
        for transaction in account.transactions where transaction.date <= date {
            switch transaction.type {
            case .income: total += Decimal(transaction.amountInCents)
            case .expense: total -= Decimal(transaction.amountInCents)
            }
        }
        for transfer in account.incomingTransfers where transfer.date <= date {
            total += Decimal(transfer.amountInCents)
        }
        for transfer in account.outgoingTransfers where transfer.date <= date {
            total -= Decimal(transfer.amountInCents)
        }
        for payment in account.cardPayments where payment.date <= date {
            total -= Decimal(payment.amountInCents)
        }
        return total
    }

    static func cents(_ amount: Decimal) throws -> Int64 {
        // Acumular em Decimal evita overflow intermediário dependente da ordem
        // dos lançamentos. Os valores persistidos e retornados continuam Int64.
        guard !amount.isNaN, amount >= Decimal(Int64.min), amount <= Decimal(Int64.max) else {
            throw FinancialSummaryError.amountOverflow
        }
        return NSDecimalNumber(decimal: amount).int64Value
    }
}
