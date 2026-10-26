function ConvertFrom-ReportDsuInventory {
    param([string]$Text)
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*\d+\.\s*(?<kind>[^,]+),\s*(?<name>.+?)\s*\(\s*Version\s*:\s*(?<version>[^)]+)\)\s*$') {
            New-ReportObject @{ Name=$matches['name'].Trim(); Version=$matches['version'].Trim(); Type=$matches['kind'].Trim() }
        }
    }
}

function ConvertFrom-ReportDsuUpdates {
    param([string]$Text, [object[]]$Inventory = @())
    $records = New-Object System.Collections.ArrayList
    $name = ''
    $unparsed = 0
    $candidateCount = 0
    $recognizedHeader = $Text -match '(?im)Update Preview|Details|Current Version\s*:'
    $explicitEmpty = $Text -match '(?im)\bNo (?:applicable |available |upgradable )?updates (?:are )?(?:available|found|applicable|required)|\bNo updates to (?:apply|install)|\b(?:system is|components are) up.to.date\b'
    foreach ($line in ($Text -split '\r?\n')) {
        # Actual preview table: # : Type : Component : Version : Filename.
        if ($line -match '^\s*\d+\s+:\s+(?<kind>.+?)\s+:\s+(?<name>.+?)\s+:\s+(?<version>.+?)\s+:\s+(?<file>.+?)\s*$') {
            $candidateCount++
            $component = $matches['name'].Trim()
            $target = $matches['version'].Trim()
            $kind = $matches['kind'].Trim()
            $file = $matches['file'].Trim()
            $current = ''
            $matching = @($Inventory | Where-Object { $_.Name -eq $component })
            if ($matching.Count -eq 1) { $current = $matching[0].Version }
            [void]$records.Add((New-ReportObject @{ Name=$component; Current=$current; Available=$target; Type=$kind; Classification=''; Status='DisponivelParaAnalise'; ID=$file; Note='Disponibilidade informada pelo preview. Versao instalada vinculada apenas quando ha correspondencia unica no inventario.' }))
            continue
        }
        # Compliance/legacy multiline component blocks.
        if ($line -match '^\s*Current Version\s*:\s*(?<current>.+?)\s+(?<action>Upgrade to|Downgrade to|Same as|Available Version)\s*:\s*(?<target>[^,\r\n]+)(?:,\s*Criticality\s*:\s*(?<criticality>[^,\r\n]+))?(?:,\s*Type\s*:\s*(?<kind>[^,\r\n]+))?\s*$') {
            if ($name -eq '') { $unparsed++; continue }
            $status = 'DisponivelParaAnalise'
            $action = $matches['action']
            if ($action -eq 'Upgrade to') { $status = 'Pendente' }
            if ($action -eq 'Downgrade to') { $status = 'VersaoInferiorNoCatalogo' }
            if ($action -eq 'Same as') { $status = 'ConformeCatalogo' }
            $currentVersion = $matches['current'].Trim()
            $targetVersion = $matches['target'].Trim()
            $classification = ''
            $kind = ''
            if ($matches.ContainsKey('criticality')) { $classification = $matches['criticality'].Trim() }
            if ($matches.ContainsKey('kind')) { $kind = $matches['kind'].Trim() }
            [void]$records.Add((New-ReportObject @{ Name=$name; Current=$currentVersion; Available=$targetVersion; Type=$kind; Classification=$classification; Status=$status; ID=''; Note=('Acao informada pela consulta: ' + $action + '. Igualdade de versao significa conformidade com este catalogo, nao ausencia de vulnerabilidades.') }))
            $name = ''
            continue
        }
        if ($line -match '^\s*(?:\[[ *-]?\]\s*)?\d+[.)]?\s+(?<name>\S.*)$') {
            if ($name -ne '') { $unparsed++ }
            $candidateCount++
            $name = $matches['name'].Trim()
            continue
        }
        if ($line -match '^\s*\d+\s*:' -or $line -match '^\s*Current Version\s*:') { $unparsed++ }
    }
    if ($name -ne '') { $unparsed++ }
    $errorText = $Text -replace '(?im)^\s*(?:No errors|0 errors)\s*\.?\s*$', ''
    $errors = $errorText -match '(?im)\berror\b|\bfatal\b|\bfailed\b|\bunable to\b|\bnot supported\b|\bunsupported\b|\bcannot\b'
    $status = 'Concluido'
    if ($unparsed -gt 0 -or $errors -or ($records.Count -eq 0 -and -not $explicitEmpty) -or (-not $recognizedHeader -and -not $explicitEmpty)) { $status = 'Parcial' }
    elseif ($records.Count -eq 0 -and $explicitEmpty) { $status = 'SemPendencias' }
    return (New-ReportObject @{ Records=@($records.ToArray()); Status=$status; Unparsed=$unparsed; CandidateCount=$candidateCount; ExplicitEmpty=$explicitEmpty; ErrorDetected=$errors })
}

