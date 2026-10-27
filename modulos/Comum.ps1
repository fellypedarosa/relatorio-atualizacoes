# Runtime code uses PowerShell 2.0 syntax and .NET APIs available on legacy hosts.
Set-StrictMode -Version 2.0

function Get-ReportValue {
    param($Object, [string]$Name, $Default = '')
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
    } else {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property -and $null -ne $property.Value) { return $property.Value }
    }
    return $Default
}

function New-ReportObject {
    param([hashtable]$Values)
    return (New-Object PSObject -Property $Values)
}

function Read-ReportXml {
    param([string]$Path)
    $settings = New-Object System.Xml.XmlReaderSettings
    # Prohibit external entities on .NET 2.0 as well as newer runtimes.
    $settings.ProhibitDtd = $true
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } finally { $reader.Close() }
}

function Write-ReportLog {
    param($Context, [string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, $Message
    [System.IO.File]::AppendAllText($Context.LogPath, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host $line
}

function ConvertTo-ReportCsvCell {
    param($Value)
    $text = [string]$Value
    # Leading whitespace/control characters must not hide an Excel formula.
    if ($text -match '^[\s\x00-\x1f]*[=+@-]' -or $text -match '^[\t\r\n]') { $text = "'" + $text }
    return ('"' + $text.Replace('"', '""') + '"')
}

function New-ReportContext {
    param([string]$Root, [string]$OutputRoot, [string]$Mode)
    $hostName = [Environment]::MachineName -replace '[^A-Za-z0-9_.-]', '_'
    $runId = '{0}_{1}_{2}' -f $hostName, [DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff'), [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $directory = Join-Path $OutputRoot $runId
    $evidence = Join-Path $directory 'evidencias'
    [void][System.IO.Directory]::CreateDirectory($evidence)
    $columns = @('servidor','fabricante_servidor','modelo_servidor','service_tag','windows','build_windows','data_coleta','modo','tipo_registro','categoria','nome_item','fabricante_item','produto_edicao','versao_instalada','versao_disponivel','arquitetura','kb_ou_id','classificacao','severidade','fonte','status','observacao','link')
    $csvPath = Join-Path $directory ('Relatorio_{0}.csv' -f $runId)
    $writer = New-Object System.IO.StreamWriter($csvPath, $false, (New-Object System.Text.UTF8Encoding($true)))
    $writer.AutoFlush = $true
    $writer.WriteLine((($columns | ForEach-Object { ConvertTo-ReportCsvCell $_ }) -join ';'))
    return (New-ReportObject @{
        Root=$Root; Directory=$directory; Evidence=$evidence; CsvPath=$csvPath; Writer=$writer
        LogPath=(Join-Path $directory 'execucao.log'); Columns=$columns; RowCount=0; Issues=0
        Mode=$Mode; RunId=$runId; Stages=(New-Object System.Collections.ArrayList)
        HostInfo=@{ servidor=$hostName; data_coleta=[DateTimeOffset]::Now.ToString('o'); modo=$Mode }
        Config=$null; StopRequested=$false
    })
}

function Add-ReportRow {
    param($Context, [hashtable]$Values)
    $fields = @()
    foreach ($column in $Context.Columns) {
        $value = ''
        if ($Context.HostInfo.ContainsKey($column)) { $value = $Context.HostInfo[$column] }
        if ($Values.ContainsKey($column)) { $value = $Values[$column] }
        $fields += (ConvertTo-ReportCsvCell $value)
    }
    $Context.Writer.WriteLine(($fields -join ';'))
    $Context.RowCount++
}

function Add-ReportStage {
    param($Context, [string]$Name, [string]$Status, [string]$Message, [int]$Count = 0)
    if ($Status -eq 'Falha' -or $Status -eq 'Parcial' -or $Status -eq 'Bloqueado' -or $Status -eq 'TempoExcedido') { $Context.Issues++ }
    [void]$Context.Stages.Add((New-ReportObject @{ Nome=$Name; Status=$Status; Mensagem=$Message; Itens=$Count; Utc=[DateTime]::UtcNow.ToString('o') }))
    Add-ReportRow $Context @{ tipo_registro='ResultadoConsulta'; categoria=$Name; nome_item=$Name; status=$Status; observacao=$Message; fonte=$Name }
    Write-ReportLog $Context ($Name + ': ' + $Status + ' - ' + $Message)
}

function Invoke-ReportStage {
    param($Context, [string]$Name, [scriptblock]$Action)
    if ($Context.StopRequested) {
        Add-ReportStage $Context $Name 'Bloqueado' 'Coleta interrompida por operacao anterior ainda em andamento.'
        return
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-ReportLog $Context ('Iniciando ' + $Name)
    try { & $Action } catch {
        Add-ReportStage $Context $Name 'Falha' $_.Exception.Message
    } finally {
        $timer.Stop()
        Write-ReportLog $Context ('Duracao de {0}: {1:n1} s' -f $Name, $timer.Elapsed.TotalSeconds)
    }
}

function Save-ReportEvidence {
    param($Context, [string]$Name, $Value)
    $path = Join-Path $Context.Evidence $Name
    $Value | Export-Clixml -Path $path -Depth 8 -Encoding UTF8
}

function Get-ReportSha256 {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $algorithm = New-Object System.Security.Cryptography.SHA256Managed
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Assert-ReportDellBinary {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)\bDell\b') {
        throw ('Assinatura Dell valida obrigatoria: ' + $Path + ' (' + $signature.Status + ').')
    }
}

function Assert-ReportPathInside {
    param([string]$Root, [string]$Path)
    $prefix = [System.IO.Path]::GetFullPath($Root).TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw ('Caminho fora da pasta permitida: ' + $resolved) }
    return $resolved
}

function Get-ReportNativeArguments {
    param([ValidateSet('Version','Inventory','Preview','Compliance','Extract','InstallTool')][string]$Operation, [string]$Target)
    switch ($Operation) {
        'Version' { return '--version' }
        'Inventory' { return '--inventory' }
        'Preview' { return '--preview' }
        'Compliance' { return '--compliance' }
        'Extract' {
            if ([string]::IsNullOrEmpty($Target) -or $Target -match '["\r\n]') { throw 'Destino de extracao invalido.' }
            return ('/s /e="' + $Target + '"')
        }
        'InstallTool' { return '/s' }
    }
}

function Invoke-ReportDellProcess {
    param($Context, [string]$Path, [string]$Operation, [string]$Label, [int]$TimeoutSeconds, [string]$Target = '')
    if ($Operation -eq 'Extract' -or $Operation -eq 'InstallTool') {
        $allowedHashes = @('2b437318e3c71d89d567498ef756f2fbcdfc4b9201406ee038efb0a2ba86fcf1','2905a5c8717a9806f76fa88af340fd4747a45c5bd846849ec0bd336ece7f6cbe')
        if ($allowedHashes -notcontains (Get-ReportSha256 $Path)) { throw 'Execucao de instalador bloqueada: somente os dois pacotes DSU fixados no codigo sao permitidos.' }
    }
    Assert-ReportDellBinary $Path
    $arguments = Get-ReportNativeArguments $Operation $Target
    $stdout = Join-Path $Context.Evidence ($Label + '.stdout.txt')
    $stderr = Join-Path $Context.Evidence ($Label + '.stderr.txt')
    Write-ReportLog $Context ('Executando ferramenta Dell: {0} {1}' -f $Path, $arguments)
    $stdin = Join-Path $Context.Evidence ($Label + '.stdin.txt')
    [IO.File]::WriteAllText($stdin, '')
    $process = Start-Process -FilePath $Path -ArgumentList $arguments -WorkingDirectory ([IO.Path]::GetDirectoryName($Path)) -WindowStyle Hidden -RedirectStandardInput $stdin -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -ErrorAction Stop
    try {
        # Windows PowerShell may lose ExitCode for redirected Start-Process calls
        # unless the native handle is acquired before waiting (PowerShell #5421).
        [void]$process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $Context.StopRequested = $true
            throw ('Tempo excedido. Processo {0} mantido em execucao, sem encerramento forcado. Evidencias: {1}. Aguarde o termino antes de nova coleta.' -f $process.Id, $stdout)
        }
        # Flush redirected asynchronous stream handlers after process exit.
        $process.WaitForExit()
        $result = New-ReportObject @{ ExitCode=$process.ExitCode; Output=[IO.File]::ReadAllText($stdout); Error=[IO.File]::ReadAllText($stderr); Path=$Path; Arguments=$arguments }
        Save-ReportEvidence $Context ($Label + '.processo.xml') $result
        if ($null -eq $result.ExitCode) {
            $Context.StopRequested = $true
            throw ('Nao foi possivel obter o codigo de saida do processo Dell {0}. Resultado indeterminado; nenhuma etapa seguinte sera executada. Consulte {1}.processo.xml em evidencias.' -f $process.Id, $Label)
        }
        Write-ReportLog $Context ('Processo Dell {0} concluido; codigo de saida: {1}.' -f $Label, $result.ExitCode)
        return $result
    } finally { $process.Dispose() }
}
