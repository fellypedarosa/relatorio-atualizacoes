function Test-ReportAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $identity.Dispose() }
}

function Get-ReportWmi {
    param([ValidateSet('Win32_ComputerSystem','Win32_OperatingSystem','Win32_BIOS','Win32_PnPSignedDriver','Win32_ServerFeature','Win32_Service')][string]$Class, [int]$TimeoutSeconds = 60)
    $options = New-Object System.Management.EnumerationOptions
    $options.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $options.ReturnImmediately = $false
    $query = New-Object System.Management.ObjectQuery('SELECT * FROM ' + $Class)
    $scope = New-Object System.Management.ManagementScope('\\.\root\cimv2')
    $searcher = New-Object System.Management.ManagementObjectSearcher($scope, $query, $options)
    try {
        $collection = $searcher.Get()
        try { foreach ($item in $collection) { $item } }
        finally { $collection.Dispose() }
    } finally { $searcher.Dispose() }
}

function Get-ReportProfile {
    param($Config, [string]$WindowsVersion, [string]$Build, [int]$ProductType, [string]$Manufacturer, [string]$Model)
    if ($ProductType -eq 1) { throw 'A coleta completa foi projetada para Windows Server; use Demonstracao para validar o pacote localmente.' }
    $osVersion = New-Object Version($WindowsVersion)
    $majorMinor = '{0}.{1}' -f $osVersion.Major, $osVersion.Minor
    $system = $null
    foreach ($candidate in $Config.Compatibilidade.Sistemas.Sistema) {
        if ($candidate.GetAttribute('version') -eq $majorMinor -and ($candidate.GetAttribute('build') -eq '' -or $candidate.GetAttribute('build') -eq $Build)) { $system = $candidate; break }
    }
    if ($null -eq $system) { throw ('Windows nao contemplado pela matriz: ' + $WindowsVersion + ' build ' + $Build) }
    if ($Manufacturer -notmatch '(?i)\bDell\b') { return $null }
    $profile = $Config.Compatibilidade.Perfis.Perfil | Where-Object { $_.GetAttribute('id') -eq $system.GetAttribute('profile') } | Select-Object -First 1
    if ($null -eq $profile) { throw 'Perfil Dell ausente na matriz.' }
    $shortModel = ($Model -replace '(?i)^\s*PowerEdge\s+', '').Trim()
    $models = ([string]$profile.Models).Split(',')
    if ($models -notcontains $shortModel) {
        # Older PowerEdge models may require 1.5.3 even on 2012 R2/2016.
        if ($majorMinor -eq '6.3' -or ($majorMinor -eq '10.0' -and $Build -eq '14393')) {
            $legacy = $Config.Compatibilidade.Perfis.Perfil | Where-Object { $_.GetAttribute('id') -eq 'dsu-legacy' } | Select-Object -First 1
            if ($null -ne $legacy -and ([string]$legacy.Models).Split(',') -contains $shortModel) { return ,$legacy }
        }
        throw ('Modelo Dell sem combinacao documentada no perfil {0}: {1}. Nenhum instalador foi executado.' -f $profile.GetAttribute('id'), $Model)
    }
    return ,$profile
}

function Initialize-ReportHost {
    param($Context)
    if (-not (Test-ReportAdministrator)) { throw 'Abra o terminal como Administrador e execute Iniciar.cmd.' }
    if ([IntPtr]::Size -ne 8) { throw 'Use Iniciar.cmd para executar o PowerShell de 64 bits.' }
    $timeout = [int]$Context.Config.Compatibilidade.Limites.wmiSegundos
    $system = @(Get-ReportWmi 'Win32_ComputerSystem' $timeout)[0]
    $os = @(Get-ReportWmi 'Win32_OperatingSystem' $timeout)[0]
    $bios = @(Get-ReportWmi 'Win32_BIOS' $timeout)[0]
    $Context.HostInfo.fabricante_servidor = [string]$system.Manufacturer
    $Context.HostInfo.modelo_servidor = [string]$system.Model
    $Context.HostInfo.service_tag = [string]$bios.SerialNumber
    $Context.HostInfo.windows = [string]$os.Caption
    $Context.HostInfo.build_windows = [string]$os.BuildNumber
    $Context.HostInfo.version = [string]$os.Version
    $Context.HostInfo.productType = [int]$os.ProductType
    # Validate OS before any update query; model validation remains Dell-specific.
    [void](Get-ReportProfile $Context.Config $Context.HostInfo.version $Context.HostInfo.build_windows $Context.HostInfo.productType 'Validacao de sistema' '')
    $systemDrive = New-Object System.IO.DriveInfo([IO.Path]::GetPathRoot($Context.Directory))
    $minimum = [int64]$Context.Config.Compatibilidade.Limites.minimoDiscoMB * 1MB
    if ($systemDrive.AvailableFreeSpace -lt $minimum) { throw 'Espaco livre insuficiente para iniciar a coleta.' }
    Save-ReportEvidence $Context 'servidor.xml' @{
        Sistema=($system | Select-Object Manufacturer,Model,TotalPhysicalMemory,NumberOfLogicalProcessors,HypervisorPresent)
        Windows=($os | Select-Object Caption,Version,BuildNumber,OSArchitecture,ServicePackMajorVersion,ProductType,LastBootUpTime)
        BIOS=($bios | Select-Object Manufacturer,SMBIOSBIOSVersion,SerialNumber,ReleaseDate)
        PowerShell=$PSVersionTable.PSVersion.ToString(); DataUtc=[DateTime]::UtcNow.ToString('o')
    }
    Add-ReportRow $Context @{ tipo_registro='Servidor'; categoria='Inventario'; nome_item=$Context.HostInfo.servidor; status='Inventariado'; versao_instalada=$os.Version; arquitetura=$os.OSArchitecture; fonte='WMI'; observacao=('PowerShell {0}; Service Pack {1}; memoria {2} bytes.' -f $PSVersionTable.PSVersion,$os.ServicePackMajorVersion,$system.TotalPhysicalMemory) }
    Add-ReportRow $Context @{ tipo_registro='Componente'; categoria='BIOS'; nome_item='BIOS'; fabricante_item=$bios.Manufacturer; versao_instalada=$bios.SMBIOSBIOSVersion; fonte='WMI'; status='Inventariado' }
    Add-ReportStage $Context 'Ambiente' 'Concluido' 'Identificacao do servidor e verificacoes iniciais concluidas.' 2
}
