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
- Criar e editar contas correntes, caixinhas, dinheiro e outras contas.
- Transferir entre contas e consultar o histórico de entradas e retiradas.
- Desativar contas com saldo zerado ou reativá-las preservando seu histórico.
- Simular rendimentos de caixinhas em RDB até o fim do mês, com IR e IOF no resgate.
- Cadastrar, editar, arquivar e excluir metas com uma caixinha exclusiva por meta ativa.

As movimentações representam valores já recebidos ou pagos. O formulário aceita
datas até hoje. As cinco áreas têm telas próprias e navegação independente.
Caixinhas apresenta as caixinhas ativas, o total, o cadastro e as transferências.
Cada caixinha abre seu saldo e histórico. **Caixinhas → Gerenciar contas** permite
cadastrar também a conta corrente e informar o dinheiro atual de cada conta.
Metas permite cadastrar objetivos e vincular uma caixinha exclusiva a cada meta ativa.
As recorrências ficam em **Movimentações → Contas recorrentes**. Cadastrar uma
recorrência gera apenas previsões; uma despesa só é criada ao registrar um pagamento.

## Organização

- `ProFin/App`: entrada do app, configuração do banco e categorias iniciais.
- `ProFin/Models`: categoria, conta, receita/despesa, transferência e seus tipos.
- `ProFin/Persistence`: schemas V1/V2/V3/V4/V5/V6/V7 e plano de migração do SwiftData.
- `ProFin/Services`: validação/gravação de operações e cálculos financeiros.
- `ProFin/Views`: lista, formulário e detalhes.
- `ProFin/Components`: apresentação de uma movimentação na lista.
- `ProFin/Utilities`: leitura e formatação de valores em reais.
- `ProFinTests`: testes de dinheiro e persistência.

As telas usam `@Query` para ler os registros. Novas receitas/despesas são gravadas
por `FinancialOperations`, que também valida e grava contas e transferências. As gravações continuam usando `ModelContext`, sem repositórios.

## Valores e armazenamento

Os valores são inteiros em centavos (`Int64`): R$ 25,90 é armazenado como `2590`.
O campo aceita `25,90`, `650` e `1.234,56`. Valores zerados, negativos, com mais de
duas casas decimais ou fora do limite do inteiro são rejeitados em movimentações
e transferências. O saldo inicial aceita zero e valores negativos.

O tipo receita/despesa determina o sentido da movimentação; o valor é sempre positivo.
A classificação é obrigatória para despesas e não é armazenada nas receitas.

Cada inclusão e exclusão é salva explicitamente. Se o salvamento falhar, as alterações
pendentes são desfeitas e a tela apresenta uma mensagem. A interface substitui o
contexto por um novo contexto do mesmo banco, preservando os campos do formulário.
Isso evita reutilizar relações em memória invalidadas pelo SwiftData após uma falha.

## Contas, transferências e cálculos

`FinancialAccount` representa conta corrente, caixinha, dinheiro ou outra conta.
Caixinha Turbo e Caixinha Normal são nomes de contas distintas do tipo caixinha. Nesta etapa, todas representam valores em BRL. O tipo não aplica
regras de rendimento. O nome é livre e pode haver várias contas do mesmo tipo.

`FinancialTransaction` mantém apenas `income` e `expense`, com uma conta exigida
pelo inicializador e pela operação de gravação. O relacionamento persistido é
opcional para permitir a migração dos registros anteriores.

`AccountTransfer` contém um valor positivo, uma data e duas contas obrigatórias e
distintas. `FinancialOperations.transfer` valida e salva um único registro, sem
criar receitas ou despesas. Taxas, se houver, devem ser despesas separadas.
Novas operações exigem contas ativas, modelos no mesmo contexto e datas até hoje.
Transferências exigem saldo inicial conhecido e saldo suficiente na origem. Para
uma transferência retroativa, `transferableBalance` usa o menor saldo desde a data
escolhida até hoje, incluindo os lançamentos posteriores. Assim, uma receita
posterior não financia uma transferência anterior e um novo débito retroativo
não deixa negativos os saldos dos lançamentos posteriores. Movimentos no mesmo
instante são agrupados. O saldo do destino pode continuar desconhecido até que
seu saldo inicial seja informado; a transferência permanece no histórico.
Os serviços são o ponto de gravação da aplicação; inserir Models diretamente no
contexto não executa essas validações de negócio. Ao receber `contextDiscarded`,
consumidores devem descartar o contexto que falhou e seus Models e buscar os dados
usando `AppData.makeContext`. A interface faz essa substituição automaticamente.

