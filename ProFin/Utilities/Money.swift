import Foundation

enum Money {
    // Texto editável em reais, sem símbolo nem conversão por Double.
    nonisolated static func input(_ cents: Int64) -> String {
        let fraction = cents.magnitude % 100
        return "\(cents < 0 ? "-" : "")\(cents.magnitude / 100),\(fraction < 10 ? "0" : "")\(fraction)"
    }

    nonisolated static func cents(from text: String) -> Int64? {
        guard let amount = magnitude(from: text), amount > 0, amount <= UInt64(Int64.max) else { return nil }
        return Int64(amount)
    }

    // Saldos iniciais podem ser zero ou negativos. Transferências continuam positivas.
    nonisolated static func balanceCents(from text: String) -> Int64? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let negative = input.hasPrefix("-")
        let digits = negative ? String(input.dropFirst()) : input
        guard let amount = magnitude(from: digits) else { return nil }
        if negative && amount == UInt64(Int64.max) + 1 { return Int64.min }
        guard amount <= UInt64(Int64.max) else { return nil }
        return negative ? -Int64(amount) : Int64(amount)
    }

    private nonisolated static func magnitude(from text: String) -> UInt64? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Aceita reais com vírgula decimal e agrupamento opcional: 1234,56 ou 1.234,56.
        let pattern = #"^(?:[0-9]+|[0-9]{1,3}(?:\.[0-9]{3})+)(?:,[0-9]{1,2})?$"#
        guard input.range(of: pattern, options: .regularExpression) != nil else { return nil }

        let parts = input.replacingOccurrences(of: ".", with: "").split(separator: ",")
        guard let reais = UInt64(parts[0]) else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let centavos = UInt64(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0

        let (whole, multiplyOverflow) = reais.multipliedReportingOverflow(by: 100)
        let (amount, additionOverflow) = whole.addingReportingOverflow(centavos)
        guard !multiplyOverflow, !additionOverflow else { return nil }
        return amount
    }

    nonisolated static func formatted(_ amountInCents: Int64) -> String {
        let amount = Decimal(amountInCents) / 100
        return amount.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }
}
