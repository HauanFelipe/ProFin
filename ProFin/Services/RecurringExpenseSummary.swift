import Foundation

enum RecurringStatus: String {
    case onCard = "No cartão"
    case pending = "Pendente"
    case paid = "Pago"
    case dueSoon = "Vencendo em breve"
    case overdue = "Atrasado"
}

enum RecurringSchedule {
    static let dueSoonDays = 3

    static func month(containing date: Date, calendar: Calendar) throws -> Date {
        guard let month = calendar.dateInterval(of: .month, for: date)?.start else {
            throw FinancialSummaryError.invalidMonth
        }
        return month
    }

    static func key(expenseID: UUID, month: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.era, .year, .month], from: month)
        return "\(expenseID.uuidString)/\(parts.era ?? 1)/\(parts.year ?? 0)/\(parts.month ?? 0)"
    }

    static func dueDate(day: Int, month: Date, calendar: Calendar) throws -> Date {
        let start = try self.month(containing: month, calendar: calendar)
        guard (1...31).contains(day), let days = calendar.range(of: .day, in: .month, for: start),
              let date = calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: start) else {
            throw FinancialSummaryError.invalidMonth
        }
        return date
    }
}

// Projeções são valores Swift, não Models: consultar um mês futuro não grava nada no banco.
struct RecurringCharge: Identifiable {
    let id: String
    let occurrenceID: UUID?
    let expenseID: UUID
    let title: String
    let categoryName: String
    let referenceMonth: Date
    let dueDate: Date
    let amountType: RecurringAmountType
    let expectedAmountInCents: Int64?
    let paidAmountInCents: Int64?

    var cardAmountInCents: Int64? = nil

    var isProjection: Bool { occurrenceID == nil }

    func status(asOf now: Date, calendar: Calendar = .current) -> RecurringStatus {
        if cardAmountInCents != nil { return .onCard }
        if paidAmountInCents != nil { return .paid }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)
        if due < today { return .overdue }
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? Int.max
        return days <= RecurringSchedule.dueSoonDays ? .dueSoon : .pending
    }
}

struct RecurringMonthlySummary {
    let knownExpectedInCents: Int64
    let paidInCents: Int64
    let knownPendingInCents: Int64
    let missingEstimateCount: Int
    let pendingWithoutEstimateCount: Int
    let incomeInCents: Int64
    let committedIncomePercentage: Decimal?
    let unpaidCharges: [RecurringCharge]

    var expectedInCents: Int64? { missingEstimateCount == 0 ? knownExpectedInCents : nil }
    var pendingInCents: Int64? { pendingWithoutEstimateCount == 0 ? knownPendingInCents : nil }
}

@MainActor
enum RecurringExpenseSummary {
    static func charges(
        expenses: [RecurringExpense], occurrences: [RecurringExpenseOccurrence],
        monthContaining date: Date, now: Date = Date(), calendar: Calendar = .current
    ) throws -> [RecurringCharge] {
        let month = try RecurringSchedule.month(containing: date, calendar: calendar)
        let current = try RecurringSchedule.month(containing: now, calendar: calendar)
        var charges = occurrences.filter {
            calendar.isDate($0.referenceMonth, equalTo: month, toGranularity: .month)
        }.map { occurrence in
            RecurringCharge(
                id: occurrence.occurrenceKey, occurrenceID: occurrence.id,
                expenseID: occurrence.recurringExpense.id, title: occurrence.title,
                categoryName: occurrence.category.name, referenceMonth: occurrence.referenceMonth,
                dueDate: occurrence.dueDate, amountType: occurrence.amountType,
                expectedAmountInCents: occurrence.expectedAmountInCents,
                paidAmountInCents: occurrence.paymentTransaction?.amountInCents,
                cardAmountInCents: occurrence.cardPurchase?.amountInCents
            )
        }
        if month > current {
            let existing = Set(charges.map(\.id))
            for expense in expenses where expense.isActive && expense.startMonth <= month {
                let key = RecurringSchedule.key(expenseID: expense.id, month: month, calendar: calendar)
                guard !existing.contains(key) else { continue }
                charges.append(RecurringCharge(
                    id: key, occurrenceID: nil, expenseID: expense.id, title: expense.title,
                    categoryName: expense.category.name, referenceMonth: month,
                    dueDate: try RecurringSchedule.dueDate(day: expense.dueDay, month: month, calendar: calendar),
                    amountType: expense.amountType, expectedAmountInCents: expense.expectedAmountInCents,
                    paidAmountInCents: nil
                ))
            }
        }
        return charges.sorted { $0.dueDate == $1.dueDate ? $0.id < $1.id : $0.dueDate < $1.dueDate }
    }

    static func monthlySummary(
        charges: [RecurringCharge], transactions: [FinancialTransaction],
        monthContaining month: Date, calendar: Calendar = .current
    ) throws -> RecurringMonthlySummary {
        let monthly = charges.filter { calendar.isDate($0.referenceMonth, equalTo: month, toGranularity: .month) }
        let income = try FinancialSummary.monthlySummary(
            transactions: transactions, monthContaining: month, calendar: calendar
        ).incomeInCents
        let expected = try FinancialSummary.cents(monthly.reduce(Decimal.zero) {
            $0 + Decimal($1.expectedAmountInCents ?? 0)
        })
        let paid = try FinancialSummary.cents(monthly.reduce(Decimal.zero) {
            $0 + Decimal($1.paidAmountInCents ?? 0)
        })
        let unpaid = monthly.filter { $0.paidAmountInCents == nil && $0.cardAmountInCents == nil }
        let pending = try FinancialSummary.cents(unpaid.reduce(Decimal.zero) {
            $0 + Decimal($1.expectedAmountInCents ?? 0)
        })
        let missing = monthly.filter { $0.expectedAmountInCents == nil }.count
        return RecurringMonthlySummary(
            knownExpectedInCents: expected, paidInCents: paid, knownPendingInCents: pending,
            missingEstimateCount: missing,
            pendingWithoutEstimateCount: unpaid.filter { $0.expectedAmountInCents == nil }.count,
            incomeInCents: income,
            committedIncomePercentage: committedPercentage(expectedInCents: missing == 0 ? expected : nil,
                                                          incomeInCents: income),
            unpaidCharges: unpaid.sorted { $0.dueDate < $1.dueDate }
        )
    }

    // Única regra de comprometimento, também disponível para o futuro Dashboard.
    static func committedPercentage(expectedInCents: Int64?, incomeInCents: Int64) -> Decimal? {
        guard let expectedInCents, incomeInCents > 0 else { return nil }
        return Decimal(expectedInCents) / Decimal(incomeInCents) * 100
    }
}
