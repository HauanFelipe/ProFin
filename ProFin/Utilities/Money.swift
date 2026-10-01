import Foundation

enum Money {
    // Texto editável em reais, sem símbolo nem conversão por Double.
    static func input(_ cents: Int64) -> String {
        let fraction = cents % 100
        return "\(cents / 100),\(fraction < 10 ? "0" : "")\(fraction)"
    }

    static func cents(from text: String) -> Int64? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Aceita reais com vírgula decimal e agrupamento opcional: 1234,56 ou 1.234,56.
        let pattern = #"^(?:[0-9]+|[0-9]{1,3}(?:\.[0-9]{3})+)(?:,[0-9]{1,2})?$"#
        guard input.range(of: pattern, options: .regularExpression) != nil else { return nil }

        let parts = input.replacingOccurrences(of: ".", with: "").split(separator: ",")
        guard let reais = Int64(parts[0]) else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let centavos = Int64(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0

        let (whole, multiplyOverflow) = reais.multipliedReportingOverflow(by: 100)
        let (amount, additionOverflow) = whole.addingReportingOverflow(centavos)
        guard !multiplyOverflow, !additionOverflow, amount > 0 else { return nil }
        return amount
    }

    static func formatted(_ amountInCents: Int64) -> String {
        let amount = Decimal(amountInCents) / 100
        return amount.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }
}
