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
