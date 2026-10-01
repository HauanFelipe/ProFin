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

    // Recebe todas as contas, inclusive arquivadas. Não soma apenas as ativas.
    static func netWorth(accounts: [FinancialAccount], asOf date: Date = Date()) throws -> Int64? {
        var total = Decimal.zero
        for account in accounts {
            guard let balance = balanceInDecimal(of: account, asOf: date) else { return nil }
            total += balance
        }
        return try cents(total)
    }

    static func monthlySummary(
        transactions: [FinancialTransaction],
        monthContaining date: Date,
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
        return try MonthlySummary(
            incomeInCents: cents(income), expenseInCents: cents(expense), resultInCents: cents(income - expense)
        )
    }

    private static func balanceInDecimal(of account: FinancialAccount, asOf date: Date) -> Decimal? {
        guard let openingBalance = account.openingBalanceInCents else { return nil }
        var total = Decimal(openingBalance)
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
