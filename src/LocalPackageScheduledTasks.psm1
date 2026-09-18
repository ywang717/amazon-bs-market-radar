Set-StrictMode -Version 2.0

function Invoke-LocalPackageScheduledTaskRegistration {
    param($Definition)
    $action = New-ScheduledTaskAction -Execute $Definition.Execute -Argument $Definition.Arguments -WorkingDirectory $Definition.WorkingDirectory
    $timeParts = ([string]$Definition.At).Split(':')
    if ($timeParts.Count -ne 2) { throw "Scheduled task time must use HH:mm: $($Definition.At)" }
    $hour = 0
    $minute = 0
    if (-not [int]::TryParse($timeParts[0],[ref]$hour) -or -not [int]::TryParse($timeParts[1],[ref]$minute) -or $hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59) {
        throw "Scheduled task time must use HH:mm: $($Definition.At)"
    }
    $triggerAt = [datetime]::Today.AddHours($hour).AddMinutes($minute)
    if ($Definition.Schedule -eq 'Daily') {
        $trigger = New-ScheduledTaskTrigger -Daily -At $triggerAt
    }
    else {
        $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $Definition.DaysOfWeek -At $triggerAt
    }
    $settingsParameters = @{
        StartWhenAvailable = $true
        ExecutionTimeLimit = (New-TimeSpan -Minutes $Definition.ExecutionTimeLimitMinutes)
        MultipleInstances = 'IgnoreNew'
    }
    $wakeProperty = $Definition.PSObject.Properties['WakeToRun']
    $allowBatteryProperty = $Definition.PSObject.Properties['AllowStartIfOnBatteries']
    $dontStopBatteryProperty = $Definition.PSObject.Properties['DontStopIfGoingOnBatteries']
    if ($null -ne $wakeProperty -and [bool]$wakeProperty.Value) { $settingsParameters.WakeToRun = $true }
    if ($null -ne $allowBatteryProperty -and [bool]$allowBatteryProperty.Value) { $settingsParameters.AllowStartIfOnBatteries = $true }
    if ($null -ne $dontStopBatteryProperty -and [bool]$dontStopBatteryProperty.Value) { $settingsParameters.DontStopIfGoingOnBatteries = $true }
    $settings = New-ScheduledTaskSettingsSet @settingsParameters
    $principal = New-ScheduledTaskPrincipal -UserId $Definition.UserId -LogonType Interactive -RunLevel Limited
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $Definition.Description
    Register-ScheduledTask -TaskName $Definition.TaskName -InputObject $task -Force | Out-Null
    $registered = Get-ScheduledTask -TaskName $Definition.TaskName
    $info = Get-ScheduledTaskInfo -TaskName $Definition.TaskName
    $obsoleteTaskNames = @()
    $obsoleteTaskNamesProperty = $Definition.PSObject.Properties['ObsoleteTaskNames']
    if ($null -ne $obsoleteTaskNamesProperty) {
        $obsoleteTaskNames = @($obsoleteTaskNamesProperty.Value)
    }
    else {
        $obsoleteTaskNameProperty = $Definition.PSObject.Properties['ObsoleteTaskName']
        if ($null -ne $obsoleteTaskNameProperty) {
            $obsoleteTaskNames = @($obsoleteTaskNameProperty.Value)
        }
    }
    foreach ($obsoleteTaskName in @($obsoleteTaskNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $obsoleteTask = Get-ScheduledTask -TaskName $obsoleteTaskName -ErrorAction SilentlyContinue
        if ($null -ne $obsoleteTask) {
            Unregister-ScheduledTask -TaskName $obsoleteTaskName -Confirm:$false
        }
    }
    [pscustomobject]@{
        TaskName = $Definition.TaskName
        Action = $Definition.Execute + ' ' + $Definition.Arguments
        NextRunTime = $info.NextRunTime
        Status = [string]$registered.State
    }
}

function Protect-LocalPackageScheduledTaskText {
    param([string]$Text,[scriptblock]$EnvironmentValueProvider)
    if ($null -eq $EnvironmentValueProvider) { $EnvironmentValueProvider = { param($name,$scope) [Environment]::GetEnvironmentVariable($name,$scope) } }
    $result = [string]$Text
    foreach ($scope in @('Process','User')) {
        foreach ($name in @('DAILY_REPORT_SMTP_AUTH_CODE','PGPASSWORD','AMAZON_BS_POSTGRES_PASSWORD')) {
            $secret = [string](& $EnvironmentValueProvider $name $scope)
            if (-not [string]::IsNullOrWhiteSpace($secret) -and $secret.Length -ge 4) { $result = $result.Replace($secret,'[REDACTED]') }
        }
    }
    return $result
}

function Register-LocalPackageScheduledTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [scriptblock]$TimeZoneProvider,
        [scriptblock]$IdentityProvider,
        [scriptblock]$SchedulerRunner,
        [scriptblock]$EnvironmentValueProvider
    )
    if ($null -eq $TimeZoneProvider) { $TimeZoneProvider = { (Get-TimeZone).Id } }
    if ($null -eq $IdentityProvider) { $IdentityProvider = { [Security.Principal.WindowsIdentity]::GetCurrent().Name } }
    if ($null -eq $SchedulerRunner) { $SchedulerRunner = { param($definition) Invoke-LocalPackageScheduledTaskRegistration -Definition $definition } }
    $timezone = $null
    $taskNames = @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600')
    try {
        $timezone = [string](& $TimeZoneProvider)
        if ($IsMacOS) {
            $launchDir = Join-Path $ProjectRoot '.local/launchd'
            New-Item -ItemType Directory -Path $launchDir -Force | Out-Null
            $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
            $script = Join-Path $ProjectRoot 'Start-Amazon-BS-macos.sh'
            $jobs = @(
                @{ Label='com.amazonbs.daily'; Hour=8; Minute=0; Args='-Mode DailyAuto -SkipEmail'; Program=$script },
                @{ Label='com.amazonbs.weekly'; Hour=6; Minute=0; Args='-Mode Weekly'; Program=$script },
                @{ Label='com.amazonbs.publish'; Hour=10; Minute=0; Args=''; Program=(Join-Path $ProjectRoot 'scripts/Publish-MacosDashboard.sh') }
            )
            $tasks = foreach ($job in $jobs) {
                $plist = Join-Path $launchDir ($job.Label + '.plist')
                $argumentXml = if ($job.Label -eq 'com.amazonbs.daily') { '<string>-Mode</string><string>DailyAuto</string><string>-SkipEmail</string>' } elseif ($job.Label -eq 'com.amazonbs.weekly') { '<string>-Mode</string><string>Weekly</string>' } else { '' }
                $xml = @"
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Label</key><string>$($job.Label)</string><key>ProgramArguments</key><array><string>$($job.Program)</string>$argumentXml</array><key>WorkingDirectory</key><string>$ProjectRoot</string><key>StartCalendarInterval</key><dict><key>Hour</key><integer>$($job.Hour)</integer><key>Minute</key><integer>$($job.Minute)</integer>$(if($job.Args -eq '-Mode Weekly'){'<key>Weekday</key><integer>1</integer>'})</dict><key>StandardOutPath</key><string>$(Join-Path $ProjectRoot '.local/launchd.log')</string><key>StandardErrorPath</key><string>$(Join-Path $ProjectRoot '.local/launchd-error.log')</string></dict></plist>
"@
                [IO.File]::WriteAllText($plist,$xml)
                & launchctl bootstrap "gui/$(id -u)" $plist 2>$null
                [pscustomobject]@{ TaskName=$job.Label; Status='REGISTERED'; PlistPath=$plist }
            }
            return [pscustomobject]@{ status='REGISTERED'; timezone=$timezone; task_names=@($jobs.Label); tasks=@($tasks); error=$null }
        }
        if ($timezone -cne 'China Standard Time') { throw "Scheduled task registration requires Windows timezone 'China Standard Time'; current timezone is '$timezone'." }
        $identity = [string](& $IdentityProvider)
        if ([string]::IsNullOrWhiteSpace($identity)) { throw 'The current interactive Windows user could not be resolved.' }
        $launcher = Join-Path $ProjectRoot 'scripts\Start-LocalPackage.ps1'
        $dailyLauncher = Join-Path $ProjectRoot 'scripts\Invoke-ScheduledDailyAuto.ps1'
        $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $common = @{
            Execute = $powershell
            WorkingDirectory = $ProjectRoot
            MultipleInstances = 'IgnoreNew'
            ExecutionTimeLimitMinutes = 120
            UserId = $identity
            LogonType = 'Interactive'
            RunLevel = 'Limited'
            WakeToRun = $true
            AllowStartIfOnBatteries = $true
            DontStopIfGoingOnBatteries = $true
        }
        $definitions = @(
            [pscustomobject]($common + @{ TaskName=$taskNames[0]; Schedule='Daily'; At='08:00'; DaysOfWeek=$null; Arguments=('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode Primary' -f $dailyLauncher); Description='Amazon BS daily local package run at 08:00 China Standard Time.'; ObsoleteTaskNames=@('AmazonIntelligence-Daily-0900') })
            [pscustomobject]($common + @{ TaskName=$taskNames[1]; Schedule='Daily'; At='08:30'; DaysOfWeek=$null; Arguments=('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode Recovery' -f $dailyLauncher); Description='Recover an unhealthy Amazon BS daily local package run at 08:30 China Standard Time.'; ObsoleteTaskNames=@() })
            [pscustomobject]($common + @{ TaskName=$taskNames[2]; Schedule='Weekly'; At='06:00'; DaysOfWeek='Monday'; Arguments=('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode Weekly' -f $launcher); Description='Amazon BS weekly local package run Monday at 06:00 China Standard Time.'; ObsoleteTaskNames=@('Amazon-BS-Package-Weekly-0900') })
        )
        $tasks = @($definitions | ForEach-Object { & $SchedulerRunner $_ })
        return [pscustomobject]@{
            status = 'REGISTERED'
            timezone = $timezone
            task_names = $taskNames
            tasks = $tasks
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            status = 'FAILED'
            timezone = $timezone
            task_names = $taskNames
            tasks = @()
            error = Protect-LocalPackageScheduledTaskText -Text $_.Exception.Message -EnvironmentValueProvider $EnvironmentValueProvider
        }
    }
}

Export-ModuleMember -Function Register-LocalPackageScheduledTasks
