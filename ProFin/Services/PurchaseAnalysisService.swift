import Foundation

struct PurchaseAnalysis {
    let cashInCents: Int64?
    let goalBoxInCents: Int64?
    let pendingInCents: Int64
    let pendingBills: [RecurringExpenseOccurrence]
    let cardPendingInCents: Int64
    let pendingInvoices: [CardInvoice]
    let monthly: MonthlySummary
    let remainingInCents: Int64?
    let missingInformation: [String]

    var explanation: String {
        guard missingInformation.isEmpty, let remainingInCents else {
            return "Análise incompleta. Confira as informações abaixo."
        }
        if remainingInCents < 0 {
            // Decimal evita negar Int64.min.
            let missing = (abs(Decimal(remainingInCents)) / 100).formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
            return "Faltam \(missing) para cobrir a compra, os compromissos e a margem informados."
        }
        if remainingInCents == 0 { return "A compra cabe no cálculo, mas não sobra valor além da margem escolhida." }
        return "Após a compra, sobrariam \(Money.formatted(remainingInCents)) além da margem escolhida."
    }
}

enum PurchaseAnalysisError: LocalizedError {
    case invalidValues, archivedGoal
    var errorDescription: String? {
        switch self {
        case .invalidValues: "Informe uma compra maior que zero e valores não negativos nos demais campos."
        case .archivedGoal: "Reative a meta antes de analisar a compra."
        }
    }
}

@MainActor
enum PurchaseAnalysisService {
    static func analyze(goal: Goal, accounts: [FinancialAccount], occurrences: [RecurringExpenseOccurrence],
                        transactions: [FinancialTransaction], invoices: [CardInvoice] = [], purchaseInCents: Int64,
                        extraExpensesInCents: Int64, marginInCents: Int64, costsInCents: Int64,
                        now: Date = Date(), calendar: Calendar = .current) throws -> PurchaseAnalysis {
        guard !goal.isArchived else { throw PurchaseAnalysisError.archivedGoal }
        guard purchaseInCents > 0, extraExpensesInCents >= 0, marginInCents >= 0, costsInCents >= 0 else {
            throw PurchaseAnalysisError.invalidValues
        }
        var missing: [String] = []
        let spendableAccounts = accounts.filter { $0.isActive && $0.kind != .savingsBox && !$0.isEmergencyReserve }
        let cash = try FinancialSummary.netWorth(accounts: spendableAccounts, asOf: now)
        for account in spendableAccounts where account.openingBalanceInCents == nil {
            missing.append("Informe o dinheiro na conta \(account.name).")
        }
        var boxBalance: Int64? = 0
        if let box = goal.savingsAccount {
            if !box.isActive || box.kind != .savingsBox || box.isEmergencyReserve {
                missing.append("A caixinha da meta está inativa ou protegida. Confira o vínculo.")
                boxBalance = nil
            } else {
                boxBalance = try FinancialSummary.balance(of: box, asOf: now)
                if boxBalance == nil { missing.append("Informe o dinheiro na caixinha \(box.name).") }
            }
        }
        let commitments = try PlanningCommitments.calculate(occurrences: occurrences, invoices: invoices, now: now, calendar: calendar)
        let pending = commitments.recurring
        let pendingAmount = Decimal(commitments.recurringInCents) + Decimal(commitments.cardInCents)
        missing += commitments.missing
        let monthly = try FinancialSummary.monthlySummary(transactions: transactions.filter { $0.date <= now },
                                                         monthContaining: now, installments: invoices.flatMap(\.installments), refunds: invoices.flatMap(\.refunds), calendar: calendar)
        var remaining: Int64?
        if missing.isEmpty, let cash, let boxBalance {
            remaining = try FinancialSummary.cents(Decimal(cash) + Decimal(boxBalance) - pendingAmount
                - Decimal(extraExpensesInCents) - Decimal(marginInCents) - Decimal(costsInCents) - Decimal(purchaseInCents))
        }
        return try PurchaseAnalysis(cashInCents: cash, goalBoxInCents: boxBalance,
            pendingInCents: FinancialSummary.cents(pendingAmount), pendingBills: pending,
            cardPendingInCents: commitments.cardInCents, pendingInvoices: commitments.invoices,
            monthly: monthly, remainingInCents: remaining, missingInformation: missing)
    }
}
