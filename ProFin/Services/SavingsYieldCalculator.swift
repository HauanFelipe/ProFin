import Foundation

struct SavingsYieldLotInput: Identifiable {
    var id = UUID()
    var applicationDate: Date
    var principalInCents: Int64
    var grossBalanceInCents: Int64
}

struct SavingsYieldResult {
    let redemptionDate: Date
    let principalInCents: Int64
    let initialGrossInCents: Int64
    let periodYieldInCents: Int64
    let finalGrossInCents: Int64
    let iofInCents: Int64
    let incomeTaxInCents: Int64
    let finalNetInCents: Int64
}

enum SavingsYieldError: LocalizedError, Equatable {
    case invalidRates, invalidDates, invalidBusinessDays, invalidLot, noLots, amountOverflow

    var errorDescription: String? {
        switch self {
        case .invalidRates: "Informe o CDI anual entre 0% e 100% e o percentual da caixinha entre 0% e 300%."
        case .invalidDates: "A data-base não pode ser futura, e os aportes devem ser anteriores ou iguais a ela."
        case .invalidBusinessDays: "Confira a quantidade de dias de rendimento até o fim do mês."
        case .invalidLot: "Cada aporte precisa de principal positivo e saldo bruto maior ou igual ao principal ainda investido."
        case .noLots: "Informe pelo menos um aporte para calcular a projeção."
        case .amountOverflow: "Os valores ultrapassam o limite permitido para o cálculo."
        }
    }
}

// Simulação de RDB: CDI constante, sem novos aportes, retiradas, vencimentos ou taxas.
// IR: Lei 11.033, art. 1º. IOF: tabela regressiva; IR incide após o IOF.
@MainActor
enum SavingsYieldCalculator {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return value
    }

    static func monthEnd(containing date: Date) throws -> Date {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let end = calendar.date(byAdding: .day, value: -1, to: month.end) else {
            throw SavingsYieldError.invalidDates
        }
        return end
    }

    // Sugestão, não calendário bancário: o usuário desconta feriados no formulário.
    static func suggestedBusinessDays(from date: Date) -> Int {
        guard let end = try? monthEnd(containing: date) else { return 0 }
        var day = calendar.startOfDay(for: date)
        var count = 0
        while day <= end {
            if !calendar.isDateInWeekend(day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    static func incomeTaxBasisPoints(days: Int) -> Int {
        switch days {
        case ...180: 2250
        case ...360: 2000
        case ...720: 1750
        default: 1500
        }
    }

    static func iofPercent(days: Int) -> Int {
        // Posição zero: sem permanência, nenhum ganho líquido é estimado.
        let table = [100, 96, 93, 90, 86, 83, 80, 76, 73, 70, 66, 63, 60, 56, 53,
                     50, 46, 43, 40, 36, 33, 30, 26, 23, 20, 16, 13, 10, 6, 3]
        return days >= 30 ? 0 : table[max(0, days)]
    }

    static func calculate(lots: [SavingsYieldLotInput], annualCDIBasisPoints: Int,
                          cdiPercentageBasisPoints: Int, referenceDate: Date,
                          businessDays: Int, now: Date = Date()) throws -> SavingsYieldResult {
        guard (0...10_000).contains(annualCDIBasisPoints), (0...30_000).contains(cdiPercentageBasisPoints) else {
            throw SavingsYieldError.invalidRates
        }
        let start = calendar.startOfDay(for: referenceDate)
        guard start <= calendar.startOfDay(for: now) else { throw SavingsYieldError.invalidDates }
        guard !lots.isEmpty else { throw SavingsYieldError.noLots }
        let end = try monthEnd(containing: referenceDate)
        guard (0...suggestedBusinessDays(from: referenceDate)).contains(businessDays) else {
            throw SavingsYieldError.invalidBusinessDays
        }
        // O percentual do CDI é aplicado à taxa diária, não diretamente à anual.
        let dailyCDI = pow(1 + Double(annualCDIBasisPoints) / 10_000, 1.0 / 252) - 1
        let factor = pow(1 + dailyCDI * Double(cdiPercentageBasisPoints) / 10_000, Double(businessDays))
        guard factor.isFinite else { throw SavingsYieldError.amountOverflow }
        var principal = Decimal.zero, initial = Decimal.zero, final = Decimal.zero
        var iof = Decimal.zero, incomeTax = Decimal.zero
        for lot in lots {
            guard lot.principalInCents > 0, lot.grossBalanceInCents >= lot.principalInCents else {
                throw SavingsYieldError.invalidLot
            }
            let application = calendar.startOfDay(for: lot.applicationDate)
            guard application <= start else { throw SavingsYieldError.invalidDates }
            let days = calendar.dateComponents([.day], from: application, to: end).day ?? 0
            let gross = rounded(Decimal(lot.grossBalanceInCents) * Decimal(factor))
            let earnings = max(0, gross - Decimal(lot.principalInCents))
            let lotIOF = rounded(earnings * Decimal(iofPercent(days: days)) / 100)
            let lotIR = rounded((earnings - lotIOF) * Decimal(incomeTaxBasisPoints(days: days)) / 10_000)
            principal += Decimal(lot.principalInCents)
            initial += Decimal(lot.grossBalanceInCents)
            final += gross
            iof += lotIOF
            incomeTax += lotIR
        }
        return try SavingsYieldResult(redemptionDate: end, principalInCents: cents(principal),
            initialGrossInCents: cents(initial), periodYieldInCents: cents(final - initial),
            finalGrossInCents: cents(final), iofInCents: cents(iof), incomeTaxInCents: cents(incomeTax),
            finalNetInCents: cents(final - iof - incomeTax))
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var original = value
        var result = Decimal.zero
        NSDecimalRound(&result, &original, 0, .plain)
        return result
    }

    private static func cents(_ value: Decimal) throws -> Int64 {
        guard !value.isNaN, value >= 0, value <= Decimal(Int64.max) else { throw SavingsYieldError.amountOverflow }
        return NSDecimalNumber(decimal: value).int64Value
    }
}
