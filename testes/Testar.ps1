#requires -version 5.1
# Development tests; harmless cmd.exe child processes, no administrator,
# downloads, installers, WMI or WUA calls.
$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
foreach ($module in @('Comum','Ambiente','Dependencias','Aplicativos','WindowsUpdate','DellUpdate')) { . (Join-Path $testRoot ('modulos\' + $module + '.ps1')) }
$script:Passed = 0
$script:Failed = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-True $threw 'Era esperada uma rejeicao.'
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action; $script:Passed++; Write-Host ('OK: ' + $Name) }
    catch { $script:Failed++; Write-Host ('FALHOU: ' + $Name + ': ' + $_.Exception.Message) }
}
function Read-Fixture { param([string]$Name); return [IO.File]::ReadAllText((Join-Path $testRoot ('testes\fixtures\' + $Name))) }
function New-FakeCollection {
    param([object[]]$Items = @())
    $collection = New-ReportObject @{ Count=$Items.Count; Values=$Items }
    $collection | Add-Member ScriptMethod Item { param($index); return $this.Values[$index] }
    return $collection
}
function New-FakeWuaSearcher {
    param([int]$ResultCode, [object[]]$Updates = @(), [object[]]$Warnings = @())
    $job = New-ReportObject @{ IsCompleted=$true; Cleaned=$false; Aborted=$false }
    $job | Add-Member ScriptMethod CleanUp { $this.Cleaned=$true }
    $job | Add-Member ScriptMethod RequestAbort { $this.Aborted=$true }
    $result = New-ReportObject @{ ResultCode=$ResultCode; Updates=(New-FakeCollection $Updates); Warnings=(New-FakeCollection $Warnings) }
    $searcher = New-ReportObject @{ Job=$job; Result=$result }
    $searcher | Add-Member ScriptMethod BeginSearch { param($criteria,$callback,$state); return $this.Job }
    $searcher | Add-Member ScriptMethod EndSearch { param($job); return $this.Result }
    return $searcher
}
$testOutput = Join-Path $testRoot ('resultados\testes_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testOutput)
$config = Read-ReportXml (Join-Path $testRoot 'configuracao\compatibilidade.xml')

Test-Case 'Todos os scripts possuem sintaxe valida no PowerShell disponivel' {
    foreach ($file in Get-ChildItem -LiteralPath $testRoot -Filter '*.ps1' -Recurse | Where-Object { $_.FullName -notmatch '\\dist\\' }) {
        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        Assert-True ($parseErrors.Count -eq 0) ($file.Name + ': ' + ($parseErrors -join ';'))
    }
}
Test-Case 'Matriz seleciona os cinco Windows Server' {
    foreach ($case in @(@('6.1.7601','7601','dsu-legacy'),@('6.2.9200','9200','dsu-legacy'),@('6.3.9600','9600','dsu-modern'),@('10.0.14393','14393','dsu-modern'),@('10.0.17763','17763','dsu-modern'))) {
        $profile = Get-ReportProfile $config $case[0] $case[1] 3 'Dell Inc.' 'PowerEdge R720'
        Assert-True ($profile.GetAttribute('id') -eq $case[2]) ('Perfil incorreto para ' + $case[0])
    }
}
Test-Case 'Modelo antigo seleciona legado no Windows 2016' {
    $profile = Get-ReportProfile $config '10.0.14393' '14393' 3 'Dell Inc.' 'PowerEdge R610'
    Assert-True ($profile.GetAttribute('id') -eq 'dsu-legacy') 'Fallback de modelo incorreto.'
}
Test-Case 'Combinacao de modelo e OS sem suporte nao e presumida' {
    Assert-Throws { Get-ReportProfile $config '10.0.17763' '17763' 3 'Dell Inc.' 'PowerEdge R610' }
    Assert-Throws { Get-ReportProfile $config '10.0.20348' '20348' 3 'Dell Inc.' 'PowerEdge R720' }
    Assert-Throws { Get-ReportProfile $config '10.0.17763' '17763' 1 'Dell Inc.' 'PowerEdge R720' }
}
Test-Case 'Servidor nao Dell nao recebe instalador Dell' {
    $profile = Get-ReportProfile $config '10.0.17763' '17763' 3 'Outro fabricante' 'Modelo'
    Assert-True ($null -eq $profile) 'Nao Dell deve ser nao aplicavel.'
}
Test-Case 'Comandos nativos limitados a consultas e preparacao fixadas' {
    Assert-True ((Get-ReportNativeArguments 'Preview') -eq '--preview') 'Preview incorreto.'
    Assert-True ((Get-ReportNativeArguments 'Compliance') -eq '--compliance') 'Compliance incorreto.'
    Assert-True ((Get-ReportNativeArguments 'InstallTool') -eq '/s') 'Instalacao deve excluir reboot e force.'
    Assert-True ((Get-ReportNativeArguments 'Extract' 'C:\Pasta com espacos\DSU') -eq '/s /e="C:\Pasta com espacos\DSU"') 'Extracao com espacos incorreta.'
    Assert-Throws { Get-ReportNativeArguments 'Reboot' }
    Assert-Throws { Get-ReportNativeArguments 'NonInteractive' }
    Assert-Throws { Get-ReportNativeArguments 'Extract' 'C:\errado" /r' }
}
Test-Case 'Instalador arbitrario e rejeitado antes de assinatura ou execucao' {
    $fake = Join-Path $testOutput 'firmware-disfarcado.exe'
    [IO.File]::WriteAllText($fake, 'isto nao e o DSU')
    $blocked = $false
    try { Invoke-ReportDellProcess $null $fake 'InstallTool' 'teste' 1 } catch { $blocked = $_.Exception.Message -match 'somente os dois pacotes DSU' }
    Assert-True $blocked 'Pacote nao fixado nao foi bloqueado na primeira barreira.'
}
Test-Case 'Downloads rejeitam origens externas, HTTP e credenciais' {
    Assert-ReportDownloadUri ([Uri]'https://dl.dell.com/arquivo.exe')
    Assert-Throws { Assert-ReportDownloadUri ([Uri]'http://dl.dell.com/arquivo.exe') }
    Assert-Throws { Assert-ReportDownloadUri ([Uri]'https://dl.dell.com.exemplo.org/arquivo.exe') }
    Assert-Throws { Assert-ReportDownloadUri ([Uri]'https://usuario:senha@dl.dell.com/arquivo.exe') }
}
Test-Case 'Cache alterado falha sem tentar baixar ou executar' {
    $sandbox = Join-Path $testOutput 'cache-alterado'
    [void][IO.Directory]::CreateDirectory((Join-Path $sandbox 'ferramentas\pacotes'))
    $profile = $config.Compatibilidade.Perfis.Perfil[0]
    [IO.File]::WriteAllText((Join-Path $sandbox ('ferramentas\pacotes\' + $profile.GetAttribute('file'))), 'arquivo adulterado')
    $ctx = New-ReportObject @{ Root=$sandbox }
    Assert-Throws { Get-ReportDellPackage $ctx $profile }
}
Test-Case 'Caminhos de preparacao nao escapam da pasta dedicada' {
    $path = Assert-ReportPathInside $testOutput (Join-Path $testOutput 'filho\arquivo')
    Assert-True ($path.StartsWith($testOutput)) 'Caminho interno rejeitado.'
    Assert-Throws { Assert-ReportPathInside $testOutput (Join-Path $testOutput '..\fora') }
}
Test-Case 'SHA-256 funciona sem Get-FileHash' {
    $path = Join-Path $testOutput 'hash.txt'
    [IO.File]::WriteAllText($path,'abc',(New-Object Text.UTF8Encoding($false)))
    Assert-True ((Get-ReportSha256 $path) -eq 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') 'SHA-256 incorreto.'
}
Test-Case 'Versao DSU deve corresponder a versao fixada' {
    Assert-True (Test-ReportDellVersion 'DELL EMC System Update 1.5.3' '1.5.3.0') 'Formato legado nao reconhecido.'
    Assert-True (-not (Test-ReportDellVersion 'DELL System Update 2.3.0' '1.9.2.0')) 'Versao divergente aceita.'
    Assert-True (-not (Test-ReportDellVersion '1.9.2.0 falhou' '1.9.2.0')) 'Texto sem identificacao aceito.'
}
Test-Case 'Compliance distingue upgrade, igualdade e downgrade' {
    $result = ConvertFrom-ReportDsuUpdates (Read-Fixture 'dsu-compliance.txt')
    Assert-True ($result.Status -eq 'Concluido' -and $result.Records.Count -eq 3) 'Compliance nao interpretado.'
    Assert-True ($result.Records[0].Status -eq 'Pendente' -and $result.Records[0].Current -eq '1.0.0') 'Upgrade incorreto.'
    Assert-True ($result.Records[1].Status -eq 'ConformeCatalogo') 'Igualdade incorreta.'
    Assert-True ($result.Records[2].Status -eq 'VersaoInferiorNoCatalogo') 'Downgrade tratado como atualizacao pendente.'
}
Test-Case 'Preview vincula inventario apenas por correspondencia unica' {
    $inventory = @(ConvertFrom-ReportDsuInventory (Read-Fixture 'dsu-inventory.txt'))
    $result = ConvertFrom-ReportDsuUpdates (Read-Fixture 'dsu-preview.txt') $inventory
    Assert-True ($result.Status -eq 'Concluido' -and $result.Records.Count -eq 2) 'Preview nao interpretado.'
    Assert-True ($result.Records[0].Current -eq '1.0.0') 'Inventario nao associado.'
    $ambiguous = @($inventory[0], $inventory[0], $inventory[1])
    $result = ConvertFrom-ReportDsuUpdates (Read-Fixture 'dsu-preview.txt') $ambiguous
    Assert-True ($result.Records[0].Current -eq '') 'Associacao ambigua inventou uma versao.'
}
Test-Case 'Preview preserva dois-pontos de MAC no nome do componente' {
    $text = "Update Preview`r`n1 : Firmware : Broadcom - AA:BB:CC:DD:EE:FF : 22.71 : NIC_DEMO.EXE"
    $result = ConvertFrom-ReportDsuUpdates $text
    Assert-True ($result.Records[0].Name -eq 'Broadcom - AA:BB:CC:DD:EE:FF') 'Nome com MAC truncado.'
    Assert-True ($result.Records[0].Available -eq '22.71') 'MAC interpretado como versao.'
}
Test-Case 'Falha textual prevalece mesmo com registros DSU reconhecidos' {
    $result = ConvertFrom-ReportDsuUpdates ((Read-Fixture 'dsu-compliance.txt') + "`r`nInventory collector failed.")
    Assert-True ($result.Status -eq 'Parcial' -and $result.Records.Count -eq 3) 'Falha textual ignorada ou registros perdidos.'
}
Test-Case 'XML de configuracao rejeita DTD e entidades externas' {
    $xmlPath = Join-Path $testOutput 'dtd.xml'
    [IO.File]::WriteAllText($xmlPath,'<!DOCTYPE x [<!ENTITY e SYSTEM "file:///C:/nao-ler.txt">]><x>&e;</x>')
    Assert-Throws { Read-ReportXml $xmlPath }
}
Test-Case 'Saidas vazias, truncadas e desconhecidas nunca viram sem pendencias' {
    foreach ($text in @('',(Read-Fixture 'dsu-desconhecido.txt'),"Update Preview`r`n1 : BIOS : incompleto", "Details`r`n1 BIOS`r`nCurrent Version : desconhecida")) {
        $result = ConvertFrom-ReportDsuUpdates $text
        Assert-True ($result.Status -eq 'Parcial') ('Saida indevida: ' + $result.Status)
    }
}
Test-Case 'Zero resultados exige mensagem reconhecida e ausencia de erro' {
    $result = ConvertFrom-ReportDsuUpdates (Read-Fixture 'dsu-vazio.txt')
    Assert-True ($result.Status -eq 'SemPendencias') 'Zero explicito nao reconhecido.'
    $result = ConvertFrom-ReportDsuUpdates ((Read-Fixture 'dsu-vazio.txt') + "`r`nERROR: failed to read catalog")
    Assert-True ($result.Status -eq 'Parcial') 'Mensagem de erro foi ignorada.'
}
Test-Case 'Aplicativos preservam instalacoes distintas e eliminam duplicatas exatas' {
    $one = New-ReportObject @{ Name='Java'; Manufacturer='Exemplo'; Version='8'; Architecture='x64'; Scope='Maquina' }
    $two = New-ReportObject @{ Name='Java'; Manufacturer='Exemplo'; Version='8'; Architecture='x86'; Scope='Maquina' }
    $three = New-ReportObject @{ Name='Java'; Manufacturer='Exemplo'; Version='17'; Architecture='x64'; Scope='Maquina' }
    $result = @(Select-ReportApplications @($one,$one,$two,$three))
    Assert-True ($result.Count -eq 3) 'Deduplicacao perdeu instalacoes.'
}
Test-Case 'Extracao do caminho de servico nao executa argumentos nem acessa UNC' {
    Assert-True ((Get-ReportServiceExecutable '"C:\Program Files\Zabbix\agent.exe" --config=x') -eq 'C:\Program Files\Zabbix\agent.exe') 'Caminho entre aspas incorreto.'
    Assert-True ((Get-ReportServiceExecutable 'C:\Program Files\Zabbix\agent.exe --config=x') -eq 'C:\Program Files\Zabbix\agent.exe') 'Caminho sem aspas incorreto.'
    Assert-True ((Get-ReportServiceExecutable '\\servidor\share\agent.exe') -eq '') 'Caminho UNC aceito.'
}
Test-Case 'CSV preserva acentos, aspas, separador e quebras; protege formulas' {
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        Add-ReportRow $ctx @{ tipo_registro='Aplicativo'; nome_item="Aplicação; com `"aspas`"`r`ne linha"; versao_instalada='1.0'; status='Inventariado' }
        foreach ($name in @('=1+1',' +SUM(1,2)',"`t@SUM(1,2)",'-1+1')) { Add-ReportRow $ctx @{ nome_item=$name } }
    } finally { $ctx.Writer.Dispose() }
    $bytes = [IO.File]::ReadAllBytes($ctx.CsvPath)
    Assert-True ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'UTF-8 BOM ausente.'
    $rows = @(Import-Csv -LiteralPath $ctx.CsvPath -Delimiter ';' -Encoding UTF8)
    Assert-True ($rows.Count -eq 5 -and $rows[0].nome_item -eq "Aplicação; com `"aspas`"`r`ne linha") 'Roundtrip CSV falhou.'
    foreach ($row in $rows[1..4]) { Assert-True ($row.nome_item.StartsWith("'")) 'Formula nao neutralizada.' }
}
Test-Case 'Registro Windows oculto mantem estado sem preencher versoes inventadas' {
    $row = ConvertTo-ReportWindowsRow @{ Title='KB ficticia'; Hidden=$true; KBs=@('KB1'); ID='id'; Optional=$false }
    Assert-True ($row.status -eq 'OcultaParaAnalise') 'Oculta tratada como pendencia comum.'
    Assert-True (-not $row.ContainsKey('versao_instalada')) 'Versao instalada foi inventada.'
}
Test-Case 'Consulta WUA simulada preserva resultado parcial e avisos' {
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        $warning = New-ReportObject @{ HResult=-1; Message='Aviso simulado' }
        $searcher = New-FakeWuaSearcher 3 @() @($warning)
        $result = Invoke-ReportWuaSearch $ctx $searcher 'IsInstalled=0' 'wua-parcial' 1
        Assert-True ($result.ResultCode -eq 3 -and $result.Errors.Count -eq 1) 'Resposta parcial/aviso perdido.'
        Assert-True ($searcher.Job.Cleaned -and -not $searcher.Job.Aborted) 'Ciclo de vida da consulta incorreto.'
    } finally { $ctx.Writer.Dispose() }
}
Test-Case 'Snapshot WUA transforma COM em dados auditaveis sem inventar versoes' {
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        $update = New-ReportObject @{
            Title='Driver ficticio'; Identity=(New-ReportObject @{UpdateID='driver-id';RevisionNumber=2})
            Categories=(New-FakeCollection @((New-ReportObject @{Name='Drivers'})))
            KBArticleIDs=(New-FakeCollection @('1234')); MoreInfoUrls=(New-FakeCollection @('https://example.invalid'))
            MsrcSeverity=''; Type=2; IsHidden=$false; BrowseOnly=$true
            InstallationBehavior=(New-ReportObject @{ CanRequestUserInput=$false })
        }
        $searcher = New-FakeWuaSearcher 2 @($update)
        $result = Invoke-ReportWuaSearch $ctx $searcher 'IsInstalled=0' 'wua-driver' 1
        Assert-True ($result.Updates.Count -eq 1 -and $result.Updates[0].Type -eq 'Driver') 'Tipo do driver perdido.'
        Assert-True ($result.Updates[0].KBs[0] -eq 'KB1234') 'KB incorreta.'
    } finally { $ctx.Writer.Dispose() }
    $rows = @(Import-Csv -LiteralPath $ctx.CsvPath -Delimiter ';' -Encoding UTF8)
    Assert-True ($rows[0].versao_instalada -eq '' -and $rows[0].categoria -eq 'Microsoft/Driver') 'Snapshot alterou semantica das versoes.'
}
Test-Case 'Timeout WUA solicita cancelamento sem matar servico ou processo' {
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        $searcher = New-FakeWuaSearcher 2
        $searcher.Job.IsCompleted = $false
        Assert-Throws { Invoke-ReportWuaSearch $ctx $searcher 'IsInstalled=0' 'wua-timeout' 0 }
        Assert-True ($searcher.Job.Aborted -and $ctx.StopRequested -and -not $searcher.Job.Cleaned) 'Cancelamento invalido ou limpeza bloqueante solicitada.'
    } finally { $ctx.Writer.Dispose() }
}
Test-Case 'Servico WUA parado e bloqueado antes de criar sessao COM' {
    function Get-Service { param($Name,$ErrorAction); return (New-ReportObject @{ Status='Stopped' }) }
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        Invoke-ReportWindowsUpdate $ctx
        Assert-True ($ctx.Stages.Count -eq 1 -and $ctx.Stages[0].Status -eq 'Bloqueado') 'Servico parado nao bloqueou a consulta.'
    } finally { $ctx.Writer.Dispose() }
}
Test-Case 'Processo redirecionado preserva codigos zero e nao zero e evidencias reais' {
    # Only the Dell identity/argument checks are replaced in this test scope;
    # production cannot use this route to launch an arbitrary executable.
    function Assert-ReportDellBinary { param($Path) }
    function Get-ReportNativeArguments { param($Operation,$Target); return $Target }
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        foreach ($expected in @(0,7)) {
            for ($attempt=0; $attempt -lt 5; $attempt++) {
                $label = 'processo-real-' + $expected + '-' + $attempt
                $arguments = '/d /c "echo saida-teste& echo erro-teste 1>&2& exit /b ' + $expected + '"'
                $result = Invoke-ReportDellProcess $ctx $env:ComSpec 'Version' $label 10 $arguments
                Assert-True ($null -ne $result.ExitCode -and $result.ExitCode -eq $expected) 'Codigo real ausente ou alterado.'
                Assert-True ($result.Output -match 'saida-teste' -and $result.Error -match 'erro-teste') 'Saidas redirecionadas perdidas.'
                $evidence = Import-Clixml -LiteralPath (Join-Path $ctx.Evidence ($label + '.processo.xml'))
                Assert-True ($null -ne $evidence.ExitCode -and $evidence.ExitCode -eq $expected) 'Codigo perdido na evidencia.'
            }
        }
    } finally { $ctx.Writer.Dispose() }
}
Test-Case 'Codigo de saida ausente preserva evidencia e bloqueia continuidade' {
    function Assert-ReportDellBinary { param($Path) }
    function Start-Process {
        param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,$RedirectStandardInput,$RedirectStandardOutput,$RedirectStandardError,[switch]$PassThru,$ErrorAction)
        [IO.File]::WriteAllText($RedirectStandardOutput,'extracao simulada')
        [IO.File]::WriteAllText($RedirectStandardError,'')
        $fake = New-ReportObject @{ Handle=[IntPtr]1; Id=12345; ExitCode=$null }
        $fake | Add-Member ScriptMethod WaitForExit { param($milliseconds); if ($null -ne $milliseconds) { return $true } }
        $fake | Add-Member ScriptMethod Dispose { }
        return $fake
    }
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        $message = ''
        try { Invoke-ReportDellProcess $ctx $env:ComSpec 'Version' 'processo-sem-codigo' 10 } catch { $message=$_.Exception.Message }
        Assert-True ($ctx.StopRequested -and $message -match 'Resultado indeterminado') 'Resultado desconhecido nao bloqueou continuidade com mensagem clara.'
        $evidence = Import-Clixml -LiteralPath (Join-Path $ctx.Evidence 'processo-sem-codigo.processo.xml')
        Assert-True ($null -eq $evidence.ExitCode -and $evidence.Output -eq 'extracao simulada') 'Evidencia de resultado indeterminado perdida.'
    } finally { $ctx.Writer.Dispose() }
}
Test-Case 'Codigo DSU nao zero prevalece sobre mensagem de zero pendencias' {
    function Initialize-ReportDsu { param($Context,$Profile); return 'C:\FICTICIO\DSU.exe' }
    function Invoke-ReportDellProcess {
        param($Context,$Path,$Operation,$Label,$TimeoutSeconds)
        if ($Operation -eq 'Inventory') { return (New-ReportObject @{ ExitCode=0; Output=(Read-Fixture 'dsu-inventory.txt'); Error='' }) }
        return (New-ReportObject @{ ExitCode=5; Output=(Read-Fixture 'dsu-vazio.txt'); Error='' })
    }
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    $ctx.Config = $config
    $ctx.HostInfo.version='10.0.17763'; $ctx.HostInfo.build_windows='17763'; $ctx.HostInfo.productType=3
    $ctx.HostInfo.fabricante_servidor='Dell Inc.'; $ctx.HostInfo.modelo_servidor='PowerEdge R720'
    try {
        Invoke-ReportDellUpdate $ctx
        Assert-True ($ctx.Stages[$ctx.Stages.Count-1].Status -eq 'Falha' -and $ctx.Issues -gt 0) 'Codigo de erro virou consulta bem-sucedida.'
    } finally { $ctx.Writer.Dispose() }
}
Test-Case 'Falha de etapa preserva linhas anteriores e permite etapa independente' {
    $ctx = New-ReportContext $testRoot $testOutput 'Demonstracao'
    try {
        Invoke-ReportStage $ctx 'Primeiro' { Add-ReportRow $ctx @{ nome_item='linha antes do erro' }; throw 'falha simulada' }
        Invoke-ReportStage $ctx 'Segundo' { Add-ReportStage $ctx 'Segundo' 'Concluido' 'etapa independente' }
        Assert-True ($ctx.Issues -eq 1) 'Falha nao registrada.'
    } finally { $ctx.Writer.Dispose() }
    $rows = @(Import-Csv -LiteralPath $ctx.CsvPath -Delimiter ';' -Encoding UTF8)
    Assert-True ($rows.Count -eq 3 -and $rows[2].status -eq 'Concluido') 'Dados ou continuidade perdidos.'
}
Test-Case 'Demonstracao integrada cobre sucesso, falha, vazio e saida desconhecida' {
    foreach ($case in @(@('Normal',0),@('FalhaWindows',2),@('SemPendencias',0),@('SaidaDellDesconhecida',2))) {
        $caseOutput = Join-Path $testOutput $case[0]
        & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -File (Join-Path $testRoot 'Principal.ps1') -Modo Demonstracao -PastaSaida $caseOutput -CenarioDemo $case[0] | Out-Null
        Assert-True ($LASTEXITCODE -eq $case[1]) ('Codigo incorreto em ' + $case[0] + ': ' + $LASTEXITCODE)
        $csv = @(Get-ChildItem -LiteralPath $caseOutput -Recurse -Filter '*.csv')
        Assert-True ($csv.Count -eq 1) 'Esperado um CSV por execucao.'
        $rows = @(Import-Csv -LiteralPath $csv[0].FullName -Delimiter ';' -Encoding UTF8)
        Assert-True (@($rows | Where-Object { $_.modo -ne 'Demonstracao' }).Count -eq 0) 'Linhas sem marcacao de simulacao.'
        Assert-True (@($rows | Where-Object { $_.tipo_registro -eq 'Aplicativo' -and ($_.status -ne 'Inventariado' -or $_.versao_disponivel -ne '') }).Count -eq 0) 'Aplicativos tiveram atualizacao avaliada.'
        Assert-True ($rows[-1].tipo_registro -eq 'Resumo') 'Resumo final ausente.'
    }
}
Test-Case 'Runtime nao contem comandos de alteracao de producao' {
    $forbidden = @('Restart-Computer','Stop-Computer','Stop-Service','Restart-Service','Start-Service','Set-Service','Stop-Process','Remove-Item','Set-ExecutionPolicy','Install-WindowsUpdate','Install-WindowsFeature','Set-ItemProperty','Invoke-Expression')
    $runtimeFiles = @((Join-Path $testRoot 'Principal.ps1')) + @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'modulos') -Filter '*.ps1' | ForEach-Object { $_.FullName })
    foreach ($path in $runtimeFiles) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        $commands = $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst]}, $true)
        foreach ($command in $commands) { Assert-True ($forbidden -notcontains $command.GetCommandName()) ('Comando proibido em ' + $path) }
        $content = [IO.File]::ReadAllText($path)
        Assert-True ($content -notmatch '(?i)SELECT\s+\*\s+FROM\s+Win32_Product|CreateUpdateInstaller|\.Install\(') ('Operacao proibida em ' + $path)
    }
}
Write-Host ('Testes: {0} passaram; {1} falharam. Artefatos: {2}' -f $script:Passed,$script:Failed,$testOutput)
if ($script:Failed -gt 0) { exit 1 }
exit 0