function Write-ReportDellUpdates {
    param($Context, $Parsed)
    foreach ($record in $Parsed.Records) {
        $kind = 'Atualizacao'
        if ($record.Status -eq 'ConformeCatalogo') { $kind = 'ComponenteDell' }
        Add-ReportRow $Context @{ tipo_registro=$kind; categoria=('Dell/' + $record.Type); nome_item=$record.Name; fabricante_item='Dell/catalogo'; versao_instalada=$record.Current; versao_disponivel=$record.Available; kb_ou_id=$record.ID; classificacao=$record.Classification; fonte='DSU'; status=$record.Status; observacao=$record.Note }
    }
}

function Invoke-ReportDellUpdate {
    param($Context)
    $profile = Get-ReportProfile $Context.Config $Context.HostInfo.version $Context.HostInfo.build_windows $Context.HostInfo.productType $Context.HostInfo.fabricante_servidor $Context.HostInfo.modelo_servidor
    if ($null -eq $profile) {
        Add-ReportStage $Context 'DellUpdate' 'NaoAplicavel' 'Fabricante diferente de Dell. Firmware de outros fabricantes nao e comparado nesta versao.'
        return
    }
    $dsu = Initialize-ReportDsu $Context $profile
    Add-ReportStage $Context 'ComplementosDell' 'Concluido' ('DSU {0} selecionado automaticamente: {1}' -f $profile.GetAttribute('version'),$dsu)
    $timeout = [int]$Context.Config.Compatibilidade.Limites.consultaSegundos
    $inventoryResult = Invoke-ReportDellProcess $Context $dsu 'Inventory' 'dsu-inventario' $timeout
    $inventory = @(ConvertFrom-ReportDsuInventory $inventoryResult.Output)
    Save-ReportEvidence $Context 'dsu-inventario-interpretado.xml' $inventory
    foreach ($component in $inventory) {
        Add-ReportRow $Context @{ tipo_registro='ComponenteDell'; categoria=('Dell/' + $component.Type); nome_item=$component.Name; fabricante_item='Dell/catalogo'; versao_instalada=$component.Version; fonte='DSU/inventario'; status='Inventariado' }
    }
    if ($inventoryResult.ExitCode -ne 0) {
        Add-ReportStage $Context 'InventarioDell' 'Falha' ('DSU retornou codigo ' + $inventoryResult.ExitCode + '; evidencias preservadas.') $inventory.Count
    } elseif ($inventory.Count -eq 0) {
        Add-ReportStage $Context 'InventarioDell' 'Parcial' 'Inventario retornou zero itens reconhecidos; saida original preservada.'
    } else { Add-ReportStage $Context 'InventarioDell' 'Concluido' 'Inventario Dell coletado.' $inventory.Count }
    $operation = $profile.GetAttribute('operation')
    if (@('Preview','Compliance') -notcontains $operation) { throw 'Operacao de consulta nao permitida no perfil Dell.' }
    $result = Invoke-ReportDellProcess $Context $dsu $operation 'dsu-atualizacoes' $timeout
    $parsed = ConvertFrom-ReportDsuUpdates ($result.Output + [Environment]::NewLine + $result.Error) $inventory
    # Preserve recognized rows even on nonzero exit or partial output.
    Write-ReportDellUpdates $Context $parsed
    Save-ReportEvidence $Context 'dsu-atualizacoes-interpretadas.xml' $parsed
    Save-ReportEvidence $Context 'dsu-fonte.xml' @{
        Perfil=$profile.GetAttribute('id'); Versao=$profile.GetAttribute('version'); Operacao=$operation
        Fonte='Repositorio padrao gerido pelo DSU; URLs efetivas nas saidas e logs Dell'
        DataConsultaUtc=[DateTime]::UtcNow.ToString('o'); DataCatalogo='Nao informada pela interface de consulta; nao inferida da data da coleta'
    }
    if ($result.ExitCode -ne 0) {
        Add-ReportStage $Context 'DellUpdate' 'Falha' ('DSU retornou codigo {0}; linhas reconhecidas={1}. Consulte dsu-atualizacoes.*.txt.' -f $result.ExitCode,$parsed.Records.Count) $parsed.Records.Count
    } else {
        Add-ReportStage $Context 'DellUpdate' $parsed.Status ('Itens={0}; trechos nao interpretados={1}; erro textual={2}. Cobertura limitada ao catalogo retornado; data do catalogo nao confirmada.' -f $parsed.Records.Count,$parsed.Unparsed,$parsed.ErrorDetected) $parsed.Records.Count
    }
}
