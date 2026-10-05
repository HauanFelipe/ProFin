import Foundation
import SwiftData

@MainActor
enum SavingsYieldOperations {
    // Detecta alterações no histórico sem persistir rendimentos ou saldos derivados.
    static func ledgerSignature(for account: FinancialAccount) -> String {
        let transactions = account.transactions.map {
            "t/\($0.id)/\($0.date.timeIntervalSince1970)/\($0.type)/\($0.amountInCents)"
        }
        let transfers = (account.incomingTransfers + account.outgoingTransfers).map {
            "x/\($0.id)/\($0.date.timeIntervalSince1970)/\($0.amountInCents)/\($0.sourceAccount.id)/\($0.destinationAccount.id)"
        }
        let payments = account.cardPayments.map { "p/\($0.id)/\($0.amountInCents)/\($0.date.timeIntervalSince1970)" }
        return ([account.openingBalanceInCents.map(String.init) ?? "unknown"] + (transactions + transfers + payments).sorted()).joined(separator: "|")
    }

    static func save(account: FinancialAccount, lots: [SavingsYieldLotInput], annualCDIBasisPoints: Int,
                     cdiPercentageBasisPoints: Int, referenceDate: Date, businessDays: Int,
                     in context: ModelContext) throws {
        guard account.modelContext === context, account.kind == .savingsBox else { throw FinancialOperationError.differentContext }
        _ = try SavingsYieldCalculator.calculate(lots: lots, annualCDIBasisPoints: annualCDIBasisPoints,
            cdiPercentageBasisPoints: cdiPercentageBasisPoints, referenceDate: referenceDate, businessDays: businessDays)
        let id = account.id
        let existing = try context.fetch(FetchDescriptor<SavingsYieldConfiguration>(predicate: #Predicate { $0.accountID == id })).first
        let configuration = existing ?? SavingsYieldConfiguration(accountID: id,
            annualCDIBasisPoints: annualCDIBasisPoints, cdiPercentageBasisPoints: cdiPercentageBasisPoints,
            referenceDate: referenceDate, businessDays: businessDays, ledgerSignature: ledgerSignature(for: account))
        if existing == nil { context.insert(configuration) }
        configuration.annualCDIBasisPoints = annualCDIBasisPoints
        configuration.cdiPercentageBasisPoints = cdiPercentageBasisPoints
        configuration.referenceDate = referenceDate
        configuration.businessDays = businessDays
        configuration.ledgerSignature = ledgerSignature(for: account)
        let oldLots = configuration.lots
        configuration.lots = lots.map(SavingsYieldLot.init)
        for lot in oldLots { context.delete(lot) }
        try FinancialOperations.save(in: context)
    }
}
