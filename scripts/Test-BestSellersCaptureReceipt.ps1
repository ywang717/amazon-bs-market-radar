param(
    [Parameter(Mandatory = $true)][string]$ReceiptPath,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
$result = Test-BestSellersCaptureReceipt -ReceiptPath $ReceiptPath -RegistryPath $RegistryPath
$result | ConvertTo-Json -Depth 6
if (-not $result.valid) { exit 2 }
