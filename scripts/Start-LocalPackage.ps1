[CmdletBinding()]
param(
    [ValidateSet('Menu','Setup','ConfigureEmail','DailyAuto','DailyImport','Weekly','Health','Test','RegisterTasks','ExportHistory','ImportHistory')]
    [string]$Mode = 'Menu',
    [string]$MarketDate,
    [string]$SnapshotPath,
    [string]$ArchivePath,
    [string]$OutputPath,
    [switch]$SkipEmail
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($IsMacOS) {
    function global:Join-Path {
        param([string]$Path,[string]$ChildPath)
        Microsoft.PowerShell.Management\Join-Path -Path $Path -ChildPath ($ChildPath -replace '\\','/')
    }
}
Import-Module (Join-Path $projectRoot 'src\LocalPackageOrchestrator.psm1') -Force

if ($Mode -eq 'Menu') {
    Start-LocalPackageMenu
    exit 0
}

$summary = Invoke-LocalPackageMode -Mode $Mode -MarketDate $MarketDate -SnapshotPath $SnapshotPath -ArchivePath $ArchivePath -OutputPath $OutputPath -SkipEmail:$SkipEmail -ProjectRoot $projectRoot
[Console]::Out.WriteLine(($summary | ConvertTo-Json -Depth 8 -Compress))
exit ([int]$summary.exit_code)
