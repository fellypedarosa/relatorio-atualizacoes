# Roteiro do piloto em produção

O piloto deve ser autorizado explicitamente para o servidor e o período escolhidos. A aprovação de desenvolvimento não inicia esse teste.

1. Identificar o servidor e o responsável que acompanhará a execução. Registrar Windows, modelo, função de produção e limites acordados de consumo/duração.
2. Conferir o SHA-256 do ZIP entregue, extrair a pasta completa localmente e revisar quais complementos serão preparados. Não substituir um DSU existente sem revisão quando o pacote registrar essa condição.
3. Executar `Iniciar.cmd -Modo Inventario` como administrador. Conferir identificação, aplicativos e drivers com as informações do servidor. Observar consumo e registros de falha.
4. Revisar os resultados e autorizar a consulta completa, incluindo eventual preparação do DSU, antes de executar `Iniciar.cmd`.
5. Durante a execução, acompanhar os logs e o consumo de recursos. Se houver necessidade de interromper, cancelar a coleta pelo terminal; não encerrar serviços compartilhados. No timeout, observar o PID informado e aguardar o término do processo Dell.
6. Conferir o CSV com as saídas WUA e DSU em `evidencias`. Verificar que faltas de cobertura estão explícitas e que aplicativos aparecem somente como inventário.
7. Registrar método de preparação do DSU, duração, consumo observado, falhas e diferenças de interpretação, sem incluir credenciais.
8. Após os ajustes necessários, repetir nos outros sistemas/famílias de hardware antes de declarar suporte a toda a frota.

Aceite do piloto: execução sem ações de interrupção da produção, resultado conferível com as fontes, preparação dentro do procedimento aprovado e falhas corretamente visíveis. Alterações no Windows, nos serviços ou nas políticas ficam sujeitas a decisão separada.
