$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\LocalPackageScheduledTasks.psm1'

Describe 'Local package scheduled task registration' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'refuses registration outside China Standard Time before calling the scheduler' {
        $calls = New-Object System.Collections.ArrayList
        $result = Register-LocalPackageScheduledTasks -ProjectRoot $TestDrive -TimeZoneProvider { 'Pacific Standard Time' } -IdentityProvider { 'DOMAIN\user' } -SchedulerRunner { param($definition) [void]$calls.Add($definition) }

        $result.status | Should Be 'FAILED'
        $result.error | Should Match 'China Standard Time'
        $calls.Count | Should Be 0
    }

    It 'registers primary and recovery daily tasks plus the weekly task with resilient runtime settings' {
        $calls = New-Object System.Collections.ArrayList
        $legacy = @('AmazonIntelligence-PostgreSQLBackup-1030','Unrelated-Legacy-Task')
        $runner = {
            param($definition)
            [void]$calls.Add($definition)
            [pscustomobject]@{ TaskName=$definition.TaskName; Action=($definition.Execute+' '+$definition.Arguments); NextRunTime='2026-08-12T08:00:00+08:00'; Status='READY' }
        }.GetNewClosure()

        $result = Register-LocalPackageScheduledTasks -ProjectRoot $TestDrive -TimeZoneProvider { 'China Standard Time' } -IdentityProvider { 'DOMAIN\interactive' } -SchedulerRunner $runner

        @($calls.TaskName) | Should Be @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600')
        $expectedPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        @($calls | Select-Object -ExpandProperty Execute -Unique) | Should Be @($expectedPowerShell)
        $calls[0].Schedule | Should Be 'Daily'
        $calls[0].At | Should Be '08:00'
        $calls[0].Arguments | Should Match '-NoProfile -NonInteractive -ExecutionPolicy Bypass'
        $calls[0].Arguments | Should Match 'Invoke-ScheduledDailyAuto\.ps1" -Mode Primary$'
        @($calls[0].ObsoleteTaskNames) | Should Be @('AmazonIntelligence-Daily-0900')
        $calls[1].Schedule | Should Be 'Daily'
        $calls[1].At | Should Be '08:30'
        $calls[1].Arguments | Should Match 'Invoke-ScheduledDailyAuto\.ps1" -Mode Recovery$'
        $calls[2].Schedule | Should Be 'Weekly'
        $calls[2].DaysOfWeek | Should Be 'Monday'
        $calls[2].At | Should Be '06:00'
        @($calls[2].ObsoleteTaskNames) | Should Be @('Amazon-BS-Package-Weekly-0900')
        $calls[2].Arguments | Should Match 'Start-LocalPackage\.ps1" -Mode Weekly$'
        @($calls | Select-Object -ExpandProperty MultipleInstances -Unique) | Should Be @('IgnoreNew')
        @($calls | Select-Object -ExpandProperty ExecutionTimeLimitMinutes -Unique) | Should Be @(120)
        @($calls | Select-Object -ExpandProperty WakeToRun -Unique) | Should Be @($true)
        @($calls | Select-Object -ExpandProperty AllowStartIfOnBatteries -Unique) | Should Be @($true)
        @($calls | Select-Object -ExpandProperty DontStopIfGoingOnBatteries -Unique) | Should Be @($true)
        @($calls | Select-Object -ExpandProperty UserId -Unique) | Should Be @('DOMAIN\interactive')
        @($calls | Select-Object -ExpandProperty LogonType -Unique) | Should Be @('Interactive')
        foreach ($call in $calls) { ([string]$call.WorkingDirectory -eq [string]$TestDrive) | Should Be $true }
        $result.status | Should Be 'REGISTERED'
        $result.timezone | Should Be 'China Standard Time'
        @($result.task_names) | Should Be @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600')
        @($result.tasks.Action | Where-Object { $_ -match 'ScheduledDailyAuto|Weekly' }).Count | Should Be 3
        @($result.tasks.NextRunTime).Count | Should Be 3
        @($legacy) | Should Be @('AmazonIntelligence-PostgreSQLBackup-1030','Unrelated-Legacy-Task')
    }

    It 'updates the same exact active names on repeat registration' {
        $calls = New-Object System.Collections.ArrayList
        $runner = { param($definition) [void]$calls.Add($definition.TaskName); [pscustomobject]@{TaskName=$definition.TaskName;Action=$definition.Arguments;NextRunTime='next';Status='READY'} }.GetNewClosure()

        Register-LocalPackageScheduledTasks -ProjectRoot $TestDrive -TimeZoneProvider { 'China Standard Time' } -IdentityProvider { 'DOMAIN\interactive' } -SchedulerRunner $runner | Out-Null
        Register-LocalPackageScheduledTasks -ProjectRoot $TestDrive -TimeZoneProvider { 'China Standard Time' } -IdentityProvider { 'DOMAIN\interactive' } -SchedulerRunner $runner | Out-Null

        @($calls) | Should Be @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600','Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600')
    }

    It 'returns one redacted failure summary when registration fails' {
        $provider = { param($name,$scope) if ($scope -eq 'Process') { 'smtp-process-secret' } else { 'postgres-user-secret' } }
        $result = Register-LocalPackageScheduledTasks -ProjectRoot $TestDrive -TimeZoneProvider { 'China Standard Time' } -IdentityProvider { 'DOMAIN\interactive' } -SchedulerRunner { throw 'registration failed smtp-process-secret postgres-user-secret' } -EnvironmentValueProvider $provider
        $json = $result | ConvertTo-Json -Depth 8 -Compress

        $result.status | Should Be 'FAILED'
        $json | Should Match '\[REDACTED\]'
        $json | Should Not Match 'smtp-process-secret|postgres-user-secret'
    }

    It 'translates definitions into safe ScheduledTasks cmdlets and repeats only the exact package names' {
        Mock -CommandName New-ScheduledTaskAction -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskAction' }
        Mock -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskTrigger' }
        Mock -CommandName New-ScheduledTaskSettingsSet -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSettings' }
        Mock -CommandName New-ScheduledTaskPrincipal -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskPrincipal' }
        Mock -CommandName New-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_ScheduledTask' }
        Mock -CommandName Register-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { [pscustomobject]@{ Registered=$true } }
        Mock -CommandName Get-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { [pscustomobject]@{ State='Ready' } }
        Mock -CommandName Get-ScheduledTaskInfo -ModuleName LocalPackageScheduledTasks -MockWith { [pscustomobject]@{ NextRunTime=[datetime]'2026-08-12T08:00:00' } }
        Mock -CommandName Unregister-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { $null }

        1..2 | ForEach-Object {
            $result = Register-LocalPackageScheduledTasks -ProjectRoot 'C:\safe project' -TimeZoneProvider { 'China Standard Time' } -IdentityProvider { 'DOMAIN\interactive' }
            $result.status | Should Be 'REGISTERED'
        }

        Assert-MockCalled -CommandName New-ScheduledTaskAction -ModuleName LocalPackageScheduledTasks -Times 6 -Exactly -ParameterFilter {
            $Execute -match 'powershell\.exe$' -and $WorkingDirectory -eq 'C:\safe project' -and
            $Argument -match '^-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\\safe project\\scripts\\(Invoke-ScheduledDailyAuto|Start-LocalPackage)\.ps1" -Mode (Primary|Recovery|Weekly)$'
        }
        Assert-MockCalled -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter {
            $Daily -and $At.Hour -eq 8 -and $At.Minute -eq 0
        }
        Assert-MockCalled -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter {
            $Daily -and $At.Hour -eq 8 -and $At.Minute -eq 30
        }
        Assert-MockCalled -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter {
            $Weekly -and $WeeksInterval -eq 1 -and @($DaysOfWeek) -contains 'Monday' -and $At.Hour -eq 6 -and $At.Minute -eq 0
        }
        Assert-MockCalled -CommandName New-ScheduledTaskSettingsSet -ModuleName LocalPackageScheduledTasks -Times 6 -Exactly -ParameterFilter {
            $StartWhenAvailable -and $WakeToRun -and $AllowStartIfOnBatteries -and $DontStopIfGoingOnBatteries -and
            $MultipleInstances -eq 'IgnoreNew' -and $ExecutionTimeLimit.TotalMinutes -eq 120
        }
        Assert-MockCalled -CommandName New-ScheduledTaskPrincipal -ModuleName LocalPackageScheduledTasks -Times 6 -Exactly -ParameterFilter {
            $UserId -eq 'DOMAIN\interactive' -and $LogonType -eq 'Interactive' -and $RunLevel -eq 'Limited'
        }
        Assert-MockCalled -CommandName New-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 6 -Exactly -ParameterFilter {
            $null -ne $Action -and $null -ne $Trigger -and $null -ne $Settings -and $null -ne $Principal -and -not [string]::IsNullOrWhiteSpace([string]$Description)
        }
        Assert-MockCalled -CommandName Register-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Daily-0800' -and $Force }
        Assert-MockCalled -CommandName Register-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Daily-Recovery-0830' -and $Force }
        Assert-MockCalled -CommandName Register-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Weekly-0600' -and $Force }
        Assert-MockCalled -CommandName Register-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 0 -Exactly -ParameterFilter { $TaskName -notin @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600') }
        Assert-MockCalled -CommandName Get-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Daily-0800' }
        Assert-MockCalled -CommandName Get-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Daily-Recovery-0830' }
        Assert-MockCalled -CommandName Get-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Weekly-0600' }
        Assert-MockCalled -CommandName Get-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 0 -Exactly -ParameterFilter { $TaskName -notin @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600','Amazon-BS-Package-Weekly-0900','AmazonIntelligence-Daily-0900') }
        Assert-MockCalled -CommandName Get-ScheduledTaskInfo -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Daily-0800' }
        Assert-MockCalled -CommandName Get-ScheduledTaskInfo -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Daily-Recovery-0830' }
        Assert-MockCalled -CommandName Get-ScheduledTaskInfo -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Weekly-0600' }
        Assert-MockCalled -CommandName Get-ScheduledTaskInfo -ModuleName LocalPackageScheduledTasks -Times 0 -Exactly -ParameterFilter { $TaskName -notin @('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Daily-Recovery-0830','Amazon-BS-Package-Weekly-0600') }
        Assert-MockCalled -CommandName Unregister-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Package-Weekly-0900' }
        Assert-MockCalled -CommandName Unregister-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $TaskName -eq 'AmazonIntelligence-Daily-0900' }
        Assert-MockCalled -CommandName Unregister-ScheduledTask -ModuleName LocalPackageScheduledTasks -Times 0 -Exactly -ParameterFilter { $TaskName -notin @('Amazon-BS-Package-Weekly-0900','AmazonIntelligence-Daily-0900') }
    }

    It 'derives daily and weekly trigger values from each supplied definition' {
        Mock -CommandName New-ScheduledTaskAction -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskAction' }
        Mock -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskTrigger' }
        Mock -CommandName New-ScheduledTaskSettingsSet -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSettings' }
        Mock -CommandName New-ScheduledTaskPrincipal -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskPrincipal' }
        Mock -CommandName New-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_ScheduledTask' }
        Mock -CommandName Register-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { $null }
        Mock -CommandName Get-ScheduledTask -ModuleName LocalPackageScheduledTasks -MockWith { [pscustomobject]@{ State='Ready' } }
        Mock -CommandName Get-ScheduledTaskInfo -ModuleName LocalPackageScheduledTasks -MockWith { [pscustomobject]@{ NextRunTime='next' } }
        $common = @{ Execute='powershell.exe';Arguments='args';WorkingDirectory='C:\project';ExecutionTimeLimitMinutes=45;UserId='DOMAIN\user';Description='test' }
        $daily = [pscustomobject]($common + @{TaskName='test-daily';Schedule='Daily';At='13:45';DaysOfWeek=$null})
        $weekly = [pscustomobject]($common + @{TaskName='test-weekly';Schedule='Weekly';At='17:30';DaysOfWeek='Friday'})

        & (Get-Module LocalPackageScheduledTasks) { param($definition) Invoke-LocalPackageScheduledTaskRegistration -Definition $definition } $daily | Out-Null
        & (Get-Module LocalPackageScheduledTasks) { param($definition) Invoke-LocalPackageScheduledTaskRegistration -Definition $definition } $weekly | Out-Null

        Assert-MockCalled -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -Times 1 -Exactly -ParameterFilter { $Daily -and $At.Hour -eq 13 -and $At.Minute -eq 45 }
        Assert-MockCalled -CommandName New-ScheduledTaskTrigger -ModuleName LocalPackageScheduledTasks -Times 1 -Exactly -ParameterFilter { $Weekly -and @($DaysOfWeek) -contains 'Friday' -and $At.Hour -eq 17 -and $At.Minute -eq 30 }
        Assert-MockCalled -CommandName New-ScheduledTaskSettingsSet -ModuleName LocalPackageScheduledTasks -Times 2 -Exactly -ParameterFilter { $ExecutionTimeLimit.TotalMinutes -eq 45 }
    }
}

