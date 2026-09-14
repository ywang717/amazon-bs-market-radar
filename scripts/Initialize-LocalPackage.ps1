[CmdletBinding()]
param(
    [string]$RecipientAddress,
    [string]$ManifestPath,
    [scriptblock]$DownloadFile,
    [scriptblock]$GetFileHash,
    [scriptblock]$InstallPython,
    [scriptblock]$InitializePythonEnvironment,
    [scriptblock]$ExtractArchive,
    [scriptblock]$PromoteDirectory,
    [scriptblock]$InitializeDatabase,
    [scriptblock]$RunMigrations,
    [scriptblock]$FindSystemBrowser,
    [scriptblock]$VerifyPythonComponent,
    [scriptblock]$VerifyPostgresComponent,
    [scriptblock]$VerifyChromiumComponent,
    [scriptblock]$InstallChromium,
    [scriptblock]$AtomicJsonWriter,
    [scriptblock]$GetPathAttributes,
    [scriptblock]$EnvironmentValueProvider
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\LocalPackageSetup.psm1') -Force
$arguments = @{ ProjectRoot = $projectRoot }
foreach ($entry in @{
    RecipientAddress = $RecipientAddress; ManifestPath = $ManifestPath; DownloadFile = $DownloadFile
    GetFileHash = $GetFileHash; InstallPython = $InstallPython; InitializePythonEnvironment = $InitializePythonEnvironment
    ExtractArchive = $ExtractArchive; PromoteDirectory = $PromoteDirectory; InitializeDatabase = $InitializeDatabase
    RunMigrations = $RunMigrations; FindSystemBrowser = $FindSystemBrowser; InstallChromium = $InstallChromium
    VerifyPythonComponent = $VerifyPythonComponent; VerifyPostgresComponent = $VerifyPostgresComponent
    VerifyChromiumComponent = $VerifyChromiumComponent; AtomicJsonWriter = $AtomicJsonWriter
    GetPathAttributes = $GetPathAttributes; EnvironmentValueProvider = $EnvironmentValueProvider
}.GetEnumerator()) {
    if ($null -ne $entry.Value -and -not ($entry.Value -is [string] -and [string]::IsNullOrWhiteSpace($entry.Value))) {
        $arguments[$entry.Key] = $entry.Value
    }
}
$summary = Invoke-LocalPackageSetup @arguments
[Console]::Out.WriteLine(($summary | ConvertTo-Json -Depth 8 -Compress))
if ($summary.status -ne 'READY') { exit 1 }
