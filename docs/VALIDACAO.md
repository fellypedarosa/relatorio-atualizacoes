# Validação local — 26/10/2026

## Verificado

- Windows PowerShell 5.1.26100.9711, em máquina de desenvolvimento; sem consultas reais a servidores.
- 31 testes automatizados aprovados com `powershell.exe -NoLogo -NoProfile -File .\testes\Testar.ps1`.
- Demonstração integrada: sucesso, falha Microsoft, ausência de pendências e saída Dell desconhecida; códigos de saída e CSV conferidos.
- Critérios de seleção de perfil para os cinco sistemas alvo e fallback de modelo antigo no Server 2016.
- Parsing sintético de inventário, preview e compliance Dell; versões, classificações, downgrade, MAC no nome, erro textual, código de erro, saída vazia/truncada e desconhecida.
- Pesquisa WUA simulada: captura de resultados/avisos, snapshot de driver, cancelamento e bloqueio quando o serviço está parado.
- Preservação do CSV em falhas, Unicode, BOM, aspas, quebras, separador e proteção contra fórmulas no Excel.
- Restrições de origem de download, SHA-256, cache adulterado, caminhos, DTD e operações nativas.
- Os dois instaladores oficiais foram baixados no modo `Preparar`, conferidos por SHA-256 e encontrados com Authenticode `Valid`, assinante `Dell Inc.`.

| Complemento | SHA-256 conferido |
|---|---|
| DSU 1.5.3 | `2b437318e3c71d89d567498ef756f2fbcdfc4b9201406ee038efb0a2ba86fcf1` |
| DSU 1.9.2.0 | `2905a5c8717a9806f76fa88af340fd4747a45c5bd846849ec0bd336ece7f6cbe` |

O download inicialmente falhou dentro do ambiente restrito. A preparação foi repetida com acesso autorizado à rede e terminou com código zero para ambos os arquivos. Os instaladores ficam fora do Git e entram no ZIP completo.

## Não homologado

- A tentativa de extração `/s /e=...` foi recusada pelo Windows antes da criação do processo, por exigir elevação administrativa. A sessão local permanece sem elevação de administrador mesmo fora do sandbox. Nenhuma instalação foi executada.
- Nenhum `DSU.exe` foi executado para inventário/compliance/preview reais; não houve consulta real ao Windows Update nem coleta de inventário da máquina de desenvolvimento.
- Não foi realizado teste em Windows Server 2008 R2, 2012, 2012 R2, 2016 ou 2019. A seleção documentada não substitui teste real.
- Não foram medidos consumo, duração e efeitos de preparação em servidores de produção. Saídas particulares dos equipamentos da frota podem exigir ampliação dos parsers.

O pacote pode ser inspecionado e demonstrado localmente. O passo seguinte de homologação é o piloto explicitamente autorizado conforme `PILOTO.md`.

## Correção 1.0.1 — 27/10/2026

- Evidências fornecidas pelo analista no HYPERV02 (PowerEdge R530, Windows Server 2016) mostraram `ExitCode` nulo nas chamadas Dell do pacote 1.0.0. A extração foi tratada como falha antes da instalação/consulta; a repetição após desinstalação manual do DSU apresentou o mesmo defeito. O inventário foi concluído. As consultas completas não foram homologadas.
- `Invoke-ReportDellProcess` agora adquire o handle nativo antes de `WaitForExit`, registra o código no log e preserva o resultado em XML. Se o código permanecer nulo, mantém as evidências e bloqueia a continuidade com mensagem explícita de resultado indeterminado. Referência: [PowerShell #5421](https://github.com/PowerShell/PowerShell/issues/5421).
- 33 testes aprovados, zero falhas, com `powershell.exe -NoLogo -NoProfile -File .\testes\Testar.ps1` no Windows PowerShell 5.1 de desenvolvimento. Os novos testes incluem dez execuções locais de `cmd.exe` com saídas redirecionadas (cinco com retorno 0 e cinco com retorno 7), conferência do XML e um processo simulado com código ausente. Não executam instaladores nem coletores Dell.
- Essa validação não demonstra que a extração/instalação DSU terá sucesso no servidor. É necessário repetir o piloto com o novo pacote e conferir os códigos e as saídas reais. O bloqueio por serviço Windows Update parado permanece independente desta correção.

## Correção 1.0.2 — 27/10/2026

- No piloto 1.0.1 no HYPERV02, a extração retornou 0 e a instalação foi iniciada, mas `ReadAllText` falhou ao ler `dsu-instalacao.stdout.txt` ainda aberto. As evidências não permitem concluir o resultado da instalação nem identificar qual processo mantinha o arquivo aberto.
- O código do processo e os caminhos de saída agora são preservados antes da leitura. Ambos os arquivos precisam ser liberados para acesso exclusivo antes de interpretar conteúdo. Erros de compartilhamento/bloqueio são repetidos dentro do prazo da operação; outros erros são propagados. Um timeout mantém as evidências com `OutputComplete=false`, bloqueia a continuidade e não encerra processos.
- Foi removida a espera adicional sem limite de tempo em `WaitForExit()`. A espera do processo e a liberação dos arquivos usam o orçamento da operação. Essa verificação dos arquivos não equivale a comprovar o término de todos os processos descendentes; a versão instalada continua sendo verificada ao final da preparação.
- 35 testes passaram no Windows PowerShell 5.1 de desenvolvimento. Os novos cenários verificam a espera por outro processo que libera um arquivo após escrever a saída final e o bloqueio persistente com preservação do código 7 e dos caminhos das evidências. Não houve instalação DSU nem consulta real ao servidor no desenvolvimento.
- Preparação/consulta DSU no servidor continuam pendentes de homologação. Antes de nova execução, é necessário aguardar operações Dell anteriores terminarem e conferir a instalação existente.