`FinancialSummary` calcula, sem persistir saldos derivados:

```text
saldo = saldo inicial + receitas − despesas + transferências recebidas − enviadas
patrimônio = soma dos saldos das contas ativas
total em caixinhas = soma dos saldos das contas ativas do tipo caixinha
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
também usam `.deny`. Desativar (`isActive = false`) exige saldo conhecido e zerado,
preserva o histórico e retira a conta do patrimônio ativo. Contas inativas antigas
não são alteradas, mesmo que tenham saldo; podem ser consultadas e reativadas em
Gerenciar contas. Não é permitido alterar seu saldo inicial enquanto inativas.
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
pagamento, e permanece congelado para migrações. `ProFinSchemaV4` adiciona
`FinancialAccount.createdAt`, opcional para não inventar datas de contas antigas.
O plano migra V1 → V2 → V3 → V4. O app mantém o mesmo banco.
O antigo tipo `turboBox` é normalizado para `savingsBox` de forma idempotente;
nomes, IDs, saldos iniciais, situação ativa/inativa e vínculos são preservados.
O plano faz a migração estrutural
e `AppData` completa os vínculos antes de liberar o contexto para as telas.

Lançamentos sem conta são associados à conta principal de UUID fixo. Se for
necessário criá-la, ela se chama “Conta Principal”, tipo conta corrente, com saldo
inicial desconhecido. Uma “Conta inicial” existente mantém seu nome e tipo.
Seu UUID fixo permite retomar o preenchimento sem duplicá-la,
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
monetários, migração V2 → V4, reabertura e falha real de gravação do pagamento.


## Criar categorias

Nos formulários de movimentações e de contas recorrentes, toque em **Criar categoria**,
logo abaixo da escolha de categoria. Informe o nome e toque em **Salvar**. A nova
categoria é armazenada localmente e fica selecionada automaticamente no formulário
original, preservando os outros campos preenchidos.

A categoria fica disponível para receitas, despesas e recorrências. Nomes vazios
ou repetidos (como “Alimentação” e “alimentacao”) são recusados. Espaços excedentes
são normalizados. O cadastro da categoria é independente: mesmo que você cancele
a movimentação depois, a categoria salva continua disponível.


## Usar caixinhas e transferências

1. Em **Dashboard → Gerenciar dinheiro nas contas**, abra sua conta e toque em
   **Editar**. Informe quanto dinheiro há nela agora, sem incluir as caixinhas.
2. Em **Caixinhas → Criar caixinha**, informe o nome, o tipo e o dinheiro que
   já existe nela. Esse cadastro não cria receita.
3. Toque em **Transferir dinheiro**, escolha origem, destino, valor e data.
   A confirmação grava um único `AccountTransfer`; não cria receita nem despesa.
4. Abra uma caixinha para consultar o saldo e o histórico, adicionar dinheiro de
   outra conta ou retirar para outra conta. O histórico é calculado por
   `AccountHistory`, sem duplicar os registros persistidos.

O formulário explica erros de valor, contas iguais, saldo desconhecido ou
insuficiente. As validações também ficam nos serviços. O cadastro de uma receita
ou despesa e o pagamento de recorrências continuam usando a conta selecionada.
Os testes adicionais cobrem saldos por conta, depósito/retirada, insuficiência,
transferências retroativas, histórico, ativação, valores iniciais negativos,
persistência e migração V3 → V4 preservando pagamentos e transferências.


## Projeção de rendimento das caixinhas

Abra **Caixinhas → sua caixinha → Rendimento estimado → Configurar projeção**.
Há atalhos para **100%, 115% e 120% do CDI**, com percentual editável por conta.
Não criamos automaticamente contas nem presumimos a taxa pelo nome “Turbo”.
Confirme no banco se a caixinha usa RDB; liquidez imediata também pode existir em
outros produtos, e este cálculo não se aplica a fundos de investimento.

Informe o CDI **anual** usado como premissa, a data-base e cada aporte remanescente:
data original da aplicação, principal ainda investido e saldo bruto já acumulado.
O saldo é a posição no início da data-base. Se houve retirada parcial, informe
os valores remanescentes conforme a posição do banco. Isso evita reconstruir
rendimentos antigos com o CDI atual ou confundir saldo líquido com principal.

A previsão vai da data-base ao fim do mesmo mês. A sugestão de dias de rendimento
conta segunda a sexta, incluindo a data-base. **Feriados não são descontados
automaticamente**: ajuste o campo conforme o calendário do banco. O app não usa
APIs e não conhece alterações futuras do CDI, condições promocionais ou vencimentos.
A hipótese é taxa constante, sem novos aportes, retiradas ou reinvestimentos.

`SavingsYieldCalculator` centraliza a simulação de cada aporte:

```text
taxa diária CDI = (1 + CDI anual / 100)^(1/252) − 1
fator = (1 + taxa diária CDI × percentual do CDI / 100)^dias de rendimento
saldo bruto final = saldo bruto informado × fator
rendimento no período = saldo bruto final − saldo bruto informado
ganho acumulado = saldo bruto final − principal remanescente
IOF = ganho acumulado × alíquota regressiva por dias corridos
IR = (ganho acumulado − IOF) × alíquota de IR por dias corridos
líquido no resgate = saldo bruto final − IOF − IR
```

O prazo fiscal usa a data original de **cada aporte**, até o último dia do mês,
no calendário de São Paulo. O IR é 22,5% até 180 dias, 20% de 181 a 360, 17,5%
de 361 a 720 e 15% acima de 720. O IOF zera a partir de 30 dias. Os impostos
mostrados são a estimativa de **resgate integral no fim do mês**, sobre todo o
ganho acumulado, e não uma cobrança mensal ou um desconto só sobre o ganho futuro.
Valores, impostos e saldos são arredondados por aporte ao centavo mais próximo;
a capitalização usa ponto flutuante para a potência e Decimal para os valores.
Podem ocorrer diferenças de centavos em relação ao cálculo operacional do banco.

As premissas e aportes são salvos localmente em `SavingsYieldConfiguration` e
`SavingsYieldLot`. São dados de simulação: não criam receitas, despesas ou
transferências e não aumentam o patrimônio registrado. Se o histórico da conta
mudar ou a projeção pertencer a um mês anterior, a tela solicita atualização da
posição e não apresenta o resultado antigo como atual. Ela não importa nem
concilia automaticamente a posição com o banco.

A migração V4 → V5 adiciona apenas essas duas entidades, reutilizando os modelos
financeiros da V4. Contas antigas continuam sem projeção até serem configuradas;
nenhuma taxa, data de aplicação ou posição é inventada.

Referências para as regras consultadas em 01/10/2026:
- [B3: acumulação do DI](https://b3.com.br/main.jsp?lumA=1&lumII=2C9FBE63638CFE2501638D373B435E37&lumPageId=2C9FBE63638CFE2501638D3464C8577B)
- [Lei 11.033: alíquotas de IR](https://www.planalto.gov.br/ccivil_03/_ato2004-2006/2004/lei/l11033compilado.htm)
- [Receita Federal: base de IR líquida de IOF](https://normas.receita.fazenda.gov.br/sijut2consulta/anexoOutros.action?idArquivoBinario=35512)
- [Nubank: IOF regressivo](https://blog.nubank.com.br/iof-tudo-sobre/)

Os testes cobrem as três taxas, fronteiras do IR, IOF em 0/1/15/29/30/31 dias,
aportes com prazos diferentes, ausência de ganho, calendário, limites de valores,
persistência, substituição dos aportes, detecção de posição desatualizada e
migração V4 → V5. A configuração não altera os saldos ou o resultado financeiro.


## Metas

Abra **Metas → +** e informe nome e valor desejado. Você pode vincular uma
caixinha ativa ou deixar o vínculo para depois. Cada caixinha só pode atender
uma meta ativa; o serviço valida a exclusividade também ao editar ou reativar.

`Goal` armazena UUID, nome, valor desejado em centavos, caixinha opcional,
data de criação e situação arquivada. `GoalSummary` reutiliza o saldo registrado
por `FinancialSummary`: não há outro saldo persistido e rendimentos projetados
não entram no progresso. Saldo desconhecido deixa o progresso indisponível;
saldo negativo contribui com zero. O percentual fica entre 0% e 100%, e o
valor faltante nunca fica negativo. Excedentes permanecem visíveis no saldo.

Vincular uma meta é uma organização do dinheiro, não uma movimentação financeira.
Depósitos e retiradas alteram o progresso. “Valor atingido” não cria despesa,
não conclui uma compra e não é uma recomendação para comprar.

Abra a meta para editar, consultar a caixinha, arquivar, reativar ou excluir.
Arquivar libera a caixinha para outra meta e preserva o vínculo como referência,
sem exibir um progresso ativo na meta arquivada. Reativar verifica novamente
se a caixinha está ativa e disponível. Editar permite remover ou trocar o vínculo.
Excluir a meta preserva a conta, os rendimentos configurados e as movimentações.

Desativar, excluir ou mudar o tipo de uma caixinha com meta ativa exige primeiro
desvincular ou arquivar a meta. Excluir uma conta vazia ligada a metas arquivadas
apenas remove o vínculo dessas metas. A reserva não bloqueia despesas ou retiradas:
esses lançamentos continuam refletidos no progresso.

A V6 adiciona `Goal`. As estruturas V4 e V5 foram congeladas em arquivos próprios;
os modelos atuais usam a V6. Isso impede que a descoberta automática de
relacionamentos do SwiftData altere os schemas antigos durante uma migração. A migração não cria metas
nem altera saldos. Os testes cobrem progresso, transferências, excedentes, saldo
negativo/desconhecido, vínculo exclusivo, edição, arquivamento, reativação,
proteção de contas vinculadas, exclusão sem perda financeira e migração/reabertura.
A divisão manual de uma conta entre várias metas fica para uma etapa posterior.


Se a origem estiver sem valor definido, a transferência oferece **Informar dinheiro
na conta de origem**. O formulário retorna à transferência com os campos mantidos.
Informe o dinheiro atual; os lançamentos existentes não são somados novamente.

## Dinheiro disponível no Dashboard

O campo visível “Dinheiro na conta” representa o saldo atual, excluindo caixinhas.
O Dashboard soma as contas ativas dos tipos conta corrente, dinheiro e outro;
caixinhas ficam fora desse total e continuam incluídas no patrimônio. Contas a
pagar ainda não foram descontadas desse indicador.

Não houve remoção de dados nem mudança de schema. Internamente, o serviço converte
o valor atual informado para a base usada pelo histórico: base = valor atual −
receitas + despesas − transferências recebidas + transferências enviadas. Assim,
não duplica receitas antigas nem cria movimentações de ajuste. As movimentações
são preservadas; alterar essa base também recalcula consultas históricas de saldo.
O saldo inicial é um detalhe interno de compatibilidade e não é mais solicitado
ou exibido ao usuário. Para entradas e saídas novas, registre a movimentação ou
transferência correspondente; editar o valor serve para corrigir o saldo informado.


## Análise de compra e reserva de emergência

Em **Metas → sua meta → Analisar compra**, simule uma compra à vista hoje.
O preço começa com o valor da meta e pode ser alterado apenas na simulação.
Informe gastos previstos adicionais, margem a manter e custos como frete ou
descontos no resgate. Use zero quando não houver esses valores.

```text
sobra = dinheiro nas contas ativas fora das caixinhas
      + saldo da caixinha ativa vinculada à meta
      − contas pendentes com vencimento até o fim do mês (incluindo atrasadas)
      − gastos previstos adicionais − margem − custos − compra
