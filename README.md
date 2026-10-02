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
- `ProFin/Persistence`: schemas V1/V2/V3/V4/V5/V6 e plano de migração do SwiftData.
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
A divisão manual de uma conta entre várias metas e a análise de compra ficam
para etapas posteriores.


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
