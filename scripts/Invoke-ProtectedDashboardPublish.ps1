param(
    [Parameter(Mandatory = $true)][ValidateSet('Publish', 'Recovery')][string]$Mode,
    [Parameter(Mandatory = $true)][uri]$DashboardUrl,
    [string]$ProtectedSecretPath,
    [string]$TargetScript,
    [string]$ProxyUrl,
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')][string]$MarketDate,
    [scriptblock]$Operation
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProtectedSecretPath)) {
    $ProtectedSecretPath = Join-Path $projectRoot '.local\dashboard-sync-secret.dpapi'
}
if (-not (Test-Path -LiteralPath $ProtectedSecretPath -PathType Leaf)) {
    throw "Protected dashboard sync secret not found: $ProtectedSecretPath"
}

Add-Type -AssemblyName System.Security
$protectedBytes = [IO.File]::ReadAllBytes($ProtectedSecretPath)
$plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
    $protectedBytes,
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
)
$previousSecret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process')
$proxyVariableNames = @('HTTPS_PROXY', 'HTTP_PROXY', 'http_proxy')
$previousProxyValues = @{}
foreach ($proxyVariableName in $proxyVariableNames) {
    $previousProxyValues[$proxyVariableName] = [Environment]::GetEnvironmentVariable($proxyVariableName, 'Process')
}
try {
    $secret = [Text.Encoding]::UTF8.GetString($plainBytes)
    if ($secret -cnotmatch '^[0-9a-f]{64}$') { throw 'Protected dashboard sync secret is invalid.' }
    [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $secret, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        foreach ($proxyVariableName in $proxyVariableNames) {
            [Environment]::SetEnvironmentVariable($proxyVariableName, $ProxyUrl, 'Process')
        }
    }

    if ($null -ne $Operation) {
        return & $Operation $Mode $DashboardUrl $MarketDate
    }

    $expectedScript = if ($Mode -eq 'Publish') {
        Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1'
    }
    else {
        Join-Path $projectRoot 'scripts\Invoke-DashboardPublishRecovery.ps1'
    }
    if ([string]::IsNullOrWhiteSpace($TargetScript)) { $TargetScript = $expectedScript }
    if ((Resolve-Path -LiteralPath $TargetScript).Path -cne (Resolve-Path -LiteralPath $expectedScript).Path) {
        throw "Protected dashboard launcher target does not match mode: $Mode"
    }
    $targetArguments = @{ DashboardUrl = $DashboardUrl }
    if (-not [string]::IsNullOrWhiteSpace($MarketDate)) { $targetArguments.MarketDate = $MarketDate }
    return & $TargetScript @targetArguments
}
finally {
    if ($null -eq $previousSecret) {
        Remove-Item Env:AMAZON_BS_DASHBOARD_SYNC_SECRET -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $previousSecret, 'Process')
    }
    foreach ($proxyVariableName in $proxyVariableNames) {
        $previousProxyValue = $previousProxyValues[$proxyVariableName]
        if ($null -eq $previousProxyValue) {
            Remove-Item "Env:$proxyVariableName" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($proxyVariableName, $previousProxyValue, 'Process')
        }
    }
    [Array]::Clear($plainBytes, 0, $plainBytes.Length)
}
