$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$result = Invoke-Pester -Script (Join-Path $projectRoot 'tests') -PassThru
if ($result.FailedCount -gt 0) { exit 1 }

