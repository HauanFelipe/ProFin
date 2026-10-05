import Foundation
import SwiftData

typealias SavingsYieldConfiguration = ProFinSchemaV9.SavingsYieldConfiguration
typealias SavingsYieldLot = ProFinSchemaV9.SavingsYieldLot

extension ProFinSchemaV9 {
// Uma posição informada para simulação. Não substitui o histórico financeiro.
@Model
final class SavingsYieldConfiguration {
    @Attribute(.unique) var accountID: UUID
    var annualCDIBasisPoints: Int
    var cdiPercentageBasisPoints: Int
    var referenceDate: Date
    var businessDays: Int
    var ledgerSignature: String
    @Relationship(deleteRule: .cascade) var lots: [SavingsYieldLot] = []

    init(accountID: UUID, annualCDIBasisPoints: Int, cdiPercentageBasisPoints: Int,
         referenceDate: Date, businessDays: Int, ledgerSignature: String) {
        self.accountID = accountID
        self.annualCDIBasisPoints = annualCDIBasisPoints
        self.cdiPercentageBasisPoints = cdiPercentageBasisPoints
        self.referenceDate = referenceDate
        self.businessDays = businessDays
        self.ledgerSignature = ledgerSignature
    }
}

@Model
final class SavingsYieldLot {
    var id: UUID
    var applicationDate: Date
    var principalInCents: Int64
    var grossBalanceInCents: Int64

    init(input: SavingsYieldLotInput) {
        id = input.id
        applicationDate = input.applicationDate
        principalInCents = input.principalInCents
        grossBalanceInCents = input.grossBalanceInCents
    }

    var input: SavingsYieldLotInput {
        SavingsYieldLotInput(id: id, applicationDate: applicationDate,
            principalInCents: principalInCents, grossBalanceInCents: grossBalanceInCents)
    }
}

}
