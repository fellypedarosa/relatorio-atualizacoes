function Get-ReportUninstallEntries {
    param($Context)
    $sources = New-Object System.Collections.ArrayList
    [void]$sources.Add(@{ Hive=[Microsoft.Win32.Registry]::LocalMachine; Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='Maquina'; Architecture='x64' })
    [void]$sources.Add(@{ Hive=[Microsoft.Win32.Registry]::LocalMachine; Path='SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='Maquina'; Architecture='x86' })
    try {
        foreach ($sid in [Microsoft.Win32.Registry]::Users.GetSubKeyNames()) {
            if ($sid -notmatch '^S-1-(?:5-21|12-1)-[0-9-]+$') { continue }
            foreach ($item in @(@{ Path='Software\Microsoft\Windows\CurrentVersion\Uninstall'; Architecture='x64' },@{ Path='Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Architecture='x86' })) {
                [void]$sources.Add(@{ Hive=[Microsoft.Win32.Registry]::Users; Path=($sid + '\' + $item.Path); Scope=('Usuario carregado ' + $sid); Architecture=$item.Architecture })
            }
        }
    } catch { $Context.Issues++; Write-ReportLog $Context ('Cobertura de usuarios incompleta: ' + $_.Exception.Message) 'AVISO' }
    foreach ($source in $sources) {
        $rootKey = $null
        try {
            $rootKey = $source.Hive.OpenSubKey($source.Path, $false)
            if ($null -eq $rootKey) { continue }
            foreach ($name in $rootKey.GetSubKeyNames()) {
                $key = $null
                try {
                    $key = $rootKey.OpenSubKey($name, $false)
                    if ($null -eq $key) { continue }
                    $displayName = [string]$key.GetValue('DisplayName', '')
                    if ([string]::IsNullOrEmpty($displayName)) { continue }
                    New-ReportObject @{
                        Name=$displayName; Manufacturer=[string]$key.GetValue('Publisher','')
                        Version=[string]$key.GetValue('DisplayVersion',''); Edition=''; Architecture=$source.Architecture
                        Scope=$source.Scope; Source=('Registro/' + $source.Path + '/' + $name)
                        # Never infer edition from name or read uninstall commands.
                    }
                } catch { $Context.Issues++; Write-ReportLog $Context ('Entrada de aplicativo inacessivel em ' + $source.Scope + ': ' + $_.Exception.Message) 'AVISO' }
                finally { if ($null -ne $key) { $key.Close() } }
            }
        } catch { $Context.Issues++; Write-ReportLog $Context ('Fonte de aplicativos inacessivel: ' + $source.Path + ': ' + $_.Exception.Message) 'AVISO' }
        finally { if ($null -ne $rootKey) { $rootKey.Close() } }
    }
}

function Get-ReportServiceExecutable {
    param([string]$CommandLine)
    $path = ''
    if ($CommandLine -match '^\s*"([^"\r\n]+\.exe)"(?:\s|$)') { $path = $matches[1] }
    elseif ($CommandLine -match '^\s*([^"\r\n]+?\.exe)(?:\s|$)') { $path = $matches[1].Trim() }
    if ($path -eq '') { return '' }
    $path = [Environment]::ExpandEnvironmentVariables($path)
    if ($path.StartsWith('\\') -or $path -notmatch '^[A-Za-z]:\\') { return '' }
    return $path
}

function Select-ReportApplications {
    param([object[]]$Applications)
    $seen = @{}
    foreach ($application in $Applications) {
        if ([string]::IsNullOrEmpty([string](Get-ReportValue $application 'Name'))) { continue }
        # Architecture/scope are part of identity: never collapse different installations.
        $identity = @((Get-ReportValue $application 'Name'),(Get-ReportValue $application 'Manufacturer'),(Get-ReportValue $application 'Version'),(Get-ReportValue $application 'Architecture'),(Get-ReportValue $application 'Scope'))
        $key = ($identity | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }) -join [char]31
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $application
    }
}

function Write-ReportApplications {
    param($Context, [object[]]$Applications)
    foreach ($application in $Applications) {
        $version = [string](Get-ReportValue $application 'Version')
        $edition = [string](Get-ReportValue $application 'Edition')
        $manufacturer = [string](Get-ReportValue $application 'Manufacturer')
        if ($version -eq '') { $version = 'Nao informado' }
        if ($edition -eq '') { $edition = 'Nao informado' }
        if ($manufacturer -eq '') { $manufacturer = 'Nao informado' }
        Add-ReportRow $Context @{ tipo_registro='Aplicativo'; categoria='Aplicativo'; nome_item=(Get-ReportValue $application 'Name'); fabricante_item=$manufacturer; produto_edicao=$edition; versao_instalada=$version; arquitetura=(Get-ReportValue $application 'Architecture'); fonte=(Get-ReportValue $application 'Source'); status='Inventariado'; observacao=((Get-ReportValue $application 'Scope') + '; somente inventario; versoes mais recentes nao consultadas.') }
    }
}

function Invoke-ReportApplications {
    param($Context)
    $issuesBefore = $Context.Issues
    $apps = New-Object System.Collections.ArrayList
    foreach ($application in @(Get-ReportUninstallEntries $Context)) { [void]$apps.Add($application) }
    $registered = @{}
    foreach ($application in $apps) { $registered[($application.Name + '|' + $application.Version).ToLowerInvariant()] = $true }
    try {
        $services = @(Get-ReportWmi 'Win32_Service' ([int]$Context.Config.Compatibilidade.Limites.wmiSegundos))
        foreach ($service in $services) {
            $exe = Get-ReportServiceExecutable ([string]$service.PathName)
            if ($exe -eq '' -or -not [IO.File]::Exists($exe)) { continue }
            try {
                $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
                if ([string]::IsNullOrEmpty($info.ProductName)) { continue }
                if ($info.ProductName -match '(?i)Microsoft.*Windows.*Operating System|Sistema Operacional.*Microsoft.*Windows') { continue }
                $key = ($info.ProductName + '|' + $info.ProductVersion).ToLowerInvariant()
                if ($registered.ContainsKey($key)) { continue }
                $registered[$key] = $true
                [void]$apps.Add((New-ReportObject @{ Name=$info.ProductName; Manufacturer=$info.CompanyName; Version=$info.ProductVersion; Edition=''; Architecture='Nao informada'; Scope='Servico'; Source=('Metadados/' + $exe) }))
            } catch { $Context.Issues++; Write-ReportLog $Context ('Metadados inacessiveis para o servico ' + $service.Name) 'AVISO' }
        }
    } catch { $Context.Issues++; Write-ReportLog $Context ('Complemento de inventario por servicos indisponivel: ' + $_.Exception.Message) 'AVISO' }
    $selected = @(Select-ReportApplications @($apps.ToArray()))
    Save-ReportEvidence $Context 'aplicativos.xml' $selected
    Write-ReportApplications $Context $selected
    $status = 'Concluido'
    if ($Context.Issues -gt $issuesBefore) { $status = 'Parcial' }
    Add-ReportStage $Context 'Aplicativos' $status ('Itens: {0}. Cobertura: registro da maquina, usuarios com hive carregado e metadados de executaveis de servicos locais. Portateis nao registrados e usuarios descarregados nao sao varridos.' -f $selected.Count) $selected.Count
}
