import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct SavingsYieldTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        SavingsYieldCalculator.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test(arguments: [(10_000, Int64(100_797), Int64(179), Int64(100_618)),
                      (11_500, Int64(100_918), Int64(207), Int64(100_711)),
                      (12_000, Int64(100_958), Int64(216), Int64(100_742))])
    func projectsTheThreeRates(_ example: (Int, Int64, Int64, Int64)) throws {
        // 10% a.a., 21 dias: valores de referência calculados com precisão decimal de 40 dígitos.
        let result = try SavingsYieldCalculator.calculate(
            lots: [SavingsYieldLotInput(applicationDate: date(2025, 12, 1), principalInCents: 100_000, grossBalanceInCents: 100_000)],
            annualCDIBasisPoints: 1_000, cdiPercentageBasisPoints: example.0,
            referenceDate: date(2026, 1, 1), businessDays: 21, now: date(2026, 1, 1))
        #expect(result.finalGrossInCents == example.1)
        #expect(result.incomeTaxInCents == example.2)
        #expect(result.finalNetInCents == example.3)
        #expect(result.periodYieldInCents == example.1 - 100_000)
        #expect(result.iofInCents == 0)
        #expect(result.redemptionDate == date(2026, 1, 31))
    }

    @Test(arguments: [(180, 2250), (181, 2000), (360, 2000), (361, 1750), (720, 1750), (721, 1500)])
    func incomeTaxUsesCalendarAgeOfEachLot(_ example: (Int, Int)) throws {
        let end = date(2026, 1, 31)
        let application = SavingsYieldCalculator.calendar.date(byAdding: .day, value: -example.0, to: end)!
        let result = try SavingsYieldCalculator.calculate(
            lots: [SavingsYieldLotInput(applicationDate: application, principalInCents: 100_000, grossBalanceInCents: 110_000)],
            annualCDIBasisPoints: 0, cdiPercentageBasisPoints: 10_000,
            referenceDate: end, businessDays: 0, now: end)
        #expect(result.incomeTaxInCents == Int64(example.1))
        #expect(result.periodYieldInCents == 0)
        #expect(result.iofInCents == 0)
        #expect(result.finalNetInCents == 110_000 - Int64(example.1))
    }

    @Test(arguments: [(0, 100), (1, 96), (15, 50), (29, 3), (30, 0), (31, 0)])
    func iofComesBeforeIncomeTax(_ example: (Int, Int)) throws {
        let end = date(2026, 1, 31)
        let application = SavingsYieldCalculator.calendar.date(byAdding: .day, value: -example.0, to: end)!
        let result = try SavingsYieldCalculator.calculate(
            lots: [SavingsYieldLotInput(applicationDate: application, principalInCents: 100_000, grossBalanceInCents: 140_000)],
            annualCDIBasisPoints: 0, cdiPercentageBasisPoints: 10_000,
            referenceDate: end, businessDays: 0, now: end)
        let iof = Int64(400 * example.1)
        #expect(result.iofInCents == iof)
        #expect(result.incomeTaxInCents == (40_000 - iof) * 225 / 1000)
        #expect(result.finalNetInCents >= result.principalInCents)
    }

    @Test
    func differentLotAgesAreNotBlended() throws {
        let result = try SavingsYieldCalculator.calculate(lots: [
            SavingsYieldLotInput(applicationDate: date(2026, 1, 30), principalInCents: 100_000, grossBalanceInCents: 110_000),
            SavingsYieldLotInput(applicationDate: date(2023, 1, 1), principalInCents: 100_000, grossBalanceInCents: 110_000)
        ], annualCDIBasisPoints: 0, cdiPercentageBasisPoints: 12_000,
            referenceDate: date(2026, 1, 31), businessDays: 0, now: date(2026, 1, 31))
        #expect(result.iofInCents == 9600)
        #expect(result.incomeTaxInCents == 90 + 1500)
        #expect(result.finalNetInCents == 220_000 - 9600 - 1590)
        #expect(result.principalInCents == 200_000)
        #expect(result.periodYieldInCents == 0)
    }

    @Test
    func businessDaySuggestionAndMonthEndIncludeLeapYear() throws {
        #expect(try SavingsYieldCalculator.monthEnd(containing: date(2024, 2, 1)) == date(2024, 2, 29))
        #expect(SavingsYieldCalculator.suggestedBusinessDays(from: date(2026, 1, 1)) == 22)
        #expect(SavingsYieldCalculator.suggestedBusinessDays(from: date(2026, 1, 30)) == 1)
        #expect(SavingsYieldCalculator.suggestedBusinessDays(from: date(2026, 1, 31)) == 0)
    }

    @Test
    func invalidInputsAndOverflowFailClearly() throws {
        let reference = date(2026, 1, 1)
        let valid = SavingsYieldLotInput(applicationDate: reference, principalInCents: 100, grossBalanceInCents: 100)
        func calculate(_ lots: [SavingsYieldLotInput], annual: Int = 1000, percentage: Int = 10_000, days: Int = 21) throws {
            _ = try SavingsYieldCalculator.calculate(lots: lots, annualCDIBasisPoints: annual,
                cdiPercentageBasisPoints: percentage, referenceDate: reference, businessDays: days, now: reference)
        }
        #expect(throws: SavingsYieldError.noLots) { try calculate([]) }
        #expect(throws: SavingsYieldError.invalidRates) { try calculate([valid], annual: -1) }
        #expect(throws: SavingsYieldError.invalidRates) { try calculate([valid], percentage: 30_001) }
        #expect(throws: SavingsYieldError.invalidBusinessDays) { try calculate([valid], days: 23) }
        #expect(throws: SavingsYieldError.invalidBusinessDays) { try calculate([valid], days: -1) }
        #expect(throws: SavingsYieldError.invalidLot) {
            try calculate([SavingsYieldLotInput(applicationDate: reference, principalInCents: 100, grossBalanceInCents: 99)])
        }
        #expect(throws: SavingsYieldError.invalidDates) {
            try calculate([SavingsYieldLotInput(applicationDate: date(2026, 1, 2), principalInCents: 100, grossBalanceInCents: 100)])
        }
        #expect(throws: SavingsYieldError.amountOverflow) {
            try calculate([SavingsYieldLotInput(applicationDate: reference, principalInCents: Int64.max, grossBalanceInCents: Int64.max)])
        }
    }

    @Test
    func configurationReopensWithoutChangingFinancialBalancesAndReplacesLots() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ProFin.store")
        let accountID = UUID()
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let account = FinancialAccount(id: accountID, name: "Turbo 120%", kind: .savingsBox, openingBalanceInCents: 100_000)
            context.insert(account)
            try context.save()
            for principal: Int64 in [100_000, 90_000] {
                try SavingsYieldOperations.save(account: account,
                    lots: [SavingsYieldLotInput(applicationDate: date(2025, 12, 1), principalInCents: principal, grossBalanceInCents: 100_000)],
                    annualCDIBasisPoints: 1000, cdiPercentageBasisPoints: 12_000,
                    referenceDate: date(2026, 1, 1), businessDays: 20, in: context)
            }
            #expect(try FinancialSummary.balance(of: account) == 100_000)
            #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldConfiguration>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldLot>()) == 1)
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first { $0.id == accountID })
            let saved = try #require(context.fetch(FetchDescriptor<SavingsYieldConfiguration>()).first)
            #expect(saved.accountID == accountID)
            #expect(saved.cdiPercentageBasisPoints == 12_000)
            #expect(saved.annualCDIBasisPoints == 1000)
            #expect(saved.businessDays == 20)
            #expect(saved.lots.count == 1)
            #expect(saved.lots.first?.principalInCents == 90_000)
            #expect(saved.ledgerSignature == SavingsYieldOperations.ledgerSignature(for: account))
            let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
            try FinancialOperations.recordTransaction(title: "Novo aporte", amountInCents: 500, date: date(2026, 1, 3),
                category: category, type: .income, account: account, in: context)
            #expect(saved.ledgerSignature != SavingsYieldOperations.ledgerSignature(for: account))
            #expect(try FinancialSummary.balance(of: account) == 100_500)
        }
    }

    @Test
    func v4MigrationAddsNoInventedRatesOrDeposits() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ProFin.store")
        let id = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: ProFinSchemaV4.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            container.mainContext.insert(ProFinSchemaV4.FinancialAccount(id: id, name: "Minha reserva", kind: .savingsBox, openingBalanceInCents: 150_000))
            try container.mainContext.save()
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
            #expect(account.id == id)
            #expect(account.name == "Minha reserva")
            #expect(try FinancialSummary.balance(of: account) == 150_000)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldConfiguration>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldLot>()) == 0)
        }
    }
}
