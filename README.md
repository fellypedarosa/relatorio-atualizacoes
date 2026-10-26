# Relatorio de servidores — versão 1

Pacote para execução local e manual em Windows Server. Consulta atualizações Microsoft e Dell, inventaria aplicativos e produz um CSV por execução para análise no Excel. Aplicativos são apenas inventariados: nenhuma comparação com versões mais recentes é feita.

**Estado de homologação:** existem testes locais e verificações dos instaladores, mas ainda não houve execução real nos Windows Server alvo. Antes de liberar o uso em produção, consulte a [base técnica e suas fontes](#base-técnica-e-referências), o [registro do que foi efetivamente validado](docs/VALIDACAO.md) e o [roteiro do piloto](docs/PILOTO.md). Referências dos fabricantes fundamentam as APIs e os comandos utilizados; elas não representam uma auditoria ou aprovação deste script pela Dell ou Microsoft.

## Começar

1. Copie a pasta completa `RelatorioServidor` extraída do ZIP para um diretório local do servidor.
2. Abra o Prompt de Comando **como administrador**.
3. Entre na pasta e execute:

```bat
Iniciar.cmd
```

O CSV e o log serão gravados em `resultados\<servidor>_<data-hora>_<identificador>\`. O campo `modo` identifica a execução e o registro final informa seu resultado. Os arquivos em `evidencias` permitem conferir as fontes e explicar falhas.

O pacote completo inclui os dois instaladores DSU conferidos por SHA-256. Internet continua necessária para as consultas Microsoft e para o catálogo/coletor geridos pelo DSU. Copie a pasta completa: os componentes não devem ser separados.

## Modos

| Comando | Comportamento |
|---|---|
| `Iniciar.cmd` | Inventário, consultas WUA/DSU e preparação automática do DSU quando necessária. Requer administrador. |
| `Iniciar.cmd -Modo Inventario` | Identificação, drivers, aplicativos e funções do Windows. Não prepara o DSU nem consulta atualizações. Requer administrador. |
| `Iniciar.cmd -Modo Demonstracao` | Gera relatório com dados fictícios. Não acessa inventário real, rede, WUA ou executáveis Dell. Não requer administrador. |
| `Preparar-Pacote.cmd` | Obtém e confere os dois instaladores Dell. Não os executa e não instala ferramentas. |

Exemplo de destino alternativo:

```bat
Iniciar.cmd -Modo Demonstracao -PastaSaida "C:\Relatorios"
```

O script não altera a política de execução do PowerShell. Se houver bloqueio corporativo, o pacote precisa seguir o procedimento de assinatura/liberação aprovado pela empresa. O inicializador usa o PowerShell de 64 bits e não carrega perfis pessoais.

## Preparação automática Dell

O perfil considera Windows e modelo. Um DSU já existente só é reutilizado se sua versão corresponder ao perfil e sua assinatura for válida e pertencer à Dell. Caso necessário:

1. Conferir SHA-256 do instalador em cache ou baixar de um dos dois hosts oficiais previstos na matriz.
2. Conferir a assinatura Authenticode antes de executar qualquer binário Dell.
3. Extrair o instalador com `/s /e="pasta"` para um diretório próprio.
4. Se a extração fornecer DSU executável, tentar utilizá-lo diretamente e conferir sua versão.
5. Se não houver executável portátil nem DSU previamente instalado, instalar **somente o complemento DSU** com `/s`, sem `/r` e sem `/f`.
6. Conferir a versão instalada antes de consultar inventário/atualizações.

A instalação pode registrar o DSU no sistema; o pacote não promete isolamento equivalente a uma máquina virtual. Se já houver outro DSU e a extração não fornecer uma alternativa portátil, a substituição é bloqueada e relatada. Dependências do sistema que exijam atualização do Windows, .NET ou reinicialização não são corrigidas automaticamente.

Os SHA-256 autorizados para extração/instalação também estão fixados no código. Alterar a matriz para apontar a outro pacote Dell não autoriza a execução de um instalador diferente, como um pacote de firmware.

## Proteção da produção

- A ferramenta não possui caminhos de execução para aplicar as atualizações encontradas, reiniciar, desligar, parar/reconfigurar serviços ou excluir dados de produção.
- As únicas operações de DSU são `--version`, `--inventory`, `--preview` ou `--compliance`, conforme o perfil. A entrada padrão fica vazia. Nenhum comando de commit, atualização não interativa ou reboot é enviado.
- O WUA é usado apenas para pesquisa e sua atualização automática é desabilitada nessa instância. A fonte escolhida é Windows Update; Microsoft Update não é habilitado ou registrado.
- Se `wuauserv` não estiver em execução, a consulta fica bloqueada. O script não inicia serviços implicitamente.
- Inventário de aplicativos usa Registro e leitura de metadados; não consulta a classe MSI que pode provocar reparos. Não executa aplicativos para descobrir suas versões.
- Apenas uma coleta do pacote pode executar por máquina, usando um mutex global.
- O CSV é gravado progressivamente. Falha de uma fonte não apaga os dados de fontes independentes.
- Consultas consomem recursos. Os limites de tempo não autorizam encerrar serviços de produção. No timeout de uma ferramenta Dell, seu PID e os arquivos de saída são registrados; a ferramenta não é morta à força e as etapas seguintes são bloqueadas. Aguarde seu término antes de repetir.
- O pacote mantém instaladores, extrações, resultados e logs. Não faz limpeza automática.

## Base técnica e referências

As referências abaixo foram consultadas durante o planejamento e a implementação, com revisão documental em **26/10/2026**. Cada uma indica qual decisão pode ser conferida e em qual parte do código ela foi implementada. As explicações são resumos; para uma revisão operacional, consulte o documento original e a versão da ferramenta que será executada.

### Dell: versões, comandos e preparação

| Decisão do projeto | Documento e o que ele sustenta | Onde conferir no projeto |
|---|---|---|
| Fixar o DSU 1.5.3 para os ambientes legados previstos. | [Dell — DSU 1.5.3, driver RT3W9](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=rt3w9): identifica o pacote, o SHA-256 e os sistemas/modelos listados pela Dell, incluindo Server 2008 R2 e 2012. A lista publicada não comprova que a combinação específica da frota já foi testada. | [Matriz de perfis](configuracao/compatibilidade.xml), `Get-ReportProfile` em [Ambiente.ps1](modulos/Ambiente.ps1). |
| Utilizar DSU 1.9.2.0 nos ambientes e modelos mais novos previstos. | [Dell — DSU 1.9.2.0, driver 5C2CW](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=5c2cw): informa o instalador, seu SHA-256 e a cobertura publicada, incluindo Server 2012 R2, 2016 e 2019. | [Matriz de perfis](configuracao/compatibilidade.xml), seleção e fallback em [Ambiente.ps1](modulos/Ambiente.ps1). |
| Distinguir consulta de inventário/prévia das operações que aplicam atualizações. | [Dell — comandos do DSU 1.5.3](https://www.dell.com/support/manuals/en-ly/system-update-v1.5.3/dsu_ug_1.5.3/updating-the-system-using-dsu?guid=guid-f28ee8de-b6ca-4ce1-9f82-93cdc2167a02&lang=en-us) e [Dell — preview da família DSU 1.9](https://www.dell.com/support/manuals/en-us/system-update/dsu_1.9/preview?guid=guid-2f7639ae-e75d-445c-9891-4e980f674861&lang=en-us) descrevem as opções de consulta. A chamada e a saída de cada versão distribuída ainda precisam ser conferidas no piloto. | Lista fechada `Get-ReportNativeArguments` em [Comum.ps1](modulos/Comum.ps1); execução em [DellUpdate.ps1](modulos/DellUpdate.ps1). O perfil legado usa `--preview`; o moderno usa `--compliance`, cujo comportamento real neste pacote ainda não foi homologado. |
| Separar extração, instalação silenciosa e solicitação de reinício. | [Dell DUP — Windows CLI Options](https://www.dell.com/support/manuals/en-ca/dell-update-packages-v17.10.00/dup_17.10_users_guide/Windows-CLI-Options?guid=guid-7e40f460-fdff-4cf9-b26f-e58065d8acbe&lang=en-us): documenta `/e` para extração, `/s` para execução silenciosa, `/r` para solicitar reinício e `/f` para forçar downgrade. **`/s` sozinho executa a instalação; não é um modo de consulta.** | Preparação em [Dependencias.ps1](modulos/Dependencias.ps1) e argumentos em [Comum.ps1](modulos/Comum.ps1). A alternativa de instalação é restrita aos dois instaladores DSU fixados por hash. |
| Verificar a assinatura antes de iniciar binários Dell. | [Microsoft — Get-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature?view=powershell-5.1): descreve a consulta da assinatura e de seu estado. Os hashes de referência vêm das páginas Dell acima. Assinatura válida e hash correspondente verificam origem/integridade; não demonstram ausência de efeitos operacionais. | `Assert-ReportDellBinary`, `Get-ReportSha256` e restrição de hashes em [Comum.ps1](modulos/Comum.ps1); conferência do cache/download em [Dependencias.ps1](modulos/Dependencias.ps1). |

**Limite da preparação portátil:** a opção documentada de extrair um DUP não garante que o conteúdo do DSU possa funcionar diretamente como aplicativo portátil. Essa tentativa e a alternativa de instalação são decisões desta implementação e permanecem pendentes de validação real. A instalação do complemento pode alterar o sistema mesmo sem aplicar firmware ou patches.

### Microsoft: consulta de atualizações e inventário

| Decisão do projeto | Documento e o que ele sustenta | Onde conferir no projeto |
|---|---|---|
| Pesquisar atualizações por WUA. | [Microsoft — IUpdateSearcher](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdatesearcher) descreve `BeginSearch`/`EndSearch`; [critérios de Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search) explicam `IsInstalled`, `IsHidden`, tipos de atualização e tratamento de versões substituídas. | [WindowsUpdate.ps1](modulos/WindowsUpdate.ps1): pesquisa separada de pendentes visíveis e ocultas; leitura de resultados e avisos. |
| Escolher o Windows Update como fonte da consulta. | [Microsoft — enumeração ServerSelection](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/aa387280%28v%3Dvs.85%29): define `ssWindowsUpdate = 2` e distingue o serviço de um servidor corporativo gerenciado e de outras fontes. | `ServerSelection = 2` em [WindowsUpdate.ps1](modulos/WindowsUpdate.ps1). Essa escolha não equivale a habilitar Microsoft Update para todos os produtos Microsoft. |
| Impedir a atualização automática do próprio WUA pela instância de pesquisa. | [Microsoft — CanAutomaticallyUpgradeService](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-uamg/0acba87e-7c0e-4916-8ad2-24ad919b2f7d): documenta a atribuição de `false` para impedir esse mecanismo antes da busca. A propriedade não desativa políticas ou tarefas de atualização já existentes no servidor. | `CanAutomaticallyUpgradeService = $false` em [WindowsUpdate.ps1](modulos/WindowsUpdate.ps1). |
| Solicitar cancelamento de uma busca, sem encerrar o serviço Windows Update. | [Microsoft — ISearchJob::RequestAbort](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-isearchjob-requestabort): define uma solicitação de cancelamento da pesquisa assíncrona. Não é uma garantia de encerramento instantâneo. | Controle de tempo e `RequestAbort()` em [WindowsUpdate.ps1](modulos/WindowsUpdate.ps1). |
| Inventariar programas pelo Registro e evitar `Win32_Product`. | [Microsoft — Working with software installations](https://learn.microsoft.com/en-us/powershell/scripting/samples/working-with-software-installations?view=powershell-7.6): apresenta a chave `Uninstall`, suas limitações de cobertura e o risco de consultas `Win32_Product` provocarem verificações/reparos MSI. | Leitura de chaves com `OpenSubKey(..., $false)` em [Aplicativos.ps1](modulos/Aplicativos.ps1). A cobertura adicional por serviços é uma escolha do projeto. |
| Coletar fabricante/modelo e versões de drivers por WMI. | [Microsoft — Win32_ComputerSystem](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem) documenta fabricante/modelo; [Win32_PnPSignedDriver](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/whqlprov/win32-pnpsigneddriver) documenta informações como dispositivo, fornecedor e versão do driver. Essas classes não determinam, sozinhas, a existência de uma atualização. | [Ambiente.ps1](modulos/Ambiente.ps1) e [Inventario.ps1](modulos/Inventario.ps1). |

### Relato de fórum utilizado como referência de saída

O tópico da [Dell Community sobre repetição de atualização do iDRAC no DSU](https://www.dell.com/community/en/conversations/systems-management-general/linux-dsu-latest-idrac-upgrade-loop-for-the-last-month-on-at-least-all-of-my-r640-r6515-and-r6615-servers/66326cc833543c7c811de24e) contém saídas de inventário, preview e comparação de versões, além de um relato de atualização oferecida para uma versão já instalada. Ele foi consultado como exemplo público de formato e de possível divergência a investigar.

**Esse relato é de Linux/RHEL com DSU 2.0.2.3**, diferente dos Windows e DSU distribuídos aqui. Ele não comprova compatibilidade nem segurança da versão 1 deste script. Os exemplos em [testes/fixtures](testes/fixtures) são sintéticos; a aprovação desses testes não transforma o relato em teste real da frota. As recomendações operacionais do tópico não foram incorporadas como ações automáticas.

### O que a documentação comprova e o que depende de revisão

| Evidência | O que permite concluir | O que ainda não permite concluir |
|---|---|---|
| Manuais de APIs e opções de linha de comando | O fabricante documenta a finalidade da operação consultada. | Que esta implementação inteira esteja correta ou sem impacto no servidor. |
| Listas Dell de sistemas/modelos e hashes | Existe uma referência publicada para selecionar e conferir o pacote. | Que toda combinação de hardware, Windows, certificados e dependências da frota funcione. |
| [Validação local registrada](docs/VALIDACAO.md) e [testes automatizados](testes/Testar.ps1) | Os cenários descritos foram verificados no ambiente local; os arquivos Dell foram conferidos. | Que os coletores reais ou a instalação/extração tenham sido homologados em produção. |
| Revisão do código e [piloto acompanhado](docs/PILOTO.md) | Permitem avaliar o comportamento efetivo e registrar evidências para a liberação interna. | Que futuras versões de catálogos, ferramentas ou do script estejam automaticamente homologadas. |

São decisões próprias do projeto: a lista fechada de operações, o bloqueio de serviço parado, a seleção/fallback dos perfis, os parsers, os estados do CSV, o mutex e os limites de tempo. A documentação de terceiros não certifica essas decisões. A revisão deve conferir sua implementação em [Principal.ps1](Principal.ps1), [Comum.ps1](modulos/Comum.ps1) e nos coletores indicados acima, e comparar o CSV com as evidências originais. **A liberação para produção deve se apoiar nessa revisão e no piloto registrado, não apenas neste README ou nos testes simulados.**

## Interpretação

| Status | Significado |
|---|---|
| `Inventariado` | Identificação e versão coletadas; não é uma avaliação de atualização. |
| `Pendente` | A fonte indicou atualização aplicável/upgrade. A instalação depende da análise humana. |
| `DisponivelParaAnalise` | O preview Dell listou uma opção do catálogo. Pode exigir avaliação de compatibilidade e de versão. |
| `OcultaParaAnalise` | Atualização Microsoft oculta; pode incluir uma versão substituída. |
| `ConformeCatalogo` | Versão igual àquela indicada pelo catálogo Dell; não atesta ausência de vulnerabilidades. |
| `VersaoInferiorNoCatalogo` | Dell indicou downgrade. Não é recomendação de aplicá-lo. |
| `SemPendencias` | Consulta reconhecida e bem-sucedida não encontrou itens na fonte consultada. |
| `Parcial`, `Falha`, `Bloqueado` | A consulta está incompleta ou não foi executada com sucesso. Não equivalem a servidor atualizado. |
| `NaoAplicavel` | Coletor não corresponde ao ambiente, por exemplo DSU em equipamento não Dell. |
| `NaoExecutado` | Etapa não solicitada no modo escolhido. |

Códigos de saída: **0** = etapas solicitadas concluídas; **2** = relatório parcial; **1** = falha de inicialização/execução/finalização. Código zero não significa servidor atualizado. O modo Inventario não comprova funcionamento de WUA/DSU e a demonstração usa somente dados fictícios.

O CSV usa `;`, UTF-8 com BOM e uma linha por item/resultado. Cada linha contém a identificação do servidor. Campos não aplicáveis ficam vazios e valores ausentes de aplicativos aparecem como `Nao informado`. Campos textuais potencialmente interpretados como fórmulas recebem um apóstrofo de proteção.

## Cobertura e validação

Leia [a matriz de compatibilidade](docs/COMPATIBILIDADE.md) e [o roteiro do piloto](docs/PILOTO.md). Os cinco Windows são alvos de compatibilidade, não ambientes já homologados. Os testes executados no desenvolvimento usam PowerShell 5.1 e simulações. Não foi realizado teste em um servidor de produção.

A coleta de aplicativos cobre o Registro da máquina, hives de usuários já carregados e metadados de executáveis locais associados a serviços. Hives descarregados não são montados; portáteis não registrados não são varridos indiscriminadamente. Produto/edição só é preenchido quando há informação específica; não é deduzido do nome.

O inventário de drivers é geral; comparação de firmware/driver de fabricantes diferentes da Dell não está implementada. Componentes que não constem do catálogo Dell podem não ter atualização identificada. A data do catálogo não é inventada a partir da data da coleta: quando não exposta pela consulta, é marcada como não informada nas evidências.

Windows antigos podem falhar por componentes WUA, TLS, certificados ou catálogos sem cobertura. Esses erros devem ser analisados; um pacote autocontido não consegue corrigir toda condição legada sem alterar o sistema.

## Desenvolvimento e empacotamento

Em uma máquina de desenvolvimento com Windows PowerShell 5.1:

```powershell
.\testes\Testar.ps1
.\Empacotar.ps1
```

O empacotador confere/obtém os complementos, copia somente as pastas do produto e cria um ZIP com manifesto de arquivos e um SHA-256 externo em `dist`. Ele não inclui `.git`, resultados nem extrações locais. Os instaladores não são versionados no Git.

`Empacotar.ps1 -SemComplementos` cria uma variante bootstrap que obterá os complementos na primeira execução. Ela depende de acesso aos hosts Dell e não é a opção preferida para servidores legados.

O modo de demonstração aceita `-CenarioDemo Normal`, `FalhaWindows`, `SemPendencias` e `SaidaDellDesconhecida` para examinar diferentes relatórios.
