import Testing
@testable import ProFin

@MainActor
struct MoneyTests {
    @Test(arguments: [
        ("0,01", Int64(1)),
        ("25,9", Int64(2590)),
        ("650", Int64(65000)),
        ("1.234,56", Int64(123456)),
        (" 2500,00 ", Int64(250000)),
        ("92.233.720.368.547.758,07", Int64.max)
    ])
    func convertsReaisWithoutRounding(input: String, expected: Int64) {
        #expect(Money.cents(from: input) == expected)
    }

    @Test(arguments: [
        "", " ", "0", "0,00", "-10", "+10", "1,234", "12.34", "25.90",
        "1.00,00", "1,2,3", "1e3", "R$ 20", "abc", "10,",
        "92233720368547758,08", "92233720368547759", "99999999999999999999999"
    ])
    func rejectsInvalidOrOverflowingAmounts(input: String) {
        #expect(Money.cents(from: input) == nil)
    }

    @Test
    func formatsReaisWithTwoDecimalPlaces() {
        // Espaços usados pelo formatador podem ser comuns ou inquebráveis.
        let formatted = Money.formatted(123456).filter { !$0.isWhitespace }
        #expect(formatted == "R$1.234,56")
        #expect(Money.formatted(1).filter { !$0.isWhitespace } == "R$0,01")
    }

    @Test(arguments: [Int64(1), 2590, 65000, Int64.max])
    func editableAmountPreservesEveryCent(amount: Int64) {
        #expect(Money.cents(from: Money.input(amount)) == amount)
    }
}
