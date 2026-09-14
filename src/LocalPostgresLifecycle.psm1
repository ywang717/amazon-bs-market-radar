Set-StrictMode -Version Latest

function Get-LocalPostgresStartupAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$IsReady,
        [Parameter(Mandatory = $true)][bool]$ServerRunning
    )

    if ($IsReady) { return 'ALREADY_READY' }
    if ($ServerRunning) { return 'RESTART' }
    return 'START'
}

function Get-LocalPostgresLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot
    )

    return Join-Path $DataRoot 'postgres-server.log'
}

Export-ModuleMember -Function 'Get-LocalPostgresStartupAction', 'Get-LocalPostgresLogPath'
