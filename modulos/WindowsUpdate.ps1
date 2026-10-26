function ConvertTo-ReportWindowsRow {
    param($Update)
    $hidden = [bool](Get-ReportValue $Update 'Hidden' $false)
    $status = 'Pendente'
    if ($hidden) { $status = 'OcultaParaAnalise' }
    return @{
        tipo_registro='Atualizacao'; categoria=('Microsoft/' + (Get-ReportValue $Update 'Type' 'Software'))
        nome_item=(Get-ReportValue $Update 'Title'); fabricante_item='Microsoft/catalogo Windows Update'
        kb_ou_id=((@(Get-ReportValue $Update 'KBs' @()) -join ',') + ' | ' + (Get-ReportValue $Update 'ID'))
        classificacao=(@(Get-ReportValue $Update 'Categories' @()) -join ', ')
        severidade=(Get-ReportValue $Update 'Severity'); fonte=(Get-ReportValue $Update 'Source' 'Windows Update')
        status=$status; link=(@(Get-ReportValue $Update 'Urls' @()) -join ' | ')
        observacao=('Opcional={0}; oculta={1}; revisao={2}; pode exigir entrada do usuario={3}. Disponibilidade depende da fonte consultada.' -f (Get-ReportValue $Update 'Optional' 'Nao informado'),$hidden,(Get-ReportValue $Update 'Revision'),(Get-ReportValue $Update 'UserInput' 'Nao informado'))
    }
}

function Get-ReportWuaSnapshot {
    param($Update)
    $categories = @()
    for ($index=0; $index -lt $Update.Categories.Count; $index++) {
        $category = $Update.Categories.Item($index)
        $categories += ([string]$category.Name)
    }
    $kbs = @()
    for ($index=0; $index -lt $Update.KBArticleIDs.Count; $index++) { $kbs += ('KB' + $Update.KBArticleIDs.Item($index)) }
    $urls = @()
    for ($index=0; $index -lt $Update.MoreInfoUrls.Count; $index++) { $urls += [string]$Update.MoreInfoUrls.Item($index) }
    $typeName = 'Software'
    if ([int]$Update.Type -eq 2) { $typeName = 'Driver' }
    return (New-ReportObject @{
        Title=[string]$Update.Title; ID=[string]$Update.Identity.UpdateID; Revision=[int]$Update.Identity.RevisionNumber
        KBs=$kbs; Categories=$categories; Severity=[string]$Update.MsrcSeverity
        Type=$typeName; Hidden=[bool]$Update.IsHidden; Optional=[bool]$Update.BrowseOnly
        UserInput=[bool]$Update.InstallationBehavior.CanRequestUserInput; Urls=$urls; Source='Windows Update (ssWindowsUpdate)'
    })
}

function Invoke-ReportWuaSearch {
    param($Context, $Searcher, [string]$Criteria, [string]$Label, [int]$TimeoutSeconds)
    $job = $null
    $completed = $false
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        Write-ReportLog $Context ('WUA consulta: ' + $Criteria)
        $job = $Searcher.BeginSearch($Criteria, $null, $null)
        $nextLog = 15
        while (-not $job.IsCompleted) {
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $Context.StopRequested = $true
                $job.RequestAbort()
                throw 'Tempo de consulta WUA excedido; cancelamento solicitado pela API. Nenhum servico ou processo compartilhado foi encerrado.'
            }
            if ($timer.Elapsed.TotalSeconds -ge $nextLog) { Write-ReportLog $Context ('Aguardando WUA: ' + [int]$timer.Elapsed.TotalSeconds + ' s'); $nextLog += 15 }
            Start-Sleep -Milliseconds 250
        }
        $completed = $true
        $result = $Searcher.EndSearch($job)
        $errors = @()
        for ($index=0; $index -lt $result.Warnings.Count; $index++) {
            $warning = $result.Warnings.Item($index)
            $errors += ('{0}: {1}' -f $warning.HResult, $warning.Message)
        }
        $updates = New-Object System.Collections.ArrayList
        for ($index=0; $index -lt $result.Updates.Count; $index++) {
            $snapshot = Get-ReportWuaSnapshot $result.Updates.Item($index)
            [void]$updates.Add($snapshot)
            Add-ReportRow $Context (ConvertTo-ReportWindowsRow $snapshot)
        }
        $snapshotResult = New-ReportObject @{ ResultCode=[int]$result.ResultCode; Errors=$errors; Updates=@($updates.ToArray()); Criteria=$Criteria; DataUtc=[DateTime]::UtcNow.ToString('o'); Source='Windows Update (ssWindowsUpdate)' }
        Save-ReportEvidence $Context ($Label + '.xml') $snapshotResult
        return $snapshotResult
    } finally {
        $timer.Stop()
        if ($null -ne $job) {
            if (-not $completed) {
                # This is a request to this search only, never to the WUA service.
                try { $job.RequestAbort() } catch { }
            } else { $job.CleanUp() }
        }
    }
}

