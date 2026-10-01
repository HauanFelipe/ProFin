# ProFin

Aplicativo pessoal de finanças em SwiftUI e SwiftData, com armazenamento local.

## Etapa atual

- Navegar entre Dashboard, Movimentações, Caixinhas, Metas e Relatórios.
- Consultar o resumo do mês e o patrimônio no Dashboard.
- Consultar receitas e despesas por mês em Relatórios.
- Cadastrar receitas e despesas.
- Escolher entre dez categorias iniciais ou criar suas próprias categorias.
- Classificar despesas como essenciais ou não essenciais.
- Associar receitas e despesas a uma conta (a conta inicial é criada automaticamente).
- Consultar a lista por data, da mais recente para a mais antiga, e abrir os detalhes.
- Excluir movimentações pela lista.
- Cadastrar, editar, desativar e reativar contas recorrentes mensais.
- Consultar cobranças previstas, pagas, pendentes e atrasadas, com resumo mensal.
- Registrar o pagamento de uma cobrança ou vinculá-la a uma despesa existente.

As movimentações representam valores já recebidos ou pagos. O formulário aceita
datas até hoje. As cinco áreas têm telas próprias e navegação independente.
Caixinhas consulta as contas dos tipos normal e turbo e apresenta seus saldos;
se não houver caixinhas, exibe um estado vazio. Metas tem uma tela de apresentação.
Os cadastros de caixinhas e metas e a tela de transferências ficam para etapas futuras.
As recorrências ficam em **Movimentações → Contas recorrentes**. Cadastrar uma
recorrência gera apenas previsões; uma despesa só é criada ao registrar um pagamento.

## Organização

- `ProFin/App`: entrada do app, configuração do banco e categorias iniciais.
- `ProFin/Models`: categoria, conta, receita/despesa, transferência e seus tipos.
- `ProFin/Persistence`: schemas V1/V2/V3 e plano de migração do SwiftData.
- `ProFin/Services`: validação/gravação de operações e cálculos financeiros.
- `ProFin/Views`: lista, formulário e detalhes.
- `ProFin/Components`: apresentação de uma movimentação na lista.
- `ProFin/Utilities`: leitura e formatação de valores em reais.
- `ProFinTests`: testes de dinheiro e persistência.

As telas usam `@Query` para ler os registros. Novas receitas/despesas são gravadas
por `FinancialOperations`, que também oferece a operação de transferência para
a futura interface. As gravações continuam usando `ModelContext`, sem repositórios.

## Valores e armazenamento

Os valores são inteiros em centavos (`Int64`): R$ 25,90 é armazenado como `2590`.
O campo aceita `25,90`, `650` e `1.234,56`. Valores zerados, negativos, com mais de
duas casas decimais ou fora do limite do inteiro são rejeitados.

O tipo receita/despesa determina o sentido da movimentação; o valor é sempre positivo.
A classificação é obrigatória para despesas e não é armazenada nas receitas.

Cada inclusão e exclusão é salva explicitamente. Se o salvamento falhar, as alterações
pendentes são desfeitas e a tela apresenta uma mensagem. A interface substitui o
contexto por um novo contexto do mesmo banco, preservando os campos do formulário.
Isso evita reutilizar relações em memória invalidadas pelo SwiftData após uma falha.

## Contas, transferências e cálculos

`FinancialAccount` representa conta corrente, caixinha normal, caixinha turbo ou
outra conta. Nesta etapa, todas representam valores em BRL. O tipo não aplica
regras de rendimento. O nome é livre e pode haver várias contas do mesmo tipo.

`FinancialTransaction` mantém apenas `income` e `expense`, com uma conta exigida
pelo inicializador e pela operação de gravação. O relacionamento persistido é
opcional para permitir a migração dos registros anteriores.

`AccountTransfer` contém um valor positivo, uma data e duas contas obrigatórias e
distintas. `FinancialOperations.transfer` valida e salva um único registro, sem
criar receitas ou despesas. Taxas, se houver, devem ser despesas separadas.
Novas operações exigem contas ativas, modelos no mesmo contexto e datas até hoje.
Os serviços são o ponto de gravação da aplicação; inserir Models diretamente no
contexto não executa essas validações de negócio. Ao receber `contextDiscarded`,
consumidores devem descartar o contexto que falhou e seus Models e buscar os dados
usando `AppData.makeContext`. A interface faz essa substituição automaticamente.

