import Foundation
import SwiftData
import SQLite3
import CryptoKit

struct ProFinBackup: Codable {
    let app: String
    let formatVersion: Int
    let schemaVersion: Int
    let createdAt: Date
    let recordCounts: [String: Int]
    let checksum: String
    let database: Data
}

enum BackupError: LocalizedError {
    case invalidFile, unsupportedVersion, databaseFailure, pendingChanges
    var errorDescription: String? {
        switch self {
        case .invalidFile: "O arquivo não é um backup válido do ProFin ou está danificado. Seus dados atuais não foram alterados."
        case .unsupportedVersion: "Este backup usa uma versão diferente. Atualize o ProFin antes de tentar restaurar."
        case .databaseFailure: "Não foi possível preparar o banco de dados. Tente novamente."
        case .pendingChanges: "Há alterações ainda não salvas. Conclua ou cancele os cadastros abertos antes de criar o backup."
        }
    }
}

@MainActor
enum BackupService {
    static let restored = Notification.Name("ProFin.backupRestored")
    private static var root: URL {
        URL.applicationSupportDirectory.appending(path: "ProFinRestored", directoryHint: .isDirectory)
    }

    static func activeStoreURL(in directory: URL? = nil) throws -> URL? {
        let directory = directory ?? root
        let pointer = directory.appending(path: "active-store.txt")
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        let name = try String(contentsOf: pointer, encoding: .utf8)
        guard UUID(uuidString: name) != nil else { throw BackupError.invalidFile }
        let url = directory.appending(path: name).appending(path: "ProFin.store")
        guard FileManager.default.fileExists(atPath: url.path) else { throw BackupError.databaseFailure }
        return url
    }

    static func decode(_ data: Data) throws -> ProFinBackup {
        let backup: ProFinBackup
        do { backup = try JSONDecoder().decode(ProFinBackup.self, from: data) }
        catch { throw BackupError.invalidFile }
        guard backup.app == "ProFin" else { throw BackupError.invalidFile }
        guard backup.formatVersion == 1, [8, 9].contains(backup.schemaVersion) else { throw BackupError.unsupportedVersion }
        guard backup.database.starts(with: Data("SQLite format 3\0".utf8)),
              digest(backup.database) == backup.checksum else { throw BackupError.invalidFile }
        return backup
    }

    static func export(context: ModelContext) throws -> Data {
        guard !context.hasChanges else { throw BackupError.pendingChanges }
        guard let configuration = context.container.configurations.first,
              !configuration.isStoredInMemoryOnly else { throw BackupError.databaseFailure }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "snapshot.store")
        // A API de backup do SQLite inclui os dados do WAL sem copiar um banco aberto parcialmente.
        try snapshot(from: configuration.url, to: url)
        let database = try Data(contentsOf: url)
        let counts = try validateStore(at: url)
        let backup = ProFinBackup(app: "ProFin", formatVersion: 1, schemaVersion: 9,
            createdAt: Date(), recordCounts: counts, checksum: digest(database), database: database)
        return try JSONEncoder().encode(backup)
    }

    // Importar em um banco separado evita apagar o banco em uso se a leitura ou migração falhar.
    static func prepare(_ backup: ProFinBackup, at url: URL) throws -> ModelContainer {
        _ = try decode(JSONEncoder().encode(backup))
        try backup.database.write(to: url, options: .atomic)
        if backup.schemaVersion == 8 {
            let schema = Schema(versionedSchema: ProFinSchemaV9.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let migrated = try ModelContainer(for: schema, migrationPlan: ProFinMigrationPlan.self, configurations: [config])
            _ = migrated.mainContext
        }
        var expected = backup.recordCounts
        if backup.schemaVersion == 8 { expected["refunds"] = expected["refunds"] ?? 0 }
        guard try validateStore(at: url) == expected else { throw BackupError.invalidFile }
        return try AppData.makeContainer(at: url)
    }

    static func restore(_ backup: ProFinBackup) throws {
        let container = try activate(backup, in: root)
        NotificationCenter.default.post(name: restored, object: container)
    }

    static func activate(_ backup: ProFinBackup, in directory: URL) throws -> ModelContainer {
        let name = UUID().uuidString
        let folder = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var activated = false
        defer { if !activated { try? FileManager.default.removeItem(at: folder) } }
        let container = try prepare(backup, at: folder.appending(path: "ProFin.store"))
        // Só troca o banco ativo depois de validar e abrir todos os dados. A gravação é atômica.
        try name.write(to: directory.appending(path: "active-store.txt"), atomically: true, encoding: .utf8)
        activated = true
        return container
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func snapshot(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?
        var output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(output, "main", input, "main") else {
            throw BackupError.databaseFailure
        }
        sqlite3_busy_timeout(input, 1500)
        sqlite3_busy_timeout(output, 1500)
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw BackupError.databaseFailure }
        // O arquivo exportado é independente: não pode exigir os arquivos WAL/SHM do banco original.
        guard sqlite3_exec(output, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw BackupError.databaseFailure
        }
    }

    private static func validateStore(at url: URL) throws -> [String: Int] {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw BackupError.invalidFile }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let result = sqlite3_column_text(statement, 0), String(cString: result) == "ok" else {
            throw BackupError.invalidFile
        }
        let schema = Schema(versionedSchema: ProFinSchemaV9.self)
        let config = ModelConfiguration("ProFin", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        // Buscar os Models também verifica que todas as tabelas esperadas podem ser lidas.
        func count<T: PersistentModel>(_ type: T.Type) throws -> Int { try context.fetch(FetchDescriptor<T>()).count }
        return try [
            "accounts": count(FinancialAccount.self), "categories": count(Category.self),
            "transactions": count(FinancialTransaction.self), "transfers": count(AccountTransfer.self),
            "recurringExpenses": count(RecurringExpense.self), "occurrences": count(RecurringExpenseOccurrence.self),
            "yieldConfigurations": count(SavingsYieldConfiguration.self), "yieldLots": count(SavingsYieldLot.self),
            "goals": count(Goal.self), "cards": count(CreditCard.self), "purchases": count(CardPurchase.self),
            "installments": count(CardInstallment.self), "invoices": count(CardInvoice.self),
            "payments": count(CardInvoicePayment.self), "monthlySettings": count(MonthlyPlanSettings.self),
            "allocationRules": count(MonthlyAllocationRule.self), "refunds": count(CardRefund.self)
        ]
    }
}
