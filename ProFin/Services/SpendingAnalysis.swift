import Foundation

struct SpendingCategory: Identifiable {
    let id: UUID
    let name: String
    let amount: Int64
    let previousAmount: Int64
    let count: Int
    let share: Double
    var change: Int64 { amount - previousAmount }
    var percentageChange: Double? {
        previousAmount > 0 ? Double(change) / Double(previousAmount) : nil
    }
}

struct SpendingAnalysisResult {
    let total: Int64
    let previousTotal: Int64
    let refunded: Int64
    let essential: Int64
    let nonEssential: Int64
    let unclassified: Int64
    let categories: [SpendingCategory]
    var largestIncrease: SpendingCategory? {
        categories.filter { $0.change > 0 }.sorted {
            $0.change == $1.change ? $0.name < $1.name : $0.change > $1.change
        }.first
    }
}

@MainActor
enum SpendingAnalysis {
    private struct Entry {
        let categoryID: UUID
        let categoryName: String
        let amount: Int64
        let classification: ExpenseClassification?
        let monthDate: Date
    }

    static func calculate(transactions: [FinancialTransaction], installments: [CardInstallment],
                          month: Date, refunds: [CardRefund] = [], now: Date = Date(), calendar: Calendar = .current) throws -> SpendingAnalysisResult {
        guard let current = calendar.dateInterval(of: .month, for: month),
              let previousDate = calendar.date(byAdding: .month, value: -1, to: current.start),
              let previous = calendar.dateInterval(of: .month, for: previousDate) else {
            throw FinancialSummaryError.invalidMonth
        }
        var entries = transactions.filter { $0.type == .expense }.map {
            Entry(categoryID: $0.category.id, categoryName: $0.category.name, amount: $0.amountInCents,
                  classification: $0.classification, monthDate: $0.date)
        }
        // A parcela pertence ao mês da fatura, independentemente do pagamento.
        entries += installments.filter { $0.purchase.date <= now }.map {
            Entry(categoryID: $0.purchase.category.id, categoryName: $0.purchase.category.name,
                  amount: $0.amountInCents, classification: $0.purchase.classification, monthDate: $0.invoice.referenceMonth)
        }
        entries += refunds.filter { $0.date <= now }.map {
            Entry(categoryID: $0.purchase.category.id, categoryName: $0.purchase.category.name,
                  amount: -$0.amountInCents, classification: $0.purchase.classification, monthDate: $0.invoice.referenceMonth)
        }
        let selected = entries.filter { $0.monthDate >= current.start && $0.monthDate < current.end }
        let earlier = entries.filter { $0.monthDate >= previous.start && $0.monthDate < previous.end }
        func sum(_ entries: [Entry]) throws -> Int64 {
            try FinancialSummary.cents(entries.reduce(Decimal.zero) { $0 + Decimal($1.amount) })
        }
        let total = try sum(selected)
        let currentGroups = Dictionary(grouping: selected, by: \.categoryID)
        let previousGroups = Dictionary(grouping: earlier, by: \.categoryID)
        let positiveTotal = try FinancialSummary.cents(try currentGroups.values.reduce(Decimal.zero) { try $0 + Decimal(max(0, sum($1))) })
        _ = try FinancialSummary.cents(Decimal(total) - Decimal(sum(earlier)))
        let categories = try Set(currentGroups.keys).union(previousGroups.keys).map { id in
            let items = currentGroups[id] ?? []
            let old = previousGroups[id] ?? []
            let amount = try sum(items)
            _ = try FinancialSummary.cents(Decimal(amount) - Decimal(sum(old)))
            return SpendingCategory(id: id, name: (items.first ?? old.first)!.categoryName,
                amount: amount, previousAmount: try sum(old), count: items.filter { $0.amount > 0 }.count,
                share: positiveTotal > 0 ? Double(max(0, amount)) / Double(positiveTotal) : 0)
        }.sorted {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
        return try SpendingAnalysisResult(total: total, previousTotal: sum(earlier),
            refunded: FinancialSummary.cents(selected.filter { $0.amount < 0 }.reduce(Decimal.zero) { $0 - Decimal($1.amount) }),
            essential: sum(selected.filter { $0.classification == .essential }),
            nonEssential: sum(selected.filter { $0.classification == .nonEssential }),
            unclassified: sum(selected.filter { $0.classification == nil }), categories: categories)
    }
}
