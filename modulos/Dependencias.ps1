function Assert-ReportDownloadUri {
    param([Uri]$Uri)
    if ($Uri.Scheme -ne 'https' -or @('dl.dell.com','downloads.dell.com') -notcontains $Uri.DnsSafeHost -or $Uri.UserInfo -ne '' -or -not $Uri.IsDefaultPort) { throw ('Origem de download nao permitida: ' + $Uri.AbsoluteUri) }
}

function Receive-ReportDellFile {
    param([string]$Url, [string]$Destination, [int]$TimeoutSeconds = 120)
    $uri = New-Object Uri($Url)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        # Process-local TLS setting, restored on exit; never changes SCHANNEL/registry.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072
        for ($redirect = 0; $redirect -lt 5; $redirect++) {
            Assert-ReportDownloadUri $uri
            $remaining = $TimeoutSeconds - [int]$timer.Elapsed.TotalSeconds
            if ($remaining -le 0) { throw 'Tempo total de download excedido.' }
            $request = [Net.HttpWebRequest]::Create($uri)
            $request.AllowAutoRedirect = $false
            $request.Timeout = $remaining * 1000
            $request.ReadWriteTimeout = [Math]::Min($remaining * 1000, 15000)
            $request.Proxy = $null
            $request.UserAgent = 'RelatorioServidor/1.0'
            $response = $request.GetResponse()
            try {
                if ([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -lt 400) {
                    $location = $response.Headers['Location']
                    if ([string]::IsNullOrEmpty($location)) { throw 'Redirecionamento sem destino.' }
                    $uri = New-Object Uri($uri, $location)
                    continue
                }
                if ([int]$response.StatusCode -ne 200) { throw ('Resposta HTTP inesperada: ' + $response.StatusCode) }
                if ($response.ContentLength -gt 256MB) { throw 'Download maior que o limite de 256 MB.' }
                $input = $response.GetResponseStream()
                $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew)
                try {
                    $buffer = New-Object byte[] 65536
                    $total = [int64]0
                    while (($count = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $total += $count
                        if ($total -gt 256MB -or $timer.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'Limite de tamanho ou tempo de download excedido.' }
                        $output.Write($buffer, 0, $count)
                    }
                    return
                } finally { $output.Dispose(); $input.Dispose() }
            } finally { $response.Close() }
        }
        throw 'Muitos redirecionamentos no download.'
    } finally { [Net.ServicePointManager]::SecurityProtocol = $oldProtocol; $timer.Stop() }
}

function Get-ReportDellPackage {
    param($Context, $Profile)
    $cache = Join-Path $Context.Root 'ferramentas\pacotes'
    [void][IO.Directory]::CreateDirectory($cache)
    $fileName = $Profile.GetAttribute('file')
    if ($fileName -ne [IO.Path]::GetFileName($fileName)) { throw 'Nome de pacote invalido.' }
    $destination = Assert-ReportPathInside $cache (Join-Path $cache $fileName)
    $expected = $Profile.GetAttribute('sha256')
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') { throw 'SHA-256 ausente ou invalido na matriz.' }
    if ([IO.File]::Exists($destination)) {
        if ((Get-ReportSha256 $destination) -ne $expected) { throw ('Pacote em cache com SHA-256 divergente; arquivo preservado: ' + $destination) }
        Write-ReportLog $Context ('Pacote conferido no cache: ' + $fileName)
        return $destination
    }
    $errors = @()
    foreach ($url in @($Profile.GetAttribute('url'), $Profile.GetAttribute('alternateUrl'))) {
        if ([string]::IsNullOrEmpty($url)) { continue }
        $partial = $destination + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
        try {
            Write-ReportLog $Context ('Obtendo complemento Dell: ' + $url)
            Receive-ReportDellFile $url $partial ([int]$Context.Config.Compatibilidade.Limites.downloadSegundos)
            if ((Get-ReportSha256 $partial) -ne $expected) { throw ('SHA-256 divergente no download: ' + $url) }
            [IO.File]::Move($partial, $destination)
            Save-ReportEvidence $Context ('pacote-' + $Profile.GetAttribute('id') + '.xml') @{ Url=$url; Sha256=$expected; Arquivo=$fileName; ObtidoUtc=[DateTime]::UtcNow.ToString('o') }
            return $destination
        } catch { $errors += $_.Exception.Message; Write-ReportLog $Context $_.Exception.Message 'AVISO' }
    }
    throw ('Nao foi possivel obter o complemento Dell. ' + ($errors -join ' | '))
}

