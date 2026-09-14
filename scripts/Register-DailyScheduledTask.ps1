param(
    [string]$TaskName = 'AmazonIntelligence-Daily-0900',
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')][string]$DailyAt = '09:00'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $PSScriptRoot 'Invoke-ScheduledDailyPipeline.ps1'
if (-not (Test-Path -LiteralPath $runnerPath)) { throw "Scheduled runner not found: $runnerPath" }

$timeParts = $DailyAt.Split(':')
$triggerTime = [DateTime]::Today.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1])
$powerShellPath = Join-Path $PSHOME 'powershell.exe'
$actionArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath
$action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $actionArguments -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $triggerTime
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 3) -MultipleInstances IgnoreNew
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description 'Amazon US Home Equipment daily collection, PostgreSQL import, report generation, and QQ email delivery.'
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null

$registered = Get-ScheduledTask -TaskName $TaskName
$registeredInfo = Get-ScheduledTaskInfo -TaskName $TaskName
[pscustomobject]@{
    Status = 'REGISTERED'
    TaskName = $registered.TaskName
    State = [string]$registered.State
    ScheduleLocalTime = $DailyAt
    TimeZone = (Get-TimeZone).Id
    RunOnlyWhenUserLoggedOn = $true
    NextRunTime = $registeredInfo.NextRunTime
    RunnerPath = $runnerPath
} | Format-List
