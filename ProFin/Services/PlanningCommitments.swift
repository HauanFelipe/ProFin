import Foundation

struct PlanningCommitments {
    let recurring: [RecurringExpenseOccurrence]
    let invoices: [CardInvoice]
    let recurringInCents: Int64
    let cardInCents: Int64
    let missing: [String]

    @MainActor static func calculate(occurrences: [RecurringExpenseOccurrence], invoices: [CardInvoice],
                                     now: Date = Date(), calendar: Calendar = .current) throws -> Self {
        guard let end = calendar.dateInterval(of: .month, for: now)?.end else { throw FinancialSummaryError.invalidMonth }
        let recurring = occurrences.filter {
            $0.dueDate < end && $0.cardPurchase == nil && ($0.paymentTransaction.map { $0.date > now } ?? true)
        }.sorted { $0.dueDate < $1.dueDate }
        let pendingCards = try invoices.filter {
            guard $0.dueDate < end else { return false }
            return try CreditCardService.pending($0, asOf: now) > 0
        }
            .sorted { $0.dueDate < $1.dueDate }
        return try Self(recurring: recurring, invoices: pendingCards,
            recurringInCents: FinancialSummary.cents(recurring.reduce(Decimal.zero) { $0 + Decimal($1.expectedAmountInCents ?? 0) }),
            cardInCents: CreditCardService.debt(pendingCards, asOf: now),
            missing: recurring.filter { $0.expectedAmountInCents == nil }.map { "A cobrança \($0.title) não tem valor previsto." })
    }
}
