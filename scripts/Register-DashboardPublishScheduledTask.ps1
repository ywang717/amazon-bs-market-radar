param([Parameter(Mandatory=$true)][uri]$DashboardUrl)

$ErrorActionPreference = 'Stop'
if ([TimeZoneInfo]::Local.Id -ne 'China Standard Time') { throw 'This task must be registered in China Standard Time.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$publishPowerShell = if ($null -ne $pwshCommand -and -not [string]::IsNullOrWhiteSpace($pwshCommand.Source)) { $pwshCommand.Source } else { $windowsPowerShell }
$proxyUrl = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process')
if ([string]::IsNullOrWhiteSpace($proxyUrl)) { $proxyUrl = [Environment]::GetEnvironmentVariable('http_proxy', 'Process') }
$proxyArgument = if ([string]::IsNullOrWhiteSpace($proxyUrl)) { '' } else { ' -ProxyUrl "{0}"' -f $proxyUrl }
$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 120)
$protectedLauncher = Join-Path $projectRoot 'scripts\Invoke-ProtectedDashboardPublish.ps1'

$primaryScript = Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1'
$primaryAction = New-ScheduledTaskAction -Execute $publishPowerShell -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode Publish -DashboardUrl "{1}" -TargetScript "{2}"{3}' -f $protectedLauncher,$DashboardUrl.AbsoluteUri,$primaryScript,$proxyArgument) -WorkingDirectory $projectRoot
$primaryTrigger = New-ScheduledTaskTrigger -Daily -At '09:00'
$primaryTask = New-ScheduledTask -Action $primaryAction -Trigger $primaryTrigger -Principal $principal -Settings $settings -Description 'Publish verified Amazon BS dashboard data daily at 09:00 Beijing time.'
Register-ScheduledTask -TaskName 'Amazon-BS-Dashboard-Publish-0900' -InputObject $primaryTask -Force | Out-Null

$recoveryScript = Join-Path $projectRoot 'scripts\Invoke-DashboardPublishRecovery.ps1'
$recoveryAction = New-ScheduledTaskAction -Execute $publishPowerShell -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode Recovery -DashboardUrl "{1}" -TargetScript "{2}"{3}' -f $protectedLauncher,$DashboardUrl.AbsoluteUri,$recoveryScript,$proxyArgument) -WorkingDirectory $projectRoot
$recoveryTrigger = New-ScheduledTaskTrigger -Daily -At '09:15'
$recoveryTask = New-ScheduledTask -Action $recoveryAction -Trigger $recoveryTrigger -Principal $principal -Settings $settings -Description 'Recover the verified Amazon BS dashboard publication at 09:15 Beijing time when needed.'
Register-ScheduledTask -TaskName 'Amazon-BS-Dashboard-Publish-Recovery-0915' -InputObject $recoveryTask -Force | Out-Null

@(
    [pscustomobject]@{ Status='REGISTERED'; TaskName='Amazon-BS-Dashboard-Publish-0900'; At='09:00'; TimeZone='China Standard Time'; MultipleInstances='IgnoreNew'; LogonType='Interactive' }
    [pscustomobject]@{ Status='REGISTERED'; TaskName='Amazon-BS-Dashboard-Publish-Recovery-0915'; At='09:15'; TimeZone='China Standard Time'; MultipleInstances='IgnoreNew'; LogonType='Interactive' }
) | ConvertTo-Json
