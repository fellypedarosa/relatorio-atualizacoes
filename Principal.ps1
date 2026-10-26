#requires -version 2.0
[CmdletBinding()]
param(
    [ValidateSet('Completo','Inventario','Demonstracao','Preparar')][string]$Modo = 'Completo',
    [string]$PastaSaida = '',
    [ValidateSet('Normal','FalhaWindows','SemPendencias','SaidaDellDesconhecida')][string]$CenarioDemo = 'Normal'
)

$ErrorActionPreference = 'Stop'
$reportRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($reportModule in @('Comum','Ambiente','Dependencias','Inventario','Aplicativos','WindowsUpdate','DellUpdate','Demonstracao')) {
    . (Join-Path $reportRoot ('modulos\' + $reportModule + '.ps1'))
}
$reportContext = $null
$reportMutex = $null
$reportLock = $false
$reportExit = 1
try {
    if ($PastaSaida -eq '') { $PastaSaida = Join-Path $reportRoot 'resultados' }
    $PastaSaida = [IO.Path]::GetFullPath($PastaSaida)
    if ($Modo -eq 'Completo' -or $Modo -eq 'Inventario') {
        # Machine-wide lock, even if the package is copied to another directory.
        $reportMutex = New-Object System.Threading.Mutex($false, 'Global\RelatorioServidorV1')
        try { $reportLock = $reportMutex.WaitOne(0, $false) }
        catch [System.Threading.AbandonedMutexException] { $reportLock = $true }
        if (-not $reportLock) { throw 'Outra coleta ja esta em execucao neste servidor.' }
    }
    $reportContext = New-ReportContext $reportRoot $PastaSaida $Modo
    $reportContext.Config = Read-ReportXml (Join-Path $reportRoot 'configuracao\compatibilidade.xml')
    Write-ReportLog $reportContext ('Pacote {0}; modo {1}; pasta {2}' -f $reportContext.Config.Compatibilidade.packageVersion,$Modo,$reportContext.Directory)
    switch ($Modo) {
        'Demonstracao' { Invoke-ReportDemonstration $reportContext $CenarioDemo }
        'Preparar' {
            foreach ($profile in $reportContext.Config.Compatibilidade.Perfis.Perfil) {
                Invoke-ReportStage $reportContext ('Pacote/' + $profile.GetAttribute('id')) {
                    $package = Get-ReportDellPackage $reportContext $profile
                    Add-ReportStage $reportContext ('Pacote/' + $profile.GetAttribute('id')) 'Concluido' ('Download/cache conferido por SHA-256: ' + $package)
                }
            }
            if ($reportContext.Issues -eq 0) { Write-ReportLog $reportContext 'Preparacao de arquivos concluida; nenhum executavel baixado foi iniciado.' }
            else { Write-ReportLog $reportContext 'Preparacao de arquivos incompleta; consulte as falhas registradas.' 'AVISO' }
        }
        default {
            # Host identification is mandatory; do not select a profile on unknown OS/model.
            Initialize-ReportHost $reportContext
            Invoke-ReportStage $reportContext 'Drivers' { Invoke-ReportDrivers $reportContext }
            Invoke-ReportStage $reportContext 'Aplicativos' { Invoke-ReportApplications $reportContext }
            Invoke-ReportStage $reportContext 'FuncoesWindows' { Invoke-ReportFeatures $reportContext }
            if ($Modo -eq 'Completo') {
                Invoke-ReportStage $reportContext 'WindowsUpdate' { Invoke-ReportWindowsUpdate $reportContext }
                Invoke-ReportStage $reportContext 'DellUpdate' { Invoke-ReportDellUpdate $reportContext }
            } else {
                Add-ReportStage $reportContext 'WindowsUpdate' 'NaoExecutado' 'Modo Inventario: consulta de atualizacoes nao solicitada.'
                Add-ReportStage $reportContext 'DellUpdate' 'NaoExecutado' 'Modo Inventario: preparacao e consulta Dell nao solicitadas.'
            }
        }
    }
    $reportExit = 0
    if ($reportContext.Issues -gt 0) { $reportExit = 2 }
} catch {
    if ($null -ne $reportContext) {
        try { Add-ReportStage $reportContext 'Execucao' 'Falha' $_.Exception.Message } catch { Write-Host $_.Exception.Message }
    } else { Write-Host ('Falha: ' + $_.Exception.Message) }
    $reportExit = 1
} finally {
    if ($null -ne $reportContext) {
        try {
            Add-ReportRow $reportContext @{ tipo_registro='Resumo'; categoria='Execucao'; nome_item='Resultado final'; fonte='RelatorioServidor'; status=(@{0='Concluido';1='Falha';2='Parcial'}[$reportExit]); observacao=('Codigo={0}; ocorrencias={1}; modo={2}; linhas anteriores={3}. Consulte os resultados de cada fonte.' -f $reportExit,$reportContext.Issues,$Modo,$reportContext.RowCount) }
            Save-ReportEvidence $reportContext 'resumo.xml' @{ CodigoSaida=$reportExit; Modo=$Modo; Servidor=$reportContext.HostInfo; Etapas=@($reportContext.Stages.ToArray()); FinalizadoUtc=[DateTime]::UtcNow.ToString('o') }
            Write-ReportLog $reportContext ('Finalizado; codigo {0}; CSV: {1}' -f $reportExit,$reportContext.CsvPath)
            Write-Host ('Relatorio: ' + $reportContext.CsvPath)
        } catch { $reportExit = 1; Write-Host ('Falha ao finalizar o relatorio: ' + $_.Exception.Message) }
        finally { $reportContext.Writer.Dispose() }
    }
    if ($reportLock -and $null -ne $reportMutex) { $reportMutex.ReleaseMutex() }
    if ($null -ne $reportMutex) { $reportMutex.Dispose() }
}
exit $reportExit