```

`PurchaseAnalysisService` concentra o cálculo e produz `PurchaseAnalysis`, sem
persistir saldos ou recomendações. O resultado informa quanto falta, se há cobertura
exata ou quanto sobra além da margem. A análise fica incompleta quando uma conta
incluída não tem saldo informado ou uma cobrança pendente não tem estimativa.
Caixinhas não utilizadas na análise podem ter saldo desconhecido sem bloquear o
cálculo. Valores negativos de saldo são considerados, não escondidos.

Ao abrir a tela e ao retornar ao app, as ocorrências recorrentes são atualizadas;
se a atualização falhar, o resultado fica indisponível até uma nova tentativa.
Cobranças pagas não são descontadas novamente. Contas de meses anteriores ainda
pendentes entram no cálculo mesmo que a recorrência tenha sido desativada.
Compromissos após o fim do mês ficam fora desse horizonte. A lista mostra quais
cobranças foram descontadas. Gastos extras devem excluir os já listados.

O resultado mensal é apenas contexto: receitas e despesas realizadas já afetam o
saldo. Receitas futuras, projeções de rendimento e caixinhas de outras metas não
são somadas. A simulação não cria compras, despesas, pagamentos ou transferências.
Os campos da simulação não são persistidos ao sair da tela.

Em **Caixinhas → sua caixinha → Editar**, ative **Proteger como reserva de emergência**.
A proteção é exclusiva de caixinhas. Ela impede vincular a caixinha a uma meta de
compra ou reativar uma meta antiga ainda vinculada. Se houver uma meta ativa,
primeiro desvincule ou arquive a meta. Transferências continuam permitidas: a
proteção é uma regra de planejamento, não um bloqueio bancário. Para mudar o tipo
da conta, remova a proteção explicitamente.

A V7 acrescenta `FinancialAccount.isEmergencyReserve`, inicialmente falso para
contas existentes. O retrato V6 foi congelado antes da alteração. Nenhuma conta é
marcada automaticamente, e os vínculos/saldos antigos são preservados na migração.
Os testes cobrem pendências antigas e futuras, pagamentos sem dupla contagem,
exclusão de outras caixinhas/reservas, valores desconhecidos, limites de cobertura,
custos, transferências, proteção e migração/reabertura.

## Cartões e Plano do mês

Acesse **Movimentações → Cartões** (também disponível no Dashboard). Cadastre
nome, limite, fechamento e vencimento. Compras permitem categoria, classificação,
valor total e de 1 a 120 parcelas. Os centavos restantes são distribuídos nas
primeiras parcelas, preservando exatamente o total. O limite disponível é uma
estimativa local; não há consulta ao banco nem bloqueio pelo limite cadastrado.

A fatura sugerida considera compras no dia do fechamento na próxima fatura.
É possível escolher a primeira fatura manualmente para conferir com o banco.
Dias inexistentes são ajustados ao último dia do mês. Alterar as datas do cartão
não modifica as faturas já registradas.

- A compra cria parcelas e dívida, sem tirar dinheiro da conta.
- Cada parcela entra nos gastos do mês de vencimento da fatura.
- Pagar a fatura reduz o saldo da conta e a dívida, sem criar outra despesa.
- O patrimônio líquido do Dashboard desconta toda a dívida, inclusive parcelas futuras.
- Uma cobrança recorrente pode ser vinculada à compra: fica **No cartão** e sua
  pendência passa a ser representada pelas faturas, sem duplicação.

Nesta etapa, pagamentos são integrais e permitidos a partir do fechamento.
Não há pagamento parcial, rotativo ou parcelamento da fatura. Estornos estão descritos na etapa de melhorias do cartão abaixo. Compras
sem parcelas pagas podem ser excluídas e cadastradas novamente para correção.
O histórico da conta inclui os pagamentos de faturas.

Em **Dashboard → Plano do mês**, configure gastos extras ainda previstos e a
margem que deseja manter. Depois adicione caixinhas/metas com um valor mensal
desejado e prioridade (menor número primeiro). A fórmula compartilhada com a
análise de compra considera:

`dinheiro livre = saldo fora das caixinhas − recorrências pendentes − faturas pendentes − extras − margem`

Entram pendências vencidas e com vencimento até o fim do mês. Parcelas futuras
aparecem na dívida, mas não nessa reserva mensal. Receitas futuras e rendimentos
estimados não são dinheiro disponível. Informações necessárias desconhecidas
bloqueiam as sugestões, em vez de serem tratadas como zero.

O plano distribui o dinheiro livre por prioridade, descontando aportes já feitos
no mês e limitando metas ao valor que falta. A meta e sua caixinha são um único
destino. Aportes de contas que não são caixinhas contam como contribuições;
transferências entre caixinhas não contam. Retiradas não renovam a intenção
mensal. Os destinos permanecem para os meses seguintes; extras e margem precisam
ser confirmados a cada mês. Ao efetivar um gasto extra, atualize sua estimativa
para não reservar duas vezes o mesmo valor.

**Registrar transferência** abre o formulário com destino e valor sugeridos.
Registre apenas transferências feitas no banco; o aplicativo não movimenta
seu dinheiro. Tudo continua local, sem APIs, autenticação ou serviços externos.

A versão V8 do SwiftData acrescenta cartão, compra, parcela, fatura, pagamento,
configuração mensal e regra de aporte. O retrato V7 foi congelado, mantendo a
migração dos dados existentes. Saldos continuam derivados do histórico. Os testes
cobrem parcelamento, centavos, fechamento, pagamento único, vínculo recorrente,
prioridades, aportes, limite das metas, dinheiro insuficiente, mudança de mês,
persistência e migração V7 → V8.

## Análise de gastos

A aba **Relatórios** mostra total, participação percentual e quantidade de
lançamentos por categoria, ordenados pelo maior gasto. As barras representam a
participação no total do mês. Categorias com gastos apenas no mês anterior
continuam na comparação, com valor atual zero.

A análise soma despesas das contas e parcelas no mês da fatura. Receitas,
transferências e pagamentos de faturas não entram novamente. Cada parcela conta
como um lançamento, não como uma nova compra pelo valor total. A classificação
é a informada pelo usuário; registros antigos sem classificação aparecem
separadamente, sem suposições automáticas.

A comparação usa o mês anterior completo, inclusive na virada do ano. Para o
mês atual, a interface avisa que ele está em andamento. Variações percentuais
não são calculadas quando o valor anterior é zero. Os destaques mostram a maior
categoria, o maior aumento em reais e o total classificado como não essencial,
sem identificar gastos como desperdício nem prometer uma economia.

O cálculo está centralizado em `SpendingAnalysis`, sem novos dados persistidos
ou alteração no banco. Testes verificam parcelas sem dupla contagem, limites dos
meses, categorias sem gastos atuais, percentuais, classificação ausente, virada
do ano, ausência de dados e proteção contra estouro de valores.

Cada categoria apresenta uma frase com o total do mês (por exemplo, gastos com
“Namorada”). Toque nela para abrir a lista das despesas e parcelas que compõem o
total, com acesso aos registros originais. Categorias pessoais são criadas no
cadastro do gasto e escolhidas pelo usuário; o app não deduz com quem ele gastou.

## Dashboard: visão do mês

O Dashboard reúne dinheiro nas contas, dinheiro livre segundo o Plano do mês,
sugestões de aportes, pendências e vencimentos, patrimônio líquido, resumo mensal,
maior categoria de gasto e até três metas ativas mais recentes.

Dinheiro livre usa `MonthlyPlanService`, incluindo margem e extras configurados
para o mês. Dados incompletos impedem a exibição de um saldo livre definitivo.
Mostra até três sugestões positivas em ordem de prioridade; o restante livre
considera todas as sugestões. Os detalhes continuam disponíveis no Plano do mês.

Os vencimentos usam `PlanningCommitments`: até cinco contas/faturas pendentes
até o fim do mês, ordenadas pelas mais antigas, incluindo atrasadas. Contas já
vinculadas ao cartão aparecem pela fatura. Valores sem estimativa são indicados.
Ao abrir a tela, retornar ao aplicativo ou puxar para atualizar, as ocorrências
recorrentes são atualizadas. Se isso falhar, o planejamento fica indisponível
até uma nova tentativa, sem apresentar pendências potencialmente desatualizadas.

Categoria e metas abrem seus detalhes e reutilizam `SpendingAnalysis` e
`GoalProgressView`. Não há novos Models nem migração de banco nesta etapa.

## Backup e restauração

Abra **Dashboard → Backup e restauração → Salvar backup no app Arquivos**.
Exporte antes de apagar/reinstalar o aplicativo e sempre que quiser atualizar sua
cópia de segurança. Salve fora da pasta do ProFin, por exemplo no iCloud Drive
escolhido no app Arquivos, ou copie para um computador. Arquivos na pasta do app
podem desaparecer ao desinstalá-lo. O ProFin não envia dados a um servidor.

Depois de instalar, abra a mesma área, escolha o último arquivo JSON exportado,
confira a data e a quantidade de registros e toque em **Restaurar este backup**.
A confirmação substitui o histórico atual pelo backup, sem mesclar ou duplicar
registros. Mudanças posteriores à exportação não estarão no arquivo. A criação
de backup é manual; o horário exibido é o da última exportação neste aparelho.

O arquivo inclui todos os Models atuais (17 na V9, incluindo estornos): contas, categorias, receitas/despesas,
transferências, recorrências e cobranças, metas, posições/lotes da simulação de
rendimento, cartões, compras, parcelas, faturas, pagamentos e Plano do mês.
Não há senha/criptografia no arquivo; guarde-o em local privado. O JSON contém
um snapshot SQLite codificado em base64, versão, data, contagens e SHA-256 para
identificar corrupção acidental. Não é um formato para editar manualmente.

A exportação usa a API de backup do SQLite, incluindo gravações do WAL e tornando
o snapshot independente de arquivos auxiliares. A importação verifica versão,
integridade e contagens e abre um banco separado antes de trocar um ponteiro
local atômico. A interface recarrega o contexto e a próxima inicialização usa o
banco restaurado. Falhas anteriores à ativação mantêm o banco atual. Bancos
anteriores não são apagados durante a restauração. O backup não contém esse
histórico de bancos anteriores, apenas os dados do banco ativo.

A versão atual aceita backups V8 e V9/formato 1; mudanças futuras de schema devem
manter uma rotina explícita de compatibilidade. Arquivos de versões não aceitas
são recusados, sem alterar os dados atuais. A seleção limita arquivos a 200 MB.
Testes cobrem restauração completa, exportação após restaurar, dados recentes no
WAL, relações, corrupção, versão incompatível, contagens divergentes e ativação
persistente com preservação do banco ativo em caso de erro.


## Melhorias do cartão: correções, estornos e parcelas futuras

Em **Cartões → cartão → fatura**, use **Corrigir pagamento registrado por engano**
e confirme. Isso exclui somente o registro local, recompõe o saldo calculado da
conta e reabre a pendência. É possível registrar o pagamento correto em seguida.
A conta precisa estar ativa. Essa operação não desfaz pagamentos no banco.

Em **Cartões → cartão → compra → Registrar estorno**, informe valor, data do
crédito e mês de vencimento da fatura onde o banco lançou o crédito. Estornos
parciais e integrais são permitidos até o valor total da compra. Datas anteriores
à compra e posteriores a hoje são recusadas. Não há receita nem depósito na
conta: o crédito reduz a fatura escolhida, e seu excedente abate faturas seguintes
em ordem cronológica. As parcelas originais permanecem no histórico. Esta etapa
representa crédito em fatura; devolução diretamente em conta e cancelamento
individual de parcelas não são operações disponíveis.

Faturas com crédito suficiente ficam sem valor a pagar; as demais são pagas
integralmente pelo restante após créditos. Alterar compras ou estornos antes de
uma fatura já paga é bloqueado para não reescrever créditos consumidos. Confira e
corrija os registros de pagamento afetados antes de corrigir esse histórico.
Estornos incorretos podem ser removidos com confirmação no detalhe da compra,
respeitando essa mesma proteção.

Relatórios abatem o estorno no mês da fatura do crédito, usando a categoria e a
classificação da compra. Valores líquidos negativos significam crédito; os
percentuais de categoria usam somente saldos positivos após estornos. A análise
mensal não soma o pagamento de fatura como outra despesa. O crédito restante,
após abatimento das compras futuras já cadastradas, entra no patrimônio líquido,
mas não é dinheiro disponível para transferir às caixinhas.

**Cartões → Parcelas dos próximos meses** reúne faturas a partir do próximo mês,
com parcelas e pendências após créditos. O mesmo atalho dentro de um cartão
mostra somente esse cartão. A visão considera registros existentes, sem prever
novas compras, tarifas, juros ou assinaturas ainda não lançadas.

A V8 foi congelada e a V9 adiciona `CardRefund`. Backups V8 continuam aceitos e
migram em um banco separado antes da ativação; novos backups incluem estornos.
Testes verificam pagamentos corrigidos e registrados novamente, créditos
transportados entre faturas, limites e datas, proteção de faturas pagas, relatórios,
saldos, restauração V8 e persistência dos estornos em novos backups.

## Aparência e navegação

O app usa aparência escura, fundo quase preto, destaques azuis e componentes
nativos do SwiftUI. A aba Dashboard passou a se chamar **Início**; sua tela tem
o título **ProFin**. O backup continua acessível nessa tela. Os atalhos iniciais
levam ao registro de movimentações, cartões/faturas e gerenciamento de saldos.

O cartão principal mostra o dinheiro nas contas, ainda sem descontar pendências.
O dinheiro livre permanece identificado separadamente no planejamento. Caixinhas,
metas e relatórios usam a mesma linguagem visual; os formulários também recebem
o tema escuro. As cores estão centralizadas em `ProFinStyle`, junto aos pequenos
componentes visuais compartilhados. Tipografia acompanha o tamanho de texto do
sistema; informações financeiras usam também títulos, sinais e ícones, não
apenas cores. Não foram adicionadas fontes, imagens pesadas, dependências ou
animações contínuas. As listas continuam nativas, com renderização sob demanda.
A atualização visual não altera a persistência nem as regras financeiras.

## Primeira instalação no iPhone e validação

A instalação nova cria somente dez categorias padrão e uma Conta Principal sem
saldo informado. Não há dados financeiros de demonstração no app. O banco do
simulador e os bancos temporários dos testes não são copiados para o iPhone.
O usuário começa informando seu dinheiro em **Início → Dinheiro nas contas**.
Reabrir ou atualizar o app preserva os dados já registrados; não existe limpeza
automática do banco. Uma reinstalação sobre um app existente também pode preservar
seus dados. Não apague o app para testar sem antes exportar o backup que deseja
manter.

O projeto agora permite iOS 26 ou superior, compatível com o iPhone 14 conectado
que executa iOS 26.6.2. Para instalar pelo Xcode, são necessários Modo de
Desenvolvedor no iPhone, conta/Personal Team configurado no Xcode e assinatura
válida. Compilar para dispositivo sem assinatura verifica o código, mas não
significa que o app foi instalado ou validado no telefone.

Nesta revisão foram ajustados o idioma de datas interpoladas, o texto sobre
parcelas na análise de compra e a dispensa do teclado ao rolar formulários.
O teste de primeira instalação verifica ausência de lançamentos em todos os
Models financeiros e preservação de um saldo informado após reabrir o banco.
Ainda precisam ser confirmados no aparelho real: navegação das cinco abas,
formulários/teclado, textos ampliados, VoiceOver, exportação/importação pelo app
Arquivos, uso offline e reabertura. Não use dados pessoais para testes destrutivos;
backup e restauração podem ser conferidos em uma instalação separada de testes.
