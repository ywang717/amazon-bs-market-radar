[CmdletBinding()]
param([string]$ModulePath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) { $ModulePath = Join-Path $projectRoot 'src\LocalPackageScheduledTasks.psm1' }
try {
    Import-Module $ModulePath -Force
    $summary = Register-LocalPackageScheduledTasks -ProjectRoot $projectRoot
}
catch {
    $errorText = [string]$_.Exception.Message
    foreach ($scope in @('Process','User')) {
        foreach ($name in @('DAILY_REPORT_SMTP_AUTH_CODE','PGPASSWORD','AMAZON_BS_POSTGRES_PASSWORD')) {
            $secret = [string][Environment]::GetEnvironmentVariable($name,$scope)
            if (-not [string]::IsNullOrWhiteSpace($secret) -and $secret.Length -ge 4) { $errorText = $errorText.Replace($secret,'[REDACTED]') }
        }
    }
    $summary = [pscustomobject]@{
        status = 'FAILED'
        timezone = $null
        task_names = @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Weekly-0600')
        tasks = @()
        error = $errorText
    }
}
[Console]::Out.WriteLine(($summary | ConvertTo-Json -Depth 8 -Compress))
if ($summary.status -ne 'REGISTERED') { exit 1 }