Describe 'Local package scheduled task script JSON boundary' {
    It 'emits exactly one JSON object on success without loading the real scheduler module' {
        $fakeModule = Join-Path $TestDrive 'SuccessScheduler.psm1'
        $source = @'
function Register-LocalPackageScheduledTasks {
    param([string]$ProjectRoot)
    [pscustomobject]@{status='REGISTERED';timezone='China Standard Time';task_names=@('Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Weekly-0600');tasks=@([pscustomobject]@{TaskName='Amazon-BS-Package-Daily-0800';Action='daily';NextRunTime='next';Status='Ready'});error=$null}
}
Export-ModuleMember -Function Register-LocalPackageScheduledTasks
'@
        [IO.File]::WriteAllText($fakeModule,$source,(New-Object Text.UTF8Encoding($false)))
        $entry = Join-Path $projectRoot 'scripts\Register-LocalPackageScheduledTasks.ps1'

        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $entry -ModulePath $fakeModule 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        $output.Count | Should Be 1
        $summary = ($output -join '') | ConvertFrom-Json
        $summary.status | Should Be 'REGISTERED'
    }

    It 'emits one redacted failed JSON object and exits nonzero when the module throws' {
        $fakeModule = Join-Path $TestDrive 'FailingScheduler.psm1'
        $source = @'
function Register-LocalPackageScheduledTasks {
    param([string]$ProjectRoot)
    throw "scheduler failed $env:DAILY_REPORT_SMTP_AUTH_CODE $env:PGPASSWORD"
}
Export-ModuleMember -Function Register-LocalPackageScheduledTasks
'@
        [IO.File]::WriteAllText($fakeModule,$source,(New-Object Text.UTF8Encoding($false)))
        $entry = Join-Path $projectRoot 'scripts\Register-LocalPackageScheduledTasks.ps1'
        $savedSmtp = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE','Process')
        $savedPg = [Environment]::GetEnvironmentVariable('PGPASSWORD','Process')
        try {
            $env:DAILY_REPORT_SMTP_AUTH_CODE = 'script-smtp-secret'
            $env:PGPASSWORD = 'script-postgres-secret'
            $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $entry -ModulePath $fakeModule 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE',$savedSmtp,'Process')
            [Environment]::SetEnvironmentVariable('PGPASSWORD',$savedPg,'Process')
        }

        $exitCode | Should Not Be 0
        $output.Count | Should Be 1
        $json = $output -join ''
        $summary = $json | ConvertFrom-Json
        $summary.status | Should Be 'FAILED'
        $json | Should Match '\[REDACTED\]'
        $json | Should Not Match 'script-smtp-secret|script-postgres-secret'
    }
}

Describe 'Operational reliability documentation' {
    It 'explains that SENT means the local SMTP client completed send, not confirmed inbox delivery' {
        $readmePath = Join-Path $projectRoot 'README.md'
        $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8

        $readme | Should Match 'SENT means the local SMTP client completed the send call'
        $readme | Should Match 'does not confirm inbox delivery'
    }
}
