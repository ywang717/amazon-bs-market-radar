Set-StrictMode -Version Latest

function Get-ProjectRuntimeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root not found: $ProjectRoot"
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    [pscustomobject]@{
        ProjectRoot = $resolvedRoot
        LocalRoot = Join-Path $resolvedRoot '.local'
        BootstrapPythonPath = Join-Path $resolvedRoot '.local\python\python.exe'
        VenvRoot = Join-Path $resolvedRoot '.venv'
        VenvPythonPath = if ($IsMacOS -and (Test-Path '/usr/bin/python3')) { '/usr/bin/python3' } else { Join-Path $resolvedRoot '.venv\Scripts\python.exe' }
        PostgresSettingsPath = Join-Path $resolvedRoot '.local\postgres-settings.json'
        PostgresInstallRoot = Join-Path $resolvedRoot '.local\postgresql'
        PostgresDataRoot = Join-Path $resolvedRoot '.local\postgres-data'
    }
}

Export-ModuleMember -Function Get-ProjectRuntimeSettings
