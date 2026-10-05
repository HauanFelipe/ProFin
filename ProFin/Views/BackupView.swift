import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var candidate: ProFinBackup?
    @State private var confirming = false
    @State private var message: String?
    @State private var busy = false
    @AppStorage("ProFin.lastBackupExport") private var lastExport: Double = 0

    var body: some View {
        List {
            Section {
                Button("Salvar backup no app Arquivos", systemImage: "square.and.arrow.up") {
                    busy = true
                    defer { busy = false }
                    do {
                        document = BackupDocument(data: try BackupService.export(context: context))
                        exporting = true
                    } catch { show(error) }
                }
                if lastExport > 0 {
                    LabeledContent("Última exportação neste aparelho") {
                        Text(Date(timeIntervalSince1970: lastExport), format: .dateTime.day().month().year().hour().minute())
                    }
                }
            } header: {
                Text("Criar backup")
            } footer: {
                Text("Inclui contas, movimentações, caixinhas, metas, recorrências, cartões, simulações de rendimento e Plano do mês. O backup é manual: exporte novamente após atualizar seus dados.")
            }
            Section {
                Button("Escolher backup para restaurar", systemImage: "square.and.arrow.down") { importing = true }
                if let candidate {
                    LabeledContent("Backup criado em") {
                        Text(candidate.createdAt, format: .dateTime.day().month().year().hour().minute())
                    }
                    LabeledContent("Contas e caixinhas", value: "\(candidate.recordCounts["accounts"] ?? 0)")
                    LabeledContent("Movimentações", value: "\(candidate.recordCounts["transactions"] ?? 0)")
                    LabeledContent("Transferências", value: "\(candidate.recordCounts["transfers"] ?? 0)")
                    LabeledContent("Compras no cartão", value: "\(candidate.recordCounts["purchases"] ?? 0)")
                    LabeledContent("Metas", value: "\(candidate.recordCounts["goals"] ?? 0)")
                    Button("Restaurar este backup", role: .destructive) { confirming = true }
                    Button("Cancelar seleção", role: .cancel) { self.candidate = nil }
                }
            } header: {
                Text("Restaurar após reinstalar")
            } footer: {
                Text("A restauração substitui os dados atuais pelos do arquivo; não mistura nem soma os dois históricos. Exporte um backup dos dados atuais antes de substituir, se quiser preservá-los.")
            }
            Section("Como usar") {
                Text("1. Salve o backup antes de apagar ou reinstalar o ProFin.")
                Text("2. Escolha uma pasta fora do ProFin, como iCloud Drive no app Arquivos, ou guarde uma cópia no computador. Arquivos dentro da pasta do aplicativo podem ser apagados junto com ele.")
                Text("3. Depois de instalar, abra Dashboard → Backup e restauração, escolha o arquivo mais recente e confirme.")
                Text("O arquivo contém seus dados financeiros e não tem senha. Guarde-o em um local privado. Não é enviado a nenhum servidor pelo ProFin; o local escolhido no app Arquivos controla a sincronização.")
            }.font(.subheadline)
        }
        .navigationTitle("Backup e restauração")
        .proFinScreen()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "ProFin-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success:
                lastExport = Date().timeIntervalSince1970
                message = "Backup salvo. Guarde esse arquivo para restaurar seus dados após reinstalar o ProFin."
            case .failure(let error): show(error)
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                candidate = nil
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 200_000_000 else { throw BackupError.invalidFile }
                candidate = try BackupService.decode(Data(contentsOf: url))
            } catch { show(error) }
        }
        .confirmationDialog("Substituir os dados atuais?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Substituir e restaurar", role: .destructive) {
                guard let candidate else { return }
                busy = true
                defer { busy = false }
                do { try BackupService.restore(candidate) }
                catch { show(error) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os dados atuais serão substituídos pelo backup selecionado. Os registros feitos depois desse backup não estarão no histórico restaurado.")
        }
        .alert("Backup do ProFin", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func show(_ error: Error) {
        message = (error as? BackupError)?.errorDescription ?? "Não foi possível concluir. Confira o arquivo e o espaço disponível e tente novamente."
    }
}
