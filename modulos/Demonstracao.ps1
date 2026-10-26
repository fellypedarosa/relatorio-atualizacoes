function Invoke-ReportDemonstration {
    param($Context, [string]$Scenario)
    $Context.HostInfo.servidor = 'DEMO-SRV01'
    $Context.HostInfo.fabricante_servidor = 'Dell Inc. (SIMULADO)'
    $Context.HostInfo.modelo_servidor = 'PowerEdge R730 (SIMULADO)'
    $Context.HostInfo.service_tag = 'SIMULADO'
    $Context.HostInfo.windows = 'Windows Server 2019 (SIMULADO)'
    $Context.HostInfo.build_windows = '17763'
    Add-ReportRow $Context @{ tipo_registro='Servidor'; categoria='Inventario'; nome_item='DEMO-SRV01'; status='Inventariado'; fonte='SIMULACAO'; observacao='Dados ficticios. Nenhuma consulta ao host, rede, WUA ou DSU foi executada.' }
    $fixture = Read-ReportXml (Join-Path $Context.Root 'testes\fixtures\aplicativos.xml')
    $apps = @()
    foreach ($app in $fixture.Aplicativos.Aplicativo) { $apps += New-ReportObject @{ Name=$app.GetAttribute('nome'); Manufacturer=$app.GetAttribute('fabricante'); Version=$app.GetAttribute('versao'); Edition=$app.GetAttribute('edicao'); Architecture='x64'; Scope='Simulado'; Source='SIMULACAO' } }
    $apps = @(Select-ReportApplications $apps)
    Write-ReportApplications $Context $apps
    Add-ReportStage $Context 'Aplicativos' 'Concluido' 'Inventario ficticio para demonstrar a apresentacao.' $apps.Count
    if ($Scenario -eq 'FalhaWindows') {
        Add-ReportStage $Context 'WindowsUpdate' 'Falha' 'SIMULACAO: fonte Microsoft indisponivel; nao significa ausencia de atualizacoes.'
    } elseif ($Scenario -eq 'SemPendencias') {
        Add-ReportStage $Context 'WindowsUpdate' 'SemPendencias' 'SIMULACAO: consulta bem-sucedida com zero resultados.'
    } else {
        $update = New-ReportObject @{ Title='Atualizacao de seguranca ficticia'; ID='00000000-0000-0000-0000-000000000001'; KBs=@('KB-DEMO'); Type='Software'; Categories=@('Security Updates'); Severity='Critical'; Hidden=$false; Optional=$false; Source='SIMULACAO' }
        Add-ReportRow $Context (ConvertTo-ReportWindowsRow $update)
        Add-ReportStage $Context 'WindowsUpdate' 'Concluido' 'Atualizacao ficticia.' 1
    }
    $file = 'dsu-compliance.txt'
    if ($Scenario -eq 'SemPendencias') { $file = 'dsu-vazio.txt' }
    if ($Scenario -eq 'SaidaDellDesconhecida') { $file = 'dsu-desconhecido.txt' }
    $text = [IO.File]::ReadAllText((Join-Path $Context.Root ('testes\fixtures\' + $file)))
    $parsed = ConvertFrom-ReportDsuUpdates $text
    Write-ReportDellUpdates $Context $parsed
    Add-ReportStage $Context 'DellUpdate' $parsed.Status 'SIMULACAO: interpretacao de fixture, sem executar ferramenta Dell.' $parsed.Records.Count
    Save-ReportEvidence $Context 'demonstracao.xml' @{ Cenario=$Scenario; DadosFicticios=$true; ConsultaReal=$false }
}