function Test-ReportDellVersion {
    param([string]$Output, [string]$Expected)
    if ($Output -notmatch '(?im)(?:DELL\s+(?:EMC\s+)?System\s+Update|DSU|dsu\s*\(Dell System Update\))[^\r\n]*?\b(\d+\.\d+\.\d+(?:\.\d+)?)\b') { return $false }
    $actual = $matches[1]
    while ($actual.Split('.').Length -lt 4) { $actual += '.0' }
    while ($Expected.Split('.').Length -lt 4) { $Expected += '.0' }
    return ([Version]$actual -eq [Version]$Expected)
}

function Get-ReportInstalledDsuPaths {
    $paths = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, ($env:SystemDrive + '\Dell'))) {
        if ([string]::IsNullOrEmpty($base)) { continue }
        foreach ($relative in @('Dell\DELL EMC System Update\DSU.exe','Dell\DELL System Update\DSU.exe','Dell System Update\DSU.exe')) {
            $candidate = Join-Path $base $relative
            if ([IO.File]::Exists($candidate)) { $paths += $candidate }
        }
    }
    $command = Get-Command dsu.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $command) { $paths += $command.Definition }
    return @($paths | Select-Object -Unique)
}

function Initialize-ReportDsu {
    param($Context, $Profile)
    # Never race an existing DSU or either of the pinned installers.
    $busy = @(Get-Process -Name 'DSU','Systems-Management_Application_RT3W9_WN64_1.5.3_A00','Systems-Management_Application_5C2CW_WN64_1.9.2.0_A00' -ErrorAction SilentlyContinue)
    if ($busy.Count -gt 0) { throw 'Outra operacao Dell esta em andamento. Nenhum processo sera interrompido.' }
    $timeout = [int]$Context.Config.Compatibilidade.Limites.preparacaoSegundos
    $expected = $Profile.GetAttribute('version')
    $existing = @(Get-ReportInstalledDsuPaths)
    $index = 0
    foreach ($path in $existing) {
        $index++
        try {
            $result = Invoke-ReportDellProcess $Context $path 'Version' ('dsu-existente-' + $index) 30
            if ($result.ExitCode -eq 0 -and (Test-ReportDellVersion $result.Output $expected)) { return $path }
        } catch { if ($Context.StopRequested) { throw }; Write-ReportLog $Context $_.Exception.Message 'AVISO' }
    }
    $package = Get-ReportDellPackage $Context $Profile
    $extractRoot = Join-Path $Context.Root 'ferramentas\extraidos'
    [void][IO.Directory]::CreateDirectory($extractRoot)
    $extract = Assert-ReportPathInside $extractRoot (Join-Path $extractRoot $Context.RunId)
    $result = Invoke-ReportDellProcess $Context $package 'Extract' 'dsu-extracao' $timeout $extract
    if ($result.ExitCode -ne 0) { throw ('Extracao do complemento retornou ' + $result.ExitCode + '. Nenhuma instalacao executada.') }
    $portable = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter DSU.exe -ErrorAction Stop | Where-Object { -not $_.PSIsContainer })
    foreach ($file in $portable) {
        $result = Invoke-ReportDellProcess $Context $file.FullName 'Version' 'dsu-portatil-versao' 30
        if ($result.ExitCode -eq 0 -and (Test-ReportDellVersion $result.Output $expected)) {
            Write-ReportLog $Context 'DSU preparado na pasta do pacote por extracao.'
            return $file.FullName
        }
    }
    if ($existing.Count -gt 0) { throw 'DSU existente com versao diferente; extracao nao forneceu executavel portatil. Substituicao ou downgrade de ferramenta existente requer avaliacao explicita.' }
    # /s installs only this SHA-pinned DSU application; no /r, force or hardware DUP.
    Write-ReportLog $Context ('Instalando somente o complemento DSU ' + $expected + ', sem solicitar reinicializacao.')
    $result = Invoke-ReportDellProcess $Context $package 'InstallTool' 'dsu-instalacao' $timeout
    if ($result.ExitCode -eq 2 -or $result.ExitCode -eq 3010 -or $result.ExitCode -eq 1641) {
        $Context.StopRequested = $true
        throw ('Instalador sinalizou reinicializacao (codigo ' + $result.ExitCode + '). Nenhuma reinicializacao sera solicitada pelo relatorio.')
    }
    if ($result.ExitCode -ne 0) { throw ('Instalacao do DSU falhou: codigo ' + $result.ExitCode) }
    foreach ($path in @(Get-ReportInstalledDsuPaths)) {
        $result = Invoke-ReportDellProcess $Context $path 'Version' 'dsu-instalado-versao' 30
        if ($result.ExitCode -eq 0 -and (Test-ReportDellVersion $result.Output $expected)) { return $path }
    }
    throw 'DSU instalado nao foi localizado com a versao esperada.'
}
