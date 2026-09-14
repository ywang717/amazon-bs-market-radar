Set-StrictMode -Version Latest

function Write-ScheduledDailyStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$State
    )

    $temporaryPath = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    $backupPath = $Path + '.bak-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporaryPath,($State | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporaryPath,$Path,$backupPath)
        }
        else {
            [IO.File]::Move($temporaryPath,$Path)
        }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
        if ([IO.File]::Exists($backupPath)) { [IO.File]::Delete($backupPath) }
    }
}

function Invoke-ScheduledDailyPublication {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidatePattern('^\d{4}-\d{2}-\d{2}$')][string]$MarketDate)

    # Reuse the registered recovery action, including its runtime, DPAPI and proxy configuration.
    $task = Get-ScheduledTask -TaskName 'Amazon-BS-Dashboard-Publish-Recovery-0915' -ErrorAction SilentlyContinue
    if ($null -eq $task) { return [pscustomobject]@{ Status = 'NOT_CONFIGURED'; ExitCode = 0 } }
    $actions = @($task.Actions)
    if ($actions.Count -ne 1) { throw 'Dashboard recovery must have exactly one action.' }
    $action = $actions[0]
    if ($action.Arguments -match '(?i)-MarketDate\b') { throw 'Dashboard recovery action must not pin a market date.' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $action.Execute
    $start.Arguments = $action.Arguments + ' -MarketDate ' + $MarketDate
    $start.WorkingDirectory = $action.WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        Write-Host $stdout.Result
        if ($stderr.Result) { Write-Host $stderr.Result }
        $status = if ($process.ExitCode -eq 0) { 'SUCCEEDED' } else { 'FAILED' }
        return [pscustomobject]@{ Status = $status; ExitCode = $process.ExitCode }
    }
    finally { $process.Dispose() }
}

Export-ModuleMember -Function Write-ScheduledDailyStateFile,Invoke-ScheduledDailyPublication