`FinancialSummary` calcula, sem persistir saldos derivados:

```text
saldo = saldo inicial + receitas − despesas + transferências recebidas − enviadas
patrimônio = soma dos saldos de todas as contas, inclusive arquivadas
resultado mensal = receitas do mês − despesas do mês
```

O saldo inicial é anterior a todos os lançamentos registrados da conta. `nil`
significa desconhecido; `0` significa zero confirmado. Saldo e patrimônio retornam
`nil` quando falta essa informação, sem apresentar uma soma parcial como total.
Para consultar uma data, o cálculo considera movimentações até aquele instante.
O resultado mensal usa os limites do mês no calendário/fuso informado, excluindo
o primeiro instante do mês seguinte. As somas usam `Decimal` como acumulador exato
e verificam os limites de `Int64` antes de retornar centavos.

Conta com histórico não pode ser excluída pela operação de exclusão. As relações
também usam `.deny`; arquivar (`isActive = false`) preserva histórico e patrimônio.
Uma conta sem histórico mas com saldo inicial diferente de zero também não pode
ser excluída. Categorias e contas mantêm UUIDs gerados pelo app sem índice `.unique`:
o Core Data usado pelo SwiftData reporta incompatibilidade desse índice com suas
relações inversas obrigatórias e `.deny`. A criação de categorias valida nomes repetidos no serviço, desconsiderando
maiúsculas, acentos e espaços excedentes. Nomes de contas continuam livres.
Não há importação com deduplicação nesta etapa.

## Migração e compatibilidade

`ProFinSchemaV1` preserva a estrutura original; não deve ser alterado.
`ProFinSchemaV2` preserva a etapa com contas e transferências.
`ProFinSchemaV3` acrescenta recorrências, cobranças mensais e o vínculo opcional do
pagamento. O plano migra V1 → V2 → V3. O app mantém o mesmo banco.
O plano faz a migração estrutural
e `AppData` completa os vínculos antes de liberar o contexto para as telas.

Lançamentos sem conta são associados à “Conta inicial”, tipo `other`, com saldo
inicial desconhecido. Seu UUID fixo permite retomar o preenchimento sem duplicá-la,
inclusive após renomeá-la. Contas já atribuídas são preservadas. Valores, datas,
IDs, categorias, tipos e observações anteriores não são recalculados ou substituídos.
O banco existente não é apagado em caso de erro.

O SwiftData usa um banco chamado `ProFin`, com CloudKit desabilitado. O antigo banco
de exemplo do Xcode não é apagado nem utilizado. As categorias são criadas somente
quando o banco ainda não contém categorias.

## Executar e testar

Abra `ProFin.xcodeproj`, selecione o scheme `ProFin` e um simulador com iOS 27.0 ou
superior. Use **Command + R** para executar e **Command + U** para rodar os testes.

Na aba **Movimentações**, toque em **+**, preencha os campos obrigatórios e toque em **Salvar**.
Toque em uma movimentação para ver seus detalhes. Para excluir, deslize a linha para
a esquerda ou use o botão de edição da lista.

O app abre no **Dashboard**. Em **Relatórios**, use as setas para consultar outros
meses. Patrimônio e saldos com informação inicial desconhecida são identificados
como incompletos, sem assumir que o valor seja zero.

Os testes verificam conversão monetária, validações, limites de `Int64`, categorias
sem duplicação, classificação de receitas, relacionamentos e reabertura em disco.
Também cobrem migração a partir da V1 com e sem versionamento explícito, retomada
do preenchimento de contas, transferências preservando patrimônio e resultado
mensal, saldos desconhecidos, contas arquivadas, limites mensais e exclusões.


## Contas recorrentes

Abra **Movimentações → Contas recorrentes → +**. Informe descrição, categoria,
classificação, tipo fixa/variável, valor previsto, dia e mês inicial. A frequência
implementada nesta etapa é mensal. Valores fixos devem ser positivos; a estimativa
variável pode ficar em branco, aparecendo como desconhecida nos totais.

