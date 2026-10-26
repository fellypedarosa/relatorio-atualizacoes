#requires -version 5.1
[CmdletBinding()]
param([switch]$SemComplementos)
$ErrorActionPreference = 'Stop'
$buildRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $buildRoot 'modulos\Comum.ps1')
$buildConfig = Read-ReportXml (Join-Path $buildRoot 'configuracao\compatibilidade.xml')
if (-not $SemComplementos) {
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -File (Join-Path $buildRoot 'Principal.ps1') -Modo Preparar
    if ($LASTEXITCODE -ne 0) { throw 'Complementos incompletos. O pacote completo nao foi gerado; consulte o log de preparacao.' }
}
$buildId = [DateTime]::Now.ToString('yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$buildDist = Join-Path $buildRoot 'dist'
$buildStage = Join-Path $buildDist ('staging_' + $buildId)
$buildPackage = Join-Path $buildStage 'RelatorioServidor'
[void][IO.Directory]::CreateDirectory($buildPackage)
foreach ($file in @('Iniciar.cmd','Principal.ps1','Preparar-Pacote.cmd','Empacotar.ps1','README.md')) {
    Copy-Item -LiteralPath (Join-Path $buildRoot $file) -Destination (Join-Path $buildPackage $file)
}
foreach ($directory in @('modulos','configuracao','docs','testes')) {
    Copy-Item -LiteralPath (Join-Path $buildRoot $directory) -Destination $buildPackage -Recurse
}
$buildCache = Join-Path $buildPackage 'ferramentas\pacotes'
[void][IO.Directory]::CreateDirectory($buildCache)
if (-not $SemComplementos) {
    foreach ($profile in $buildConfig.Compatibilidade.Perfis.Perfil) {
        $source = Join-Path $buildRoot ('ferramentas\pacotes\' + $profile.GetAttribute('file'))
        if ((Get-ReportSha256 $source) -ne $profile.GetAttribute('sha256')) { throw 'Pacote Dell alterado durante o empacotamento.' }
        Copy-Item -LiteralPath $source -Destination $buildCache
    }
}
$manifest = New-Object Xml.XmlDocument
$declaration = $manifest.CreateXmlDeclaration('1.0','utf-8',$null)
[void]$manifest.AppendChild($declaration)
$packageNode = $manifest.CreateElement('Pacote')
$packageNode.SetAttribute('versao',$buildConfig.Compatibilidade.packageVersion)
$packageNode.SetAttribute('criadoUtc',[DateTime]::UtcNow.ToString('o'))
$packageNode.SetAttribute('comComplementos',(-not $SemComplementos).ToString())
[void]$manifest.AppendChild($packageNode)
foreach ($file in Get-ChildItem -LiteralPath $buildPackage -Recurse -File) {
    $node = $manifest.CreateElement('Arquivo')
    $node.SetAttribute('caminho',$file.FullName.Substring($buildPackage.Length + 1).Replace('\','/'))
    $node.SetAttribute('sha256',(Get-ReportSha256 $file.FullName))
    [void]$packageNode.AppendChild($node)
}
$manifest.Save((Join-Path $buildPackage 'manifesto-pacote.xml'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$suffix = 'complementos'
if ($SemComplementos) { $suffix = 'bootstrap' }
$buildZip = Join-Path $buildDist ('RelatorioServidor_v{0}_{1}_{2}.zip' -f $buildConfig.Compatibilidade.packageVersion,$suffix,$buildId)
[IO.Compression.ZipFile]::CreateFromDirectory($buildPackage,$buildZip,[IO.Compression.CompressionLevel]::Optimal,$true)
[IO.File]::WriteAllText(($buildZip + '.sha256'),((Get-ReportSha256 $buildZip) + '  ' + [IO.Path]::GetFileName($buildZip) + [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Output ('Pacote: ' + $buildZip)
Write-Output ('SHA-256: ' + (Get-ReportSha256 $buildZip))
