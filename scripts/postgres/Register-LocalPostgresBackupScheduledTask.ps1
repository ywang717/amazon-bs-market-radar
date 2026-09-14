param(
    [string]$TaskName = 'AmazonIntelligence-PostgreSQLBackup-1030',
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')][string]$DailyAt = '10:30'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$backupScript = Join-Path $PSScriptRoot 'Backup-LocalPostgres.ps1'
if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) { throw "Backup script not found: $backupScript" }

$timeParts = $DailyAt.Split(':')
$triggerTime = [DateTime]::Today.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1])
$powerShellPath = Join-Path $PSHOME 'powershell.exe'
$actionArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $backupScript
$action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $actionArguments -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $triggerTime
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description 'Creates a verified PostgreSQL logical backup for Amazon Intelligence. It does not restore or delete data.'
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
    BackupScript = $backupScript
} | Format-List