`RecurringExpense` é o cadastro; `RecurringExpenseOccurrence` guarda o retrato de
cada mês. A geração recupera meses transcorridos desde o início do período ativo,
sem duplicar a combinação conta/mês e sem criar `FinancialTransaction`.
A chave estável da cobrança também tem uma restrição de unicidade no banco.
Datas de vencimento que não existem no mês usam seu último dia.

Consultas a meses futuros produzem `RecurringCharge`, uma estrutura em memória.
Essas projeções não são persistidas e não permitem pagamento antes da geração da
cobrança no mês correspondente. A atualização acontece ao abrir o banco, acessar
recorrências, trocar o mês ou retornar à tela com o app ativo.

Em **Gerenciar contas**, editar consolida primeiro as cobranças até o mês atual;
as mudanças valem para as próximas cobranças. Desativar preserva cobranças e dívidas
existentes. Reativar usa o mês escolhido (atual ou futuro), sem preencher o intervalo
inativo. Não há exclusão de cadastros com histórico.

Em uma cobrança, **Registrar pagamento** permite informar valor efetivo, data e
conta financeira. O serviço valida, cria uma única despesa, vincula à cobrança e
salva tudo na mesma operação. Repetir o pagamento é rejeitado. Também é possível
selecionar **Usar despesa já registrada**, que cria somente o vínculo, sem novo débito.
A mesma despesa não pode quitar duas cobranças. Pagamentos são integrais nesta etapa.
Excluir a despesa vinculada pela lista avisa que a cobrança voltará a ficar pendente.

`RecurringExpenseSummary` calcula os totais, sem gravar saldos ou status:

```text
previsto = soma das estimativas das cobranças do mês, inclusive as já pagas
pago = soma dos valores efetivos vinculados às cobranças daquele mês
pendente = soma das estimativas das cobranças sem pagamento
comprometimento (%) = previsto / receitas efetivamente registradas no mês * 100
```

Sem receita, o percentual é indisponível. Uma previsão sem valor deixa o total
previsto e o percentual incompletos, exibindo subtotal conhecido e quantidade sem
estimativa. O total pendente só fica incompleto se houver cobrança SEM pagamento
E SEM estimativa. Valores variáveis pagos podem diferir da previsão: previsto não
precisa ser igual a pago + pendente. O percentual pode superar 100%.

O resumo recorrente usa o mês da cobrança; `FinancialSummary` usa a data da
movimentação. Uma cobrança de setembro paga em outubro fica quitada na referência
de setembro e afeta as despesas realizadas de outubro uma única vez.

Os status são calculados: pagamento vinculado → Pago; vencimento anterior a hoje
→ Atrasado; entre hoje e três dias adiante → Vencendo em breve; depois → Pendente.
O dia inteiro do vencimento é considerado, no calendário usado pelo cálculo.
Todas as cobranças sem pagamento, inclusive atrasadas, entram no pendente do mês.

O Dashboard mantém sua apresentação. `RecurringMonthlySummary` disponibiliza
previsões, pendências, pagamentos e receitas para integração futura. Os valores
`expectedInCents` e `pendingInCents` são opcionais para não apresentar subtotais
como totais completos. Não se presume que patrimônio seja dinheiro livre para compra.

Os testes de recorrência cobrem cadastro sem despesa, estimativa desconhecida,
status, meses futuros, dia 31/ano bissexto, geração idempotente, edição do histórico,
reativação, pagamento e vínculo sem duplicação, exclusão, comprometimento, limites
monetários, migração V2 → V3, reabertura e falha real de gravação do pagamento.


## Criar categorias

Nos formulários de movimentações e de contas recorrentes, toque em **Criar categoria**,
logo abaixo da escolha de categoria. Informe o nome e toque em **Salvar**. A nova
categoria é armazenada localmente e fica selecionada automaticamente no formulário
original, preservando os outros campos preenchidos.

A categoria fica disponível para receitas, despesas e recorrências. Nomes vazios
ou repetidos (como “Alimentação” e “alimentacao”) são recusados. Espaços excedentes
são normalizados. O cadastro da categoria é independente: mesmo que você cancele
a movimentação depois, a categoria salva continua disponível.
