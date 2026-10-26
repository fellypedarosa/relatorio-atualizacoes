# Matriz da versão 1

| Windows alvo | Versão/build | Perfil Dell inicial | Estado |
|---|---|---|---|
| Server 2008 R2 | 6.1 / 7600–7601 | DSU 1.5.3 | Seleção automatizada e documentada; teste real pendente. |
| Server 2012 | 6.2 / 9200 | DSU 1.5.3 | Seleção automatizada e documentada; teste real pendente. |
| Server 2012 R2 | 6.3 / 9600 | DSU 1.9.2.0; 1.5.3 para modelos antigos previstos | Teste real pendente. |
| Server 2016 | 10.0 / 14393 | DSU 1.9.2.0; 1.5.3 para modelos antigos previstos | Teste real pendente. |
| Server 2019 | 10.0 / 17763 | DSU 1.9.2.0 | Teste real pendente. |

Os perfis são intencionalmente fixados para compatibilidade histórica. Não representam a versão mais recente do DSU. A lista de modelos é conservadora e inclui os PowerEdge explicitados no manifesto. Combinações ausentes são relatadas antes de qualquer instalação, em vez de tentar executar uma ferramenta sem evidência de compatibilidade. Outros modelos e variações, inclusive Storage/NX, exigem revisão da matriz uma vez para todo o pacote.

O runtime visa sintaxe PowerShell 2.0, WMI clássico e APIs .NET disponíveis em sistemas legados. Não instala/habilita PowerShell 2.0 nos demais Windows e não força `-Version 2`. O empacotador e os testes são ferramentas de desenvolvimento e exigem PowerShell 5.1.

WUA deve estar funcional, seus certificados e a comunicação com Windows Update devem ser aceitos pelo sistema. O script não altera WSUS, políticas de atualização, SCHANNEL ou certificados. A preparação de arquivos usa TLS 1.2 no processo e restaura o valor anterior; servidores cujo runtime não o suporte precisam receber o pacote já com os complementos. DSU continua precisando acessar seu catálogo/coletor. A ausência de novos patches para um sistema sem suporte não é uma conclusão de segurança.

## Fontes utilizadas

- [DSU 1.5.3: sistemas, modelos, instalador e SHA-256 oficial](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=rt3w9).
- [DSU 1.9.2.0: sistemas, modelos, instalador e SHA-256 oficial](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=5c2cw).
- [DSU 1.5.3: comandos](https://www.dell.com/support/manuals/en-ly/system-update-v1.5.3/dsu_ug_1.5.3/updating-the-system-using-dsu?guid=guid-f28ee8de-b6ca-4ce1-9f82-93cdc2167a02&lang=en-us).
- [DSU 1.9: consulta de preview](https://www.dell.com/support/manuals/en-us/system-update/dsu_1.9/preview?guid=guid-2f7639ae-e75d-445c-9891-4e980f674861&lang=en-us).
- [Dell DUP: extração e opções de linha de comando](https://www.dell.com/support/manuals/en-ca/dell-update-packages-v17.10.00/dup_17.10_users_guide/Windows-CLI-Options?guid=guid-7e40f460-fdff-4cf9-b26f-e58065d8acbe&lang=en-us).
- [WUA: critérios da consulta](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search).
- [WUA: impedir autoatualização do agente nessa consulta](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-uamg/0acba87e-7c0e-4916-8ad2-24ad919b2f7d).
- [Microsoft: inventário por Registro e efeitos colaterais de consultas MSI](https://learn.microsoft.com/en-us/powershell/scripting/samples/working-with-software-installations?view=powershell-7.6).

## Limites ainda não homologados

- Extração portátil versus instalação do DSU e comportamento real de seus coletores em cada família de hardware.
- Saídas reais das duas versões do DSU nos servidores da frota. Os parsers têm testes sintéticos de tabelas, blocos e falhas e rejeitam saídas desconhecidas como parciais.
- PowerShell 2.0 e 3.0 reais, inclusive parâmetros e adaptações COM/WMI dos hosts legados.
- Consumo de recursos e tempo das consultas em produção.
- Cobertura do catálogo Dell atual para hardware antigo e funcionamento do Windows Update nos hosts legados.

Resultados locais devem ser registrados em `VALIDACAO.md`; homologação depende dos pilotos, não da mera existência da seleção de perfis.