function Invoke-ReportWindowsUpdate {
    param($Context)
    $service = Get-Service -Name wuauserv -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        Add-ReportStage $Context 'WindowsUpdate' 'Bloqueado' 'Servico Windows Update nao esta em execucao. A coleta nao inicia nem reconfigura servicos; esta condicao requer avaliacao explicita.'
        return
    }
    $session = $null
    $searcher = $null
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'RelatorioServidor/1.0 - somente consulta'
        $searcher = $session.CreateUpdateSearcher()
        $searcher.CanAutomaticallyUpgradeService = $false
        $searcher.ServerSelection = 2
        $searcher.Online = $true
        $searcher.IncludePotentiallySupersededUpdates = $false
        $totalTimer = [Diagnostics.Stopwatch]::StartNew()
        $budget = [int]$Context.Config.Compatibilidade.Limites.consultaSegundos
        $normal = Invoke-ReportWuaSearch $Context $searcher 'IsInstalled=0 and IsHidden=0' 'windows-pendentes' $budget
        $remaining = $budget - [int]$totalTimer.Elapsed.TotalSeconds
        if ($remaining -le 0) { throw 'Consulta de atualizacoes ocultas nao iniciada: orcamento total de tempo esgotado.' }
        $searcher.IncludePotentiallySupersededUpdates = $true
        $hidden = Invoke-ReportWuaSearch $Context $searcher 'IsInstalled=0 and IsHidden=1' 'windows-ocultas' $remaining
        $count = $normal.Updates.Count + $hidden.Updates.Count
        if ($normal.ResultCode -ne 2 -or $hidden.ResultCode -ne 2 -or $normal.Errors.Count -gt 0 -or $hidden.Errors.Count -gt 0) {
            Add-ReportStage $Context 'WindowsUpdate' 'Parcial' ('WUA nao confirmou sucesso integral. Resultados={0}/{1}; avisos={2}. Consulte as evidencias.' -f $normal.ResultCode,$hidden.ResultCode,(($normal.Errors + $hidden.Errors) -join ' | ')) $count
        } elseif ($count -eq 0) {
            Add-ReportStage $Context 'WindowsUpdate' 'SemPendencias' 'Nenhuma atualizacao aplicavel retornada pelo Windows Update. Isso nao atesta suporte do sistema nem cobertura de outros produtos Microsoft.'
        } else {
            Add-ReportStage $Context 'WindowsUpdate' 'Concluido' ('Pendentes={0}; ocultas para analise={1}. Ocultas podem incluir atualizacoes substituidas. Fonte: Windows Update; Microsoft Update nao e habilitado ou registrado.' -f $normal.Updates.Count,$hidden.Updates.Count) $count
        }
    } finally {
        foreach ($com in @($searcher,$session)) {
            if ($null -ne $com -and [Runtime.InteropServices.Marshal]::IsComObject($com)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com) }
        }
    }
}
