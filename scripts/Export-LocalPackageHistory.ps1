[CmdletBinding()]
param([string]$OutputPath,[string]$ModulePath,[scriptblock]$ExitRunner)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($ModulePath)){$ModulePath=Join-Path $projectRoot 'src\LocalPackageHistory.psm1'}
try{
    Import-Module $ModulePath -Force
    $arguments=@{ProjectRoot=$projectRoot};if(-not [string]::IsNullOrWhiteSpace($OutputPath)){$arguments.OutputPath=$OutputPath}
    $summary=Invoke-LocalPackageHistoryExport @arguments
}catch{
    $errorText=[string]$_.Exception.Message
    foreach($scope in @('Process','User')){foreach($name in @('DAILY_REPORT_SMTP_AUTH_CODE','PGPASSWORD','AMAZON_BS_POSTGRES_PASSWORD')){$secret=[string][Environment]::GetEnvironmentVariable($name,$scope);if(-not [string]::IsNullOrWhiteSpace($secret)-and $secret.Length-ge 4){$errorText=$errorText.Replace($secret,'[REDACTED]')}}}
    $summary=[pscustomobject]@{status='FAILED';archive_path=$OutputPath;error=$errorText}
}
foreach($propertyName in @('archive_path','staging_path','error')){
    $property=$summary.PSObject.Properties[$propertyName]
    if($null -ne $property -and $property.Value -is [string]){
        $value=[string]$property.Value
        foreach($scope in @('Process','User')){foreach($name in @('DAILY_REPORT_SMTP_AUTH_CODE','PGPASSWORD','AMAZON_BS_POSTGRES_PASSWORD')){$secret=[string][Environment]::GetEnvironmentVariable($name,$scope);if(-not [string]::IsNullOrWhiteSpace($secret) -and $secret.Length -ge 4){$value=$value.Replace($secret,'[REDACTED]')}}}
        $property.Value=$value
    }
}
$exitCode=if($summary.status -eq 'FAILED'){1}else{0}
Write-Output ($summary|ConvertTo-Json -Depth 8 -Compress)
if($null-ne $ExitRunner){& $ExitRunner $exitCode|Out-Null;return}
if($exitCode-ne 0){exit $exitCode}
